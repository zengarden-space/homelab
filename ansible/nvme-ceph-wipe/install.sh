#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}WARNING: This will zap NVMe ceph partitions on all nodes!${NC}"
echo -e "${RED}This action is IRREVERSIBLE and will destroy all existing data on NVMe ceph partition!${NC}"
echo -e "${YELLOW}Make sure you have backups of any important data.${NC}"
echo ""

read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Operation cancelled."
    exit 1
fi

echo -e "${GREEN}Starting ceph volume zapping...${NC}"

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

echo -e "${GREEN}Running ceph volume zapping playbook...${NC}"
ansible-playbook -v -i hosts.yaml install.yaml

if [ $? -eq 0 ]; then
    echo -e "${GREEN}ceph volume zapping completed successfully!${NC}"
else
    echo -e "${RED}ceph volume zapping failed!${NC}"
    exit 1
fi
