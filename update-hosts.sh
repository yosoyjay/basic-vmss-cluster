#!/bin/bash
# Update hostfile and hostfile-ip with current set of VMs in the scale set

set -eo pipefail

if [ -z "$1" ]; then
    echo "Usage: $0 <path-to-cluster-config-file>"
    exit 1
fi
source "$1"
PUBLIC_IP_NAME="${VMSS_NAME}-public-ip"

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

log_header "CONFIGURATION PARAMETERS"
log_param "Resource Group" "$RESOURCE_GROUP"
log_param "VMSS Name" "$VMSS_NAME"
log_param "Location" "$LOCATION"
log_param "Public IP" "$PUBLIC_IP_NAME"
log_header "UPDATING HOSTS"

# Constants used in the script
HOSTFILE="hostfile"
IP_HOSTFILE="hostfile-ip"

# Save hostnames in file and copy to headnode
PUBLIC_IP=$(az network public-ip show --resource-group $RESOURCE_GROUP --name $PUBLIC_IP_NAME --query "ipAddress" -o tsv)
log_info "Using headnode public IP: $PUBLIC_IP"

log_info "Generating hostfile with VMSS hostnames and copying to headnode"
az vm list --resource-group $RESOURCE_GROUP --query "[?virtualMachineScaleSet.id!=null].{hostname:osProfile.computerName}" -o tsv > $HOSTFILE
scp $HOSTFILE $ADMIN@$PUBLIC_IP:$HOSTFILE

# Generate hostfile with IPs on headnode
log_info "Generating hostfile with IPs ($IP_HOSTFILE)"
ssh $ADMIN@$PUBLIC_IP "parallel-ssh -h $HOSTFILE -i \"ip addr show eth0 | grep 'inet ' | awk '{ print \$2 }' | cut -d'/' -f1\" | grep -oP 'inet \K[\d.]+' > $IP_HOSTFILE"