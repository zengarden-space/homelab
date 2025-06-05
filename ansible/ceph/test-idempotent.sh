#!/bin/bash

# Test idempotency of the Ceph installation playbook
echo "Testing Ceph installation playbook idempotency..."
echo "This will run the playbook to verify it doesn't make unnecessary changes."
echo

# Run the playbook with sudo password prompt
ansible-playbook -i hosts.yaml install.yaml --ask-become-pass

echo
echo "Idempotency test completed."
echo "If no tasks showed 'changed' status except for apt update, the playbook is idempotent."
