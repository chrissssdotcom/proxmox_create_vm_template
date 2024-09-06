#!/bin/bash

# Ensure dialog is installed
if ! command -v dialog &> /dev/null
then
    echo "Dialog could not be found, installing..."
    apt-get update && apt-get install -y dialog
fi

# Function to list network bridges
list_bridges() {
  echo $(brctl show | awk 'NR>1 {print $1}')
}

# Function to list available storages
list_storages() {
  echo $(pvesm status | awk 'NR>1 {print $1}')
}

# Define cloud directory
CLOUD_DIR="/var/lib/vz/cloudready"

# List of predefined image URLs to download
IMAGES_URLS=(
  "Rocky Linux 9:https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
  "Debian 12:https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
  "Ubuntu 22.04:https://cloud-images.ubuntu.com/releases/jammy/release/ubuntu-22.04-server-cloudimg-amd64.img"
)

# Initialize unique VMID
START_VMID=9001

# Request RAM in GB using dialog
dialog --inputbox "Enter RAM size (GB):" 8 40 2>ram_input.txt
MEM_GB=$(cat ram_input.txt)
MEM=$((MEM_GB * 1024))  # Convert to MB
rm ram_input.txt

# List network bridges and choose one
BRIDGES=$(list_bridges)
dialog --menu "Select Network Bridge" 15 40 6 $(for bridge in $BRIDGES; do echo "$bridge - $bridge"; done) 2>net_bridge.txt
NET_BRIDGE=$(cat net_bridge.txt)
rm net_bridge.txt

# List available storage and choose one
STORAGES=$(list_storages)
dialog --menu "Select Disk Storage" 15 40 6 $(for storage in $STORAGES; do echo "$storage - $storage"; done) 2>disk_storage.txt
DISK_STOR=$(cat disk_storage.txt)
rm disk_storage.txt

# Request disk size using dialog
dialog --inputbox "Enter Disk Size (e.g., 32G):" 8 40 2>disk_size.txt
DISK_SIZE=$(cat disk_size.txt)
rm disk_size.txt

# Request CPU cores using dialog
dialog --inputbox "Enter number of CPU cores:" 8 40 2>cpu_cores.txt
CPU_CORES=$(cat cpu_cores.txt)
rm cpu_cores.txt

# Show a dialog with checkboxes to select predefined images to download
IMAGE_OPTIONS=()
for img in "${IMAGES_URLS[@]}"; do
  IMAGE_OPTIONS+=("$(echo "$img" | cut -d':' -f1)" "Download" "off")
done

dialog --checklist "Select images to download:" 15 40 6 "${IMAGE_OPTIONS[@]}" 2>selected_images.txt
SELECTED_IMAGES=$(cat selected_images.txt)
rm selected_images.txt

# Allow user to input a custom qcow2 image URL
dialog --inputbox "Enter a custom qcow2 image URL (leave empty if none):" 8 40 2>custom_image.txt
CUSTOM_IMAGE_URL=$(cat custom_image.txt)
rm custom_image.txt

# Create a list of image URLs to download based on the selection
IMAGES_TO_DOWNLOAD=()

# Map the selected images back to URLs
for img_name in $SELECTED_IMAGES; do
  for img in "${IMAGES_URLS[@]}"; do
    if [[ "$img" == "$img_name:"* ]]; then
      IMAGES_TO_DOWNLOAD+=("$(echo "$img" | cut -d':' -f2)")
    fi
  done
done

# Add the custom image URL if provided
if [[ -n "$CUSTOM_IMAGE_URL" ]]; then
  IMAGES_TO_DOWNLOAD+=("$CUSTOM_IMAGE_URL")
fi

# Download selected images if they do not exist
mkdir -p "$CLOUD_DIR"

for IMG_URL in "${IMAGES_TO_DOWNLOAD[@]}"; do
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
  qm set "$vmid" --vga std   # Default VGA display output
  qm set "$vmid" --serial0 socket  # Serial port for future usage but not main display
  qm set "$vmid" --ipconfig0 ip=dhcp
  qm set "$vmid" --cores $CPU_CORES
  qm resize "$vmid" scsi0 $DISK_SIZE
  qm template "$vmid"
  echo "Virtual machine template $templ_name has been created with VMID $vmid."
}

# Create templates for all downloaded images
for IMG_URL in "${IMAGES_TO_DOWNLOAD[@]}"; do
  IMG_PATH="$CLOUD_DIR/$(basename $IMG_URL)"
  create_template "$IMG_PATH" "$START_VMID"
  START_VMID=$((START_VMID + 1)) # Increment VMID for the next machine
done

# Optionally remove downloaded images after creating templates
for IMG_URL in "${IMAGES_TO_DOWNLOAD[@]}"; do
  IMG_PATH="$CLOUD_DIR/$(basename $IMG_URL)"
  rm -f "$IMG_PATH"
done
