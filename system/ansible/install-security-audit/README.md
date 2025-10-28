# Install Security Audit Script

Ansible playbook to deploy the security audit script to all blade nodes.

## What it does

Deploys `security-audit.sh` to `~/bin/` on all blade nodes (blade001-blade005) for both the ansible and oleksiyp users.

## Prerequisites

- Ansible installed on control machine
- SSH access to all blade nodes as `ansible` user
- Passwordless sudo configured for `ansible` user

## Installation

```bash
./install.sh
```

This will:
1. Create `~/bin/` directory if it doesn't exist
2. Copy `security-audit.sh` to `~/bin/security-audit.sh`
3. Set executable permissions (0755)
4. Verify installation by running `--help`

## Manual Installation

If you need more control:

```bash
ansible-playbook -v -i hosts.yaml install.yaml
```

## Verification

After installation, verify on any node:

```bash
ssh blade001 '~/bin/security-audit.sh --help'
```

## Usage After Installation

**Run on a single node:**
```bash
ssh blade001 '~/bin/security-audit.sh'
```

**Run on all nodes:**
```bash
for blade in blade001 blade002 blade003 blade004 blade005; do
  echo "=== $blade ==="
  ssh $blade '~/bin/security-audit.sh | tail -15'
done
```

**JSON output:**
```bash
ssh blade001 '~/bin/security-audit.sh --json'
```

## Script Capabilities

The security audit script performs 10 comprehensive checks:

1. **Authentication logs** - Failed logins, invalid users
2. **User accounts** - New users, UID 0 users, shell access
3. **SSH keys** - Authorized keys integrity
4. **Network connections** - Listening ports, external connections
5. **Running processes** - Suspicious patterns
6. **Scheduled tasks** - Crontabs
7. **File integrity** - System files, SUID/SGID files
8. **System logs** - Security keywords
9. **System resources** - Disk, memory, CPU usage
10. **Restrictive proxy** - Unauthorized access attempts

## Exit Codes

- `0` - System secure, no issues
- `1` - Warnings detected, review recommended
- `2` - Critical issues detected, immediate investigation required

## Files

```
install-security-audit/
├── README.md              # This file
├── hosts.yaml             # Ansible inventory (all blade nodes)
├── install.sh             # Installation script
├── install.yaml           # Ansible playbook
└── files/
    └── security-audit.sh  # The security audit script
```

## Updating the Script

To update the script on all nodes after making changes:

1. Edit `files/security-audit.sh`
2. Run `./install.sh` again

Ansible will detect changes and update the script on all nodes.

## Troubleshooting

**Permission denied:**
```bash
# Check ansible user can sudo without password
ssh blade001 'sudo whoami'
```

**Script not found after installation:**
```bash
# Check if ~/bin is in PATH
ssh blade001 'echo $PATH'

# Use full path if needed
ssh blade001 '/home/ansible/bin/security-audit.sh'
```

**Ansible connection issues:**
```bash
# Test connectivity
ansible all -i hosts.yaml -m ping
```

## See Also

- [Monitoring Documentation](../../../docs/content/operations/monitoring.mdx) - Security auditing section
- [Security Audit Script Source](files/security-audit.sh) - The script itself