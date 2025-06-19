#!/bin/bash
# filepath: /home/oleksiyp/dev/basic-infra/ansible/updates/install.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting system updates for all blades...${NC}"

# Check if required files exist
if [ ! -f "hosts.yaml" ]; then
    echo -e "${RED}Error: hosts.yaml not found${NC}"
    exit 1
fi

if [ ! -f "install.yaml" ]; then
    echo -e "${RED}Error: install.yaml not found${NC}"
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

# Run the installation playbook
echo -e "${GREEN}Running system updates playbook...${NC}"
ansible-playbook -v -i hosts.yaml install.yaml

if [ $? -eq 0 ]; then
    echo -e "${GREEN}System updates completed successfully!${NC}"
    echo -e "${YELLOW}Check the output above to see if any servers require a reboot.${NC}"
else
    echo -e "${RED}Updates failed. Check the output above for errors.${NC}"
    exit 1
fi
