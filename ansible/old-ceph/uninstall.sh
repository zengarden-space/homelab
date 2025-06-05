#!/bin/bash
# filepath: /home/oleksiyp/dev/basic-infra/ansible/ceph/uninstall.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}WARNING: This will completely remove Ceph cluster and ALL DATA!${NC}"
echo -e "${YELLOW}This action cannot be undone.${NC}"
echo ""
read -p "Are you sure you want to proceed? (type 'yes' to continue): " confirmation

if [ "$confirmation" != "yes" ]; then
    echo -e "${YELLOW}Uninstallation cancelled.${NC}"
    exit 0
fi

echo -e "${RED}Starting Ceph cluster uninstallation...${NC}"

# Check if required files exist
if [ ! -f "hosts.yaml" ]; then
    echo -e "${RED}Error: hosts.yaml not found${NC}"
    exit 1
fi

if [ ! -f "uninstall.yaml" ]; then
    echo -e "${RED}Error: uninstall.yaml not found${NC}"
    exit 1
fi

# Source environment if exists
if [ -f ".env" ]; then
    echo -e "${YELLOW}Loading environment variables...${NC}"
    source .env
fi

# Check if ansible is available
if ! command -v ansible-playbook &> /dev/null; then
    echo -e "${RED}Error: ansible-playbook not found. Please install Ansible.${NC}"
    exit 1
fi

# Ask about disk cleanup and optional components
echo ""
echo -e "${YELLOW}Optional cleanup options:${NC}"
read -p "Do you want to remove Docker components? (y/N): " remove_docker
read -p "Do you want to remove system packages (chrony, lvm2, gdisk, parted)? (y/N): " remove_packages
read -p "Do you want to clean up disk partitions created by Ceph? (y/N): " cleanup_disks

EXTRA_VARS=""
if [[ "$remove_docker" =~ ^[Yy]$ ]]; then
    EXTRA_VARS="$EXTRA_VARS -e remove_docker=true"
    echo -e "${YELLOW}Will remove Docker components${NC}"
fi

if [[ "$remove_packages" =~ ^[Yy]$ ]]; then
    EXTRA_VARS="$EXTRA_VARS -e remove_system_packages=true"
    echo -e "${YELLOW}Will remove system packages${NC}"
fi

if [[ "$cleanup_disks" =~ ^[Yy]$ ]]; then
    EXTRA_VARS="$EXTRA_VARS -e cleanup_disks=true"
    echo -e "${RED}WARNING: This will wipe Ceph-created partitions on all disks!${NC}"
    read -p "Are you absolutely sure? (type 'yes' to continue): " disk_confirmation
    if [ "$disk_confirmation" != "yes" ]; then
        echo -e "${YELLOW}Disk cleanup cancelled. Proceeding with software-only removal.${NC}"
        EXTRA_VARS=$(echo "$EXTRA_VARS" | sed 's/-e cleanup_disks=true//')
    fi
fi

# Run pre-uninstallation checks
echo -e "${YELLOW}Running pre-uninstallation checks...${NC}"
ansible -i hosts.yaml pies -m ping

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Warning: Cannot reach all hosts. Proceeding with available hosts only.${NC}"
fi

# Run the uninstallation playbook
echo -e "${RED}Running Ceph uninstallation playbook...${NC}"
ansible-playbook -i hosts.yaml uninstall.yaml -K $EXTRA_VARS

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Ceph uninstallation completed successfully!${NC}"
    echo -e "${YELLOW}All Ceph components have been removed from the cluster.${NC}"
else
    echo -e "${RED}Uninstallation encountered some errors. Check the output above.${NC}"
    echo -e "${YELLOW}You may need to manually clean up remaining components.${NC}"
    exit 1
fi