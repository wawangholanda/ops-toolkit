# Redis Installation

Script: `scripts/redis-install.sh`

## Purpose

Install and configure Redis on a remote Debian or Ubuntu host using Ansible.

## Requirements

- Linux control machine with Bash, Python 3, SSH client, and `mktemp`.
- Activate the repository's Python virtual environment with Ansible installed.
- SSH access and sudo privileges on the target host.
- `sshpass` on the control machine only when password-based SSH authentication is used.
- Network access from the target host to its configured APT repositories.

## Run

From the repository root:

```bash
source .venv/bin/activate
bash scripts/redis-install.sh
```

## Interactive configuration

The quick-start asks for:

- Target server IP/hostname and SSH username.
- Redis port (default `6379`).
- Bind address: localhost (default), private server IP, custom IPv4 address, or `0.0.0.0`.
- Optional Redis password.
- SSH private-key path or SSH password, plus sudo authentication.
- Confirmation before applying the configuration.

A selected specific IP must already be assigned to the target host. The role validates the address before configuring Redis.

## Defaults and behavior

- Redis listens on `127.0.0.1:6379` by default.
- Protected mode remains enabled.
- Redis is started immediately and enabled at boot.
- A Redis password is optional; provide one when the service requires authentication.
- No reboot is performed.
- The quick-start creates temporary inventory and variables files with restrictive permissions and removes them on exit.

## Direct Ansible execution

The playbook can also be run directly:

```bash
ansible-playbook -i ansible/inventory/dev/hosts.yml ansible/playbooks/redis.yml
```

The inventory must define hosts in the `redis_servers` group. For advanced configuration, review `ansible/roles/redis/defaults/main.yml` or use a protected Ansible vars file. Do not commit passwords.

## Security notes

- Keep Redis bound to localhost unless remote access is required.
- If using a private or custom address, restrict access with host/network firewalls.
- Binding to `0.0.0.0` exposes Redis on all interfaces; only use it with deliberate network controls and authentication.
- Never expose Redis directly to the public Internet.
