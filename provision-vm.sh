#!/bin/bash
# Provisions a single VM
set -eo pipefail

if [ -z "$1" ]; then
    echo "Usage: $0 <path-to-vm-config-file>"
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
log_param "Location" "$LOCATION"
log_param "VM SKU" "$SKU"
# Remove trailing dash from VM_NAME_PREFIX because it's an invalid tailing character for VM names
VM_NAME=$(echo $VM_NAME_PREFIX | sed 's/-$//')
log_param "VM Name" "$VM_NAME"
log_param "Image" "$IMAGE"
log_param "Admin Username" "$ADMIN"
log_param "SSH Key Path" "$SSH_PATH"
log_param "Cloud Init File" "$CLOUD_INIT"

log_header "TAGS"
for tag in "${TAGS[@]}"; do
    # Split tag into key and value
    IFS='=' read -r key value <<< "$tag"
    log_param "$key" "$value"
done

#Constants used in the script
DISK_SIZE_GB=256

log_header "PROVISIONING VM"
# Create the resource group if it doesn't exist
if [[ $(az group exists --name "$RESOURCE_GROUP") == "false" ]]; then
    log_info "Creating resource group: $RESOURCE_GROUP"
    az group create --name $RESOURCE_GROUP --location $LOCATION
else
    log_info "Resource group already exists: $RESOURCE_GROUP"
fi

az vm create \
    --resource-group $RESOURCE_GROUP \
    --name $VM_NAME \
    --image $IMAGE \
    --size  $SKU \
    --os-disk-size-gb $DISK_SIZE_GB \
    --location $LOCATION \
    --admin-username $ADMIN \
    --ssh-key-values $SSH_PATH \
    --custom-data $CLOUD_INIT