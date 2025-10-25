# Restrictive HTTP Proxy

A Node.js-based HTTP proxy that restricts access to specific paths based on HTTP methods. Designed to limit the power of credentials (e.g., MikroTik router) to only allow specific API operations like external DNS requests.

## Features

- **Path-based restrictions**: Define allowed paths per HTTP method using glob patterns
- **Two modes**:
  - `WATCH`: Allow all requests but log which ones match restrictions
  - `RESTRICT`: Block requests that don't match defined restrictions
- **Clean logging**: Simple one-line logs showing allowed/restricted/potentially-restricted requests
- **Basic authentication**: Automatically adds credentials to proxied requests
- **Systemd service**: Runs as a Linux service with automatic restart
- **Secure credential handling**: Credentials are templated into config file with 0400 permissions (read-only by proxy user)

## Configuration

The proxy configuration is templated by Ansible from `templates/restrictive-proxy.conf.j2` and deployed to `/etc/restrictive-proxy.conf` with very restrictive permissions (0400):

```yaml
proxy:
  mikrotik-proxy.homelab.int.zengarden.space:
    to:
      url: http://192.168.77.1
      username: admin
      password: {{ mikrotik_password }}
    mode: WATCH  # or RESTRICT
    restrictions:
      GET:
        - /rest/ip/dns/static/**
        - /rest/system/resource
      POST:
        - /rest/ip/dns/static
      PUT:
        - /rest/ip/dns/static/*
      PATCH:
        - /rest/ip/dns/static/*
      DELETE:
        - /rest/ip/dns/static/*
```

### Configuration Options

- **mode**: 
  - `WATCH`: Log matches but allow all requests (for testing)
  - `RESTRICT`: Block requests that don't match restrictions
- **restrictions**: Define allowed paths per HTTP method using glob patterns
  - `*` matches a single path segment
  - `**` matches multiple path segments
  - No pattern = method not allowed

## Installation

1. Copy `.env.template` to `.env` and fill in credentials:
   ```bash
   cp .env.template .env
   # Edit .env with your passwords
   ```

2. Edit `hosts.yaml` to specify target nodes (default: blade001, blade002)

3. Optionally edit `templates/restrictive-proxy.conf.j2` to customize the proxy rules

4. Run the installation script:
   ```bash
   ./install.sh
   ```

The script will:
- Source the `.env` file locally
- Pass credentials as Ansible variables (never stored on server)
- Template the config file with embedded credentials
- Set config file permissions to 0400 (read-only by proxy user)

## Security

- **No .env on server**: Credentials are passed via Ansible variables and templated directly into config
- **Restrictive file permissions**: Config file has 0400 permissions (read-only for owner only)
- **Dedicated user**: Runs as `restrictive-proxy` system user
- **Systemd hardening**: NoNewPrivileges, ProtectSystem, ProtectHome, PrivateTmp
- **No password exposure**: Passwords never logged or exposed in process list

## Usage

### Check service status
```bash
ansible proxy_nodes -i hosts.yaml -b -m shell -a 'systemctl status restrictive-proxy'
```

### View logs
```bash
ansible proxy_nodes -i hosts.yaml -b -m shell -a 'journalctl -u restrictive-proxy -n 50 --no-pager'
```

### Restart service
```bash
ansible proxy_nodes -i hosts.yaml -b -m shell -a 'systemctl restart restrictive-proxy'
```

## Log Output

The proxy produces clean, concise logs:

```
RESTRICTED GET /admin/users
ALLOWED DELETE /rest/ip/dns/static/12345
POTENTIALLY-RESTRICTED POST /rest/system/reboot
```

- **RESTRICTED**: Request was blocked (RESTRICT mode only)
- **ALLOWED**: Request matched a restriction rule and was allowed
- **POTENTIALLY-RESTRICTED**: Request didn't match any rule (allowed in WATCH, depends on mode in RESTRICT)

## Uninstallation

```bash
./uninstall.sh
```

## Use Case: MikroTik External DNS

This proxy is designed to limit MikroTik credentials to only perform DNS operations via the REST API:

1. Configure external-dns to use the proxy URL instead of direct MikroTik access
2. Set mode to `RESTRICT` after testing with `WATCH`
3. Only DNS-related API paths are allowed
4. Even if credentials are compromised, attacker cannot perform other operations

## Port Configuration

The proxy listens on port 555 (configured in `hosts.yaml`). Accessible at:
```
http://blade001:555
http://blade002:555
```
