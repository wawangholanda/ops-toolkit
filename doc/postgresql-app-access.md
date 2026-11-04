# PostgreSQL Application Access

Playbook: `ansible/playbooks/postgresql-app-access.yml`

## Purpose

Add or update a restricted application network allowlist for an existing PostgreSQL database after it has already been installed or refreshed.

Use this playbook when only `pg_hba.conf` access needs to change. It does not dump, drop, restore, or otherwise modify database contents.

## Requirements

- Ansible installed on the control machine.
- SSH and sudo access to the existing PostgreSQL host.
- Inventory group named `postgresql_app_access_targets`.
- The selected PostgreSQL major version's `main` cluster already exists.
- A trusted private IPv4 client CIDR.

## Example

```bash
ansible-playbook -i /path/to/inventory.yml \
  ansible/playbooks/postgresql-app-access.yml \
  -e "postgresql_access_version=18" \
  -e "postgresql_access_port=5432" \
  -e "postgresql_access_database=appdb" \
  -e "postgresql_access_username=appuser" \
  -e "postgresql_access_client_cidr=172.23.0.0/16"
```

## Variables

| Variable | Description |
| --- | --- |
| `postgresql_access_version` | PostgreSQL major version; defaults to `18` (supported: 15–18). |
| `postgresql_access_port` | PostgreSQL port; defaults to `5432`. |
| `postgresql_access_database` | Database name to allow. |
| `postgresql_access_username` | PostgreSQL role to allow. |
| `postgresql_access_client_cidr` | One trusted private IPv4 network. |

## What it does

- Validates the requested version, port, database/role names, and private IPv4 CIDR.
- Checks that the selected PostgreSQL cluster and HBA file exist before editing.
- Adds or updates a database/user-specific `scram-sha-256` host rule marked `managed by ops-toolkit`.
- Reloads PostgreSQL only when the HBA rule changes.
- Checks that PostgreSQL parses a matching valid HBA rule.

## Limitations and security

- This playbook currently accepts one CIDR per invocation.
- Its managed rule is scoped to the supplied database, role, and CIDR. If you need multiple CIDRs, invoke it carefully and inspect the resulting `pg_hba.conf`; the current line-management pattern may update the existing managed rule for the same database and role rather than preserve multiple entries.
- It does not change host firewall or cloud security-group rules. Permit the PostgreSQL port only from the trusted application network.
- Use the actual Docker network subnet, not an assumed container IP. Avoid broad CIDRs and do not expose PostgreSQL directly to the Internet.

For a complete production-to-development database refresh, see [PostgreSQL refresh](postgresql-refresh-dev.md).
