# SSH Setup Runbook

This runbook sets up seamless SSH access between blade001, blade002, blade003, blade004, and blade005 using Ansible.

## What it does

1. **Generates SSH key pairs** on each host (if they don't already exist)
2. **Distributes public keys** to all other hosts' `authorized_keys` files
3. **Verifies connectivity** by testing SSH connections between all hosts

## Prerequisites

- Ansible must be installed on the machine running this playbook
- You must have SSH access (with password) to all target hosts
- The user account (`oleksiyp`) must exist on all hosts
- Python must be available on all target hosts

## Usage

1. **Run the setup:**
   ```bash
   cd /home/oleksiyp/dev/zengarden/basic-infra/ansible/ssh-setup
   ./install.sh
   ```

   You may be prompted for passwords during the first run.

2. **Test connectivity manually:**
   ```bash
   ssh blade002 hostname
   ssh blade003 hostname
   ssh blade004 hostname
   ssh blade005 hostname
   ```

## Files

- `hosts.yaml` - Ansible inventory with all blade hosts
- `install.yaml` - Ansible playbook for SSH setup
- `install.sh` - Convenience script to run the playbook
- `README.md` - This documentation

## What happens after setup

- Each host will have an SSH key pair in `~/.ssh/`
- Each host's public key will be in `authorized_keys` on all other hosts
- SSH connections between any blade hosts will work without passwords
- Scripts like `recover.sh` will work seamlessly

## Troubleshooting

- If a host is unreachable, check network connectivity and SSH service
- If authentication fails, verify the user exists and has SSH access
- Run with `-vvv` for verbose output: `./install.sh -vvv`
