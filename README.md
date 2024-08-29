# Virtual Machine Template Creation Script for PROXMOX

## Description

This Bash script automatically downloads disk images from external sources, creates virtual machine templates from these images, and deletes the downloaded image files after the process is complete. It supports both `.qcow2` and `.img` file formats.

## Features

- **Download Images:** Downloads disk images from specified URLs if they are not already present in the local directory.
- **Create Templates:** Creates virtual machine templates based on the downloaded images. Template names are generated from the first two segments of the image file name, with an added `-template` suffix.
- **Remove Existing Templates:** If a template with the same name already exists, it is deleted before creating a new template.
- **Cleanup:** Deletes the downloaded image files after they have been used.

## Requirements

- Proxmox VE (for `qm` and `virt-customize` commands)
- `wget` (for downloading files)
- `virt-customize` (for image customization)

## Usage

1. **Install Required Tools:**
   - `wget` and `virt-customize` are available in most Linux distributions and can be installed using the package manager.

2. **Configure the List of Images:**
   - Edit the `IMAGES_URLS` list in the script to add or remove URLs of the images you want to download and process.

3. **Run the Script:**

   ```bash
   ./create_vm_template.sh
   ```
