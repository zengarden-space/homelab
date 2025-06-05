#!/bin/bash

echo "Adding NVMe storage to Ceph cluster..."
echo "This will add /dev/nvme0n1 from each host as an OSD"
echo

# Check if hosts.yaml exists
if [ ! -f "hosts.yaml" ]; then
    echo "Error: hosts.yaml not found in current directory"
    echo "Please run this script from the ceph ansible directory"
    exit 1
fi

# Run the storage addition playbook
echo "Running storage addition playbook..."
ansible-playbook -i hosts.yaml add-storage.yaml --ask-become-pass

echo
echo "Storage addition completed."
echo "Check the output above for any errors or warnings."
echo
echo "To verify the storage was added correctly:"
echo "  cephadm shell -- ceph osd status"
echo "  cephadm shell -- ceph status"
