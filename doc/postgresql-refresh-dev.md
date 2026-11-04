# PostgreSQL Production-to-Development Refresh

Script: `scripts/postgresql-refresh-dev.sh`

## Purpose

Refresh a development PostgreSQL database using a dump from an AWS RDS PostgreSQL source. The workflow connects to the source for reading and applies changes only to the development target.

## Requirements

- Linux control machine with Bash, Python 3, SSH client, and `mktemp`.
- Activate the repository's Python virtual environment with Ansible installed.
- SSH and sudo access to the development PostgreSQL host.
- `sshpass` on the control machine only when password-based SSH authentication is used.
- Network connectivity from the development host to the RDS endpoint.
- An RDS account with permission to connect to the source database and read the objects/data required by `pg_dump`.
- Required PostgreSQL extensions available on the development host before restore.

## Run

From the repository root:

```bash
source .venv/bin/activate
bash scripts/postgresql-refresh-dev.sh
```

The script interactively collects the RDS endpoint/database/user/password, development host and SSH user, target database/owner, application role, and network access settings.

## Saved configuration

The script remembers only validated, non-secret connection settings in:

`~/.config/ops-toolkit/postgresql-refresh-dev/config.json`

When `XDG_CONFIG_HOME` is set, the file is stored below that directory instead. The configuration directory is restricted to mode `0700` and the JSON file to mode `0600`. Passwords, SSH credentials, and other secrets are requested at runtime and are not saved.

To remove saved defaults:

```bash
bash scripts/postgresql-refresh-dev.sh --reset-config
```

Press Enter to accept a displayed default. At the application source CIDR prompt, enter `none` for local-only access. For remote access, multiple IPv4 CIDRs can be entered as a comma-separated list, for example:

```text
10.8.0.0/24,172.23.0.0/16
```

Each CIDR is validated and normalized. Use only trusted, narrow source networks.

## Workflow

1. Connects to the RDS source using PostgreSQL SSL (`sslmode=require` by default).
2. Installs the PostgreSQL 18 client as a bootstrap tool and detects the actual RDS server major version using `SHOW server_version_num`.
3. Supports RDS PostgreSQL major versions 15, 16, 17, and 18. Unsupported versions stop before the target database is modified.
4. Prepares the matching PostgreSQL server/client major version on the development host. Other installed PostgreSQL major versions are left in place; packages and clusters are not automatically uninstalled or deleted.
5. Checks source, target, and client major-version compatibility before dumping.
6. Creates a temporary custom-format dump on the development host and restores it to the development database.
7. Uses `--no-owner` and `--no-acl`. Restored objects are owned by the PostgreSQL restore account; the database itself is owned by the selected target database owner.
8. Creates or validates a separate application login role and grants runtime access to non-system schemas, existing tables, and sequences. The application role is not intended for schema migrations requiring `CREATE` privileges.
9. Keeps PostgreSQL local during restore. If remote application access is enabled, it then binds to the selected server interface IP and adds one database/user-specific `scram-sha-256` HBA rule per supplied CIDR.
10. Removes the temporary dump directory after the workflow, including on task failure.

The workflow does not modify the RDS source, production infrastructure, application endpoints, host firewall, or AWS security-group rules.

## Important pre-run checks

- Allow outbound connectivity from the development host to the RDS endpoint.
- Allow the development host's egress IP in the RDS security group on the database port.
- Ensure the target PostgreSQL port is available for the selected cluster.
- Ensure required extensions are installed on the development host.
- The target database owner role must already exist.
- The application username must differ from the database owner.
- The application password must be at least 16 characters. If the role already exists, its current password is preserved; the supplied password is used only when creating the role.
- Remote access is disabled by default. If enabled, configure firewall and security-group rules separately to allow only the supplied trusted CIDRs. Prefer a private network or VPN and configure PostgreSQL TLS when transport encryption is required; SCRAM authentication alone does not encrypt traffic.

## Destructive operation warning

The script refuses to overwrite an existing target database by default. To authorize replacement, type exactly `REPLACE` at the prompt. The dump is completed before an existing target database is dropped.

If restore fails after replacement begins, the development database may be left partially restored. The RDS source remains untouched. Review and mask personal or sensitive production data before allowing developer access.

## Direct Ansible execution

The underlying playbook is `ansible/playbooks/postgresql-refresh-dev.yml`. It expects the `postgresql_refresh_targets` inventory group and variables defined in `ansible/roles/postgresql_refresh_dev/defaults/main.yml`. Keep source credentials in Ansible Vault or a protected vars file; never commit them.
