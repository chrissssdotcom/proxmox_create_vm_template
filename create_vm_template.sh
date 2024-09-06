#!/bin/bash

# Define variables
MEM=2048              # Amount of RAM in MB
NET_BRIDGE="vmbr0"    # Network bridge, e.g., vmbr0
DISK_STOR="local" # Disk storage, e.g., local-lvm
CPU_CORES=2           # Number of CPU cores
DISK_SIZE="32G"       # Disk size
CLOUD_DIR="/var/lib/vz/cloudready"  # Directory to store images

# List of image URLs to download
IMAGES_URLS=(
  "https://mirror.aarnet.edu.au/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"
  "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
  "https://cloud-images.ubuntu.com/releases/jammy/release/ubuntu-22.04-server-cloudimg-amd64.img"
  # Add more images here
)

# Initialize unique VMID
START_VMID=10000

# Download images if they do not exist
mkdir -p "$CLOUD_DIR"

for IMG_URL in "${IMAGES_URLS[@]}"; do
  IMG_PATH="$CLOUD_DIR/$(basename $IMG_URL)"
  if [ ! -f "$IMG_PATH" ]; then
    wget -P "$CLOUD_DIR" "$IMG_URL"
  else
    echo "File $IMG_PATH already exists, skipping download."
  fi
done

# Function to create a VM template
create_template() {
  local img_name="$1"
  local vmid="$2"

  # Generate template name based on the first two segments of the image file name
  local templ_name=$(basename "$img_name" .qcow2)
  templ_name=$(basename "$templ_name" .img)  # Handle both .img and .qcow2
  templ_name=$(echo "$templ_name" | cut -d'-' -f1-2)

  # Append '-template' to the template name
  templ_name="${templ_name}-template"

  # Remove existing VM if a template with the same name already exists
  if qm list | grep -qw "$templ_name"; then
    local existing_vmid=$(qm list | grep -w "$templ_name" | awk '{print $1}')
    echo "Template with name $templ_name already exists with VMID $existing_vmid. Removing..."
    qm destroy "$existing_vmid" --purge
  fi

  # Create a new virtual machine
  virt-customize -a "$img_name" --install qemu-guest-agent
  qm create "$vmid" --name "$templ_name" --memory $MEM --net0 virtio,bridge=$NET_BRIDGE
  qm importdisk "$vmid" "$img_name" $DISK_STOR
  qm set "$vmid" --scsihw virtio-scsi-pci --scsi0 $DISK_STOR:vm-$vmid-disk-0
  qm set "$vmid" --ide2 $DISK_STOR:cloudinit
  qm set "$vmid" --boot c --bootdisk scsi0
  qm set "$vmid" --ipconfig0 ip=dhcp
  qm set "$vmid" --cores $CPU_CORES
  qm resize "$vmid" scsi0 $DISK_SIZE
  qm template "$vmid"
  echo "Virtual machine template $templ_name has been created with VMID $vmid."
}

# Create templates for all downloaded images
for IMG_URL in "${IMAGES_URLS[@]}"; do
  IMG_PATH="$CLOUD_DIR/$(basename $IMG_URL)"
  create_template "$IMG_PATH" "$START_VMID"
  START_VMID=$((START_VMID + 1)) # Increment VMID for the next machine
done

# Remove downloaded images after creating templates
for IMG_URL in "${IMAGES_URLS[@]}"; do
  IMG_PATH="$CLOUD_DIR/$(basename $IMG_URL)"
  rm -f "$IMG_PATH"
done
