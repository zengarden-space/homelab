#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}WARNING: This will repartition NVMe drives on all master nodes!${NC}"
echo -e "${RED}This action is IRREVERSIBLE and will destroy all existing data on NVMe drives!${NC}"
echo -e "${YELLOW}Make sure you have backups of any important data.${NC}"
echo ""

read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Operation cancelled."
    exit 1
fi

echo -e "${GREEN}Starting NVMe repartitioning for K3s etcd...${NC}"

# Check if required files exist
if [ ! -f "hosts.yaml" ]; then
    echo -e "${RED}Error: hosts.yaml not found${NC}"
    exit 1
fi

if [ ! -f "install.yaml" ]; then
    echo -e "${RED}Error: install.yaml not found${NC}"
    exit 1
fi

# Load environment if exists
if [ -f ".env" ]; then
    source .env
fi

# Check if ansible-playbook is available
if ! command -v ansible-playbook &> /dev/null; then
    echo -e "${RED}Error: ansible-playbook is not installed${NC}"
    exit 1
fi

echo -e "${GREEN}Running NVMe repartitioning playbook...${NC}"
ansible-playbook -v -i hosts.yaml install.yaml

if [ $? -eq 0 ]; then
    echo -e "${GREEN}NVMe repartitioning completed successfully!${NC}"
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. Uninstall K3s if not already done"
    echo "  2. Install K3s with new configuration pointing to NVMe etcd partition"
    echo "  3. Deploy Ceph via Rook operator"
else
    echo -e "${RED}NVMe repartitioning failed!${NC}"
    exit 1
fi
