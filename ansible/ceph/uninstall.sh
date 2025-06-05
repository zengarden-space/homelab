#!/bin/bash
# filepath: /home/oleksiyp/dev/basic-infra/ansible/ceph/uninstall.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}WARNING: This will completely remove Ceph from all hosts!${NC}"
echo -e "${RED}This action is IRREVERSIBLE and will destroy the cluster!${NC}"
echo -e "${YELLOW}Storage data will NOT be automatically cleaned - use ceph-volumes runbook for that.${NC}"
echo ""
read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${GREEN}Operation cancelled.${NC}"
    exit 0
fi

echo -e "${GREEN}Starting Ceph cluster uninstallation...${NC}"

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

# Run the uninstallation playbook
echo -e "${GREEN}Running Ceph uninstallation playbook...${NC}"
ansible-playbook -v -i hosts.yaml uninstall.yaml -K

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Ceph uninstallation completed successfully!${NC}"
    echo -e "${YELLOW}Note: Storage devices may still contain Ceph data.${NC}"
    echo -e "${YELLOW}Use ceph-volumes runbook to clean storage devices if needed.${NC}"
else
    echo -e "${RED}Uninstallation failed. Check the output above for errors.${NC}"
    exit 1
fi