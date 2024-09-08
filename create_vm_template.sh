#!/bin/bash

# Variables
MEMORY=2048
CORES=2
BRIDGE="vmbr0"
STORAGE="local-lvm"  # Change to your storage choice
DISK_SIZE="16G"  # Desired disk size after expansion

# Array of VM details: (VM_ID, VM_NAME, IMG_URL)
VM_DETAILS=(
    "10010 rockylinux-9.4 https://mirror.aarnet.edu.au/pub/rocky/9.4/images/x86_64/Rocky-9-GenericCloud-Base-9.4-20240509.0.x86_64.qcow2"
    "10020 debian-12 https://cloud.debian.org/images/cloud/bookworm/20240901-1857/debian-12-generic-amd64-20240901-1857.qcow2"
    "10030 ubuntu-24.10 https://cloud-images.ubuntu.com/oracular/current/oracular-server-cloudimg-amd64.img"
)

# Function to create and configure VM
create_vm() {
    VM_ID=$1
    VM_NAME=$2
    IMG_URL=$3
    IMG_FILE="${VM_NAME}.qcow2"

    echo "---------------------------------"
    echo "Processing VM: $VM_NAME (ID: $VM_ID)"
    echo "---------------------------------"

    # Step 1: Download Ubuntu Cloud Image
    echo "Downloading Ubuntu Cloud Image for $VM_NAME..."
    wget $IMG_URL -O $IMG_FILE

    # Step 2: Resize the disk image to 16GB
    echo "Resizing disk image for $VM_NAME to $DISK_SIZE..."
    qemu-img resize $IMG_FILE $DISK_SIZE

    # Step 3: Create a new virtual machine
    echo "Creating VM $VM_NAME..."
    qm create $VM_ID --memory $MEMORY --core $CORES --name $VM_NAME --net0 virtio,bridge=$BRIDGE

    # Step 4: Import the downloaded disk to local storage
    echo "Importing disk for $VM_NAME to storage..."
    qm disk import $VM_ID $IMG_FILE $STORAGE

    # Step 5: Attach the disk as a SCSI drive on the SCSI controller
    echo "Attaching disk for $VM_NAME as SCSI drive..."
    qm set $VM_ID --scsihw virtio-scsi-pci --scsi0 $STORAGE:vm-$VM_ID-disk-0

    # Step 6: Add cloud-init drive
    echo "Adding cloud-init drive for $VM_NAME..."
    qm set $VM_ID --ide2 $STORAGE:cloudinit

    # Step 7: Make cloud-init drive bootable and restrict BIOS to boot from disk only
    echo "Setting boot options for $VM_NAME..."
    qm set $VM_ID --boot c --bootdisk scsi0

    # Step 8: Add serial console
    echo "Adding serial console for $VM_NAME..."
    qm set $VM_ID --serial0 socket --vga serial0

    # DO NOT START VM (automatically avoided in script)

    # Optional: Install necessary tools and guest agent before importing the image
    echo "Installing libguestfs-tools..."
    apt install -y libguestfs-tools

    echo "Installing qemu-guest-agent on $VM_NAME image..."
    virt-customize -a $IMG_FILE --install qemu-guest-agent

    # Enable agent in VM settings
    echo "Enabling agent in VM settings for $VM_NAME..."
    qm set $VM_ID --agent 1,fstrim_cloned_disks=1

    # Clear machine-id in the image to allow regeneration on first boot
    echo "Clearing machine ID in $VM_NAME image..."
    virt-customize -a $IMG_FILE --run-command "sudo truncate -s 0 /etc/machine-id /var/lib/dbus/machine-id"

    # Step 9: Create VM template
    echo "Creating VM template for $VM_NAME..."
    qm template $VM_ID

    echo "VM $VM_NAME (ID: $VM_ID) is ready with expanded disk!"
    echo "---------------------------------"
}

# Iterate over each VM entry in the array
for VM in "${VM_DETAILS[@]}"; do
    # Split the VM entry into separate variables
    VM_ID=$(echo $VM | awk '{print $1}')
    VM_NAME=$(echo $VM | awk '{print $2}')
    IMG_URL=$(echo $VM | awk '{print $3}')
    
    # Call the function to create the VM
    create_vm $VM_ID $VM_NAME $IMG_URL
done
