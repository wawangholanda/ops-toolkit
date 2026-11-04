# PostgreSQL Installation

Script: `scripts/postgresql-install.sh`

## Purpose

Install and configure a selected PostgreSQL major version on a remote Debian or Ubuntu host using Ansible.

## Requirements

- Linux control machine with Bash, Python 3, SSH client, and `mktemp`.
- Activate the repository's Python virtual environment with Ansible installed.
- SSH access and sudo privileges on the target host.
- `sshpass` on the control machine only when password-based SSH authentication is used.
- Network access from the target host to the official PGDG APT repository and package mirrors.

## Run

From the repository root:

```bash
source .venv/bin/activate
bash scripts/postgresql-install.sh
```

## Interactive configuration

The quick-start asks for the target host, SSH username, PostgreSQL major version, port, listen address, and SSH authentication details.

The currently offered major versions are PostgreSQL 15, 16, 17, and 18; version 18 is the default. The role uses versioned packages such as `postgresql-18` and `postgresql-client-18`, rather than the moving `postgresql` meta-package.

The listen address can be localhost, a private server IP, a custom IPv4 address, or `*` (all interfaces). A specific IPv4 address must already be assigned to the target host.

## Defaults and behavior

- PostgreSQL listens on `localhost:5432` by default.
- Configures the selected major version's `main` cluster.
- Enables and starts PostgreSQL.
- Verifies service readiness and the responding server major version.
- Creates no database user or password.
- Does not modify `pg_hba.conf`.
- Does not reboot the target host.
- Temporary inventory and mode-`0600` variables files are removed on exit.

## Direct Ansible execution

```bash
ansible-playbook -i /path/to/inventory.yml ansible/playbooks/postgresql.yml
```

The inventory must define hosts in the `postgresql_servers` group. For advanced configuration, review `ansible/roles/postgresql/defaults/main.yml` or pass overrides through a protected vars file. For example, set `postgresql_version: "17"` to select PostgreSQL 17.

## Remote access warning

Changing `listen_addresses` does not grant remote database access. Remote clients also need:

- An intentional and narrowly scoped `pg_hba.conf` rule.
- Appropriate authentication.
- A host firewall and/or cloud security-group rule limited to trusted source addresses.

Do not expose PostgreSQL directly to the Internet. For a database that is already installed, use the separate [PostgreSQL application access playbook guide](postgresql-app-access.md) rather than reinstalling PostgreSQL.
