#!/bin/bash
# Provision a VMSS cluster without scheduler, but a head node.
# - Creates a VMSS, VNet, load balancer with public IP, public IP for headnode (first VM in scale set because load balancer is unreliable).
# - Generates SSH key on headnode and distributes it to all VMs in the scale set.
# - Generates hostfile with VMSS hostnames(hostfile) and IPs (hostfile-ip) on headnode.
set -eo pipefail

if [ -z "$1" ]; then
    echo "Usage: $0 <path-to-cluster-config-file>"
    exit 1
fi
source "$1"

# Function for formatted logging
log_info() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[INFO] ${timestamp} - $1"
}

log_header() {
    echo -e "\n=== $1 ==="
}

log_param() {
    printf "  %-25s %s\n" "$1:" "$2"
}

# Log the configuration
log_header "VMSS CLUSTER PROVISIONING"
log_info "Starting provisioning with configuration from $1"

# Display parameters
log_header "CONFIGURATION PARAMETERS"
log_param "Resource Group" "$RESOURCE_GROUP"
log_param "VMSS Name" "$VMSS_NAME"
log_param "Location" "$LOCATION"
log_param "VM SKU" "$SKU"
log_param "Image" "$IMAGE"
log_param "Instance Count" "$INSTANCE_COUNT"
log_param "VM Name Prefix" "$VM_NAME_PREFIX"
log_param "Admin Username" "$ADMIN"
log_param "Orchestration Mode" "$ORCH_MODE"
log_param "SSH Key Path" "$SSH_PATH"
log_param "Cloud Init File" "$CLOUD_INIT"

log_header "TAGS"
for tag in "${TAGS[@]}"; do
    # Split tag into key and value
    IFS='=' read -r key value <<< "$tag"
    log_param "$key" "$value"
done

# Constants used in the script
HOSTFILE="hostfile"
IP_HOSTFILE="hostfile-ip"
PUBLIC_IP_NAME="${VMSS_NAME}-public-ip"
HEADNODE_PUBLIC_KEY="id_rsa.pub"
HEADNODE_PRIVATE_KEY="id_rsa"
DISK_SIZE_GB=256

# Handle VMSS orchestration differences
# UNIFORM
# --single-placement-group true
# --disable-overprovision
# FLEX
# --single-placement-group false
VMSS_ORCH_ARGS=""
if [ "$ORCH_MODE" == "Uniform" ] || [ "$ORCH_MODE" == "uniform" ]; then
    VMSS_ORCH_ARGS="--single-placement-group true --disable-overprovision"
elif [ "$ORCH_MODE" == "Flexible" ] || [ "$ORCH_MODE" == "flexible" ]; then
    VMSS_ORCH_ARGS="--single-placement-group false"
else
    log_info "Invalid orchestration mode: $ORCH_MODE"
    exit 1
fi
# Add tags
TAG_ARGS=""
for tag in "${TAGS[@]}"; do
    TAG_ARGS+="--tags $tag "
done

log_header "PROVISIONING CLUSTER"
# Create the resource group if it doesn't exist
if [[ $(az group exists --name "$RESOURCE_GROUP") == "false" ]]; then
    log_info "Creating resource group: $RESOURCE_GROUP"
    az group create --name $RESOURCE_GROUP --location $LOCATION
else
    log_info "Resource group already exists: $RESOURCE_GROUP"
fi

# Create the VMSS
az vmss create \
    --name $VMSS_NAME \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --image $IMAGE \
    --vm-sku $SKU \
    --computer-name-prefix $VM_NAME_PREFIX \
    --instance-count $INSTANCE_COUNT \
    --custom-data $CLOUD_INIT \
    --accelerated-networking true \
    --admin-username $ADMIN \
    --ssh-key-values $SSH_PATH \
    --os-disk-size-gb $DISK_SIZE_GB \
    --authentication-type ssh \
    --orchestration-mode $ORCH_MODE \
    --security-type standard \
    $TAG_ARGS \
    $VMSS_ORCH_ARGS

# Create public IP and attach to NIC of headnode (10.0.0.4)
# - More reliable than using load balancer
NIC_NAME=$(az network nic list -g $RESOURCE_GROUP --query "[?ipConfigurations[?privateIPAddress=='10.0.0.4']].name" -o tsv)
IP_CONFIG_NAME=$(az network nic show --resource-group $RESOURCE_GROUP --name $NIC_NAME --query "ipConfigurations[].name" -o tsv)

log_info "Creating public IP for head node: $PUBLIC_IP_NAME"

az network public-ip create \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --name $PUBLIC_IP_NAME \
    --allocation-method Static \
    --sku Standard

az network nic ip-config update \
    --resource-group $RESOURCE_GROUP \
    --nic-name $NIC_NAME \
    --public-ip-address $PUBLIC_IP_NAME \
    --name $IP_CONFIG_NAME

# Retrieve and print the public IP
PUBLIC_IP=$(az network public-ip show --resource-group $RESOURCE_GROUP --name $PUBLIC_IP_NAME --query "ipAddress" -o tsv)
log_info "Headnode public IP assigned: $PUBLIC_IP"

# Save hostnames in file and copy to headnode
log_info "Generating hostfile with VMSS hostnames and copying to headnode"
az vm list --resource-group $RESOURCE_GROUP --query "[?virtualMachineScaleSet.id!=null].{hostname:osProfile.computerName}" -o tsv > $HOSTFILE
scp hostfile $ADMIN@$PUBLIC_IP:$HOSTFILE

# Wait until the headnode is up and running
log_info "Waiting for headnode to be up and running"
while ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 $ADMIN@$PUBLIC_IP "echo 'Headnode is alive'" 2>/dev/null; do
    log_info " - Waiting for headnode to be reachable..."
    sleep 5
done

# Generate key on headnode (10.0.0.4)
log_info "Generating key-pair on headnode"
ssh $ADMIN@$PUBLIC_IP "if [ ! -f ~/.ssh/$HEADNODE_PRIVATE_KEY ]; then ssh-keygen -t rsa -b 4096 -f ~/.ssh/$HEADNODE_PRIVATE_KEY -N '' -q; fi"

# Add public key of headnode to all VMs in the scale set from the headnode
log_info "Adding public key to all VMs in the scale set"
scp $ADMIN@$PUBLIC_IP:~/.ssh/$HEADNODE_PUBLIC_KEY .

while IFS= read -r host; do
    log_info "- $host"
    # Use -f to force addition of public key without matching private key locally and connect through headnode
    # Redirect /dev/null to stdin to avoid interacting with loop
    # Send to background to avoid waiting for each ssh-copy-id
    ssh-copy-id -f -i $HEADNODE_PUBLIC_KEY -o ProxyCommand="ssh -W %h:%p $ADMIN@$PUBLIC_IP" $ADMIN@$host < /dev/null &
done < $HOSTFILE
wait

rm $HEADNODE_PUBLIC_KEY

# Add IP hostfile
log_info "Generating hostfile with IPs (hostfile-ip)"
ssh $ADMIN@$PUBLIC_IP "parallel-ssh -h $HOSTFILE -i \"ip addr show eth0 | grep 'inet ' | awk '{ print \$2 }' | cut -d'/' -f1\" | grep -oP 'inet \K[\d.]+' > $IP_HOSTFILE"