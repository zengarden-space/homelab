# Blade System Updates

This runbook automates the process of downloading and applying system updates on all blade servers.

## Features

- Updates all system packages on specified blade servers
- Displays a list of upgradable packages before installation
- Shows a summary of installed, upgraded, and removed packages
- Detects if a reboot is required and asks for confirmation
- Provides detailed logging of all operations

## Requirements

- Ansible installed on the control machine
- SSH access to all blade servers
- Sudo privileges on the blade servers

## Usage

1. Copy the `.env.template` file to `.env` and edit if needed:
   ```bash
   cp .env.template .env
   ```

2. Edit the `hosts.yaml` file to include the blades you want to update.

3. Run the update process:
   ```bash
   bash install.sh
   ```

4. Follow the prompts - you may be asked to:
   - Enter your sudo password for ansible
   - Confirm if you want to reboot servers (if needed)

## Configuration Options

You can customize the behavior by editing the `.env` file:

- `UPDATE_TIMEOUT`: Maximum time to wait for updates (seconds)
- `REBOOT_TIMEOUT`: Maximum time to wait for reboot (seconds)
- `SKIP_UPDATES_PACKAGES`: Packages to exclude from updates

## Customization

To skip updating certain packages, add them to the `SKIP_UPDATES_PACKAGES` variable in your `.env` file. For example:

```
SKIP_UPDATES_PACKAGES="kernel*,postgresql*"
```
