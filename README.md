# Ops Toolkit

A growing collection of reusable DevOps scripts and infrastructure automation tools.

This project starts with GitLab Runner lifecycle management, providing scripts to simplify runner registration and unregistration. The long-term goal is to build a practical toolkit for Linux system administration, CI/CD operations, and infrastructure automation.

## Current Features

- **GitLab Runner Registration** — automate the runner registration workflow.
- **GitLab Runner Unregistration** — simplify the runner unregistration workflow.
- **Redis Installation** — install and configure Redis on Debian and Ubuntu hosts using Ansible.
- **PostgreSQL Installation** — install and configure PostgreSQL on Debian and Ubuntu hosts using Ansible.

## Requirements

- Linux environment with Bash, Python 3, and SSH client.
- Ansible installed in a Python virtual environment (see `requirements.txt`).
- `sshpass` on the control machine only when using SSH password authentication.
- GitLab Runner installed on the target system, where required by the GitLab Runner management scripts.
- Network access to the relevant package repositories and GitLab instance.
- Appropriate SSH and sudo permissions on target hosts.

See each script's usage instructions for its exact requirements.

## Getting Started

Clone the repository:

```bash
git clone git@github.com:wawangholanda/ops-toolkit.git
cd ops-toolkit
```

Review the scripts and their usage instructions before execution. Use the appropriate command-line options and configuration supported by each script.

### Redis installation

The Redis role targets Debian and Ubuntu systems using APT. It does not pin a fixed list of OS release numbers; actual compatibility depends on the target's Python version, the installed Ansible version, and the availability of APT repositories.

Activate the project's Ansible virtual environment, then run:

```bash
source .venv/bin/activate
bash scripts/redis-install.sh
```

The quick-start prompts for the target host, SSH user, Redis port, optional Redis password, and SSH authentication details. It uses a temporary inventory and a mode-0600 temporary variables file; both are removed when the script exits.

Defaults:
- Redis listens on `127.0.0.1:6379` by default. The quick-start lets you choose localhost, a private server IP, a custom IPv4 address, or `0.0.0.0` (all interfaces).
- A selected specific IP must already be assigned to the target host; the Ansible role validates this before configuring Redis.
- Protected mode remains enabled.
- Redis starts now and is enabled at boot.
- A Redis password is optional; supply one when the service needs authentication.
- No reboot is performed.

For advanced configuration, edit the Redis role variables in `ansible/roles/redis/defaults/main.yml` or pass overrides through a protected Ansible vars file. Do not commit passwords.

The playbook can also be run directly:

```bash
ansible-playbook -i ansible/inventory/dev/hosts.yml ansible/playbooks/redis.yml
```

The inventory must define hosts in the `redis_servers` group.

### PostgreSQL installation

The PostgreSQL role installs a specifically selected major version from the official PostgreSQL Global Development Group (PGDG) APT repository. The quick-start currently offers PostgreSQL 15, 16, 17, and 18, with 18 as the default. Versioned packages are used (for example, `postgresql-18` and `postgresql-client-18`) rather than the moving `postgresql` meta-package.

PGDG repository setup follows the official PostgreSQL instructions and uses the repository signing key with APT's `Signed-By` option. Repository availability depends on the target Debian/Ubuntu release and CPU architecture; check the [official Debian](https://www.postgresql.org/download/linux/debian/) and [Ubuntu](https://www.postgresql.org/download/linux/ubuntu/) support lists before deployment.

Activate the project's Ansible virtual environment, then run:

```bash
source .venv/bin/activate
bash scripts/postgresql-install.sh
```

The quick-start prompts for the target host, SSH user, PostgreSQL major version, port, listen address, and SSH authentication details. It creates temporary inventory and mode-0600 variables files and removes them on exit.

Defaults:
- PostgreSQL listens on `localhost:5432` (local connections only).
- You can select localhost, a private server IP, a custom IPv4 address, or `*` (all interfaces).
- A selected specific IPv4 address must already be assigned to the target host.
- The role configures the selected major version's `main` cluster, enables and starts PostgreSQL, and verifies readiness plus the responding server major version.
- No database user or password is created, no `pg_hba.conf` rules are modified, and no reboot is performed.

**Important:** changing `listen_addresses` alone does not grant remote database access. Remote clients also need an intentional `pg_hba.conf` rule, appropriate authentication, and a firewall rule restricted to trusted source addresses. Do not expose PostgreSQL directly to the Internet.

For advanced configuration, edit `ansible/roles/postgresql/defaults/main.yml` or pass overrides through a protected Ansible vars file. For example, set `postgresql_version: "17"` to select PostgreSQL 17.

The playbook can also be run directly:

```bash
ansible-playbook -i /path/to/inventory.yml ansible/playbooks/postgresql.yml
```

The inventory must define hosts in the `postgresql_servers` group.

### PostgreSQL production-to-development refresh

To refresh a development database from an AWS RDS PostgreSQL database, first install PostgreSQL on the development host with `scripts/postgresql-install.sh`. Then run:

```bash
source .venv/bin/activate
bash scripts/postgresql-refresh-dev.sh
```

The refresh workflow:
- Connects from the development host to the RDS source using PostgreSQL SSL (`sslmode=require` by default).
- Checks source, target, and client major-version compatibility before dumping.
- Creates a temporary custom-format dump on the development host, then restores it into the development database.
- Uses `--no-owner` and `--no-acl`; restored objects are owned by the selected target database owner.
- Removes the temporary dump directory after the workflow, including when a task fails.
- Never changes the RDS source, application endpoints, or production infrastructure.

Before running:
- Allow the development host's outbound connection to the RDS endpoint and allow its private/public egress IP in the RDS security group on the database port.
- Ensure the RDS user can connect to the selected database and read all objects/data required by `pg_dump`.
- Ensure the target PostgreSQL client major version is at least the source major version, and the target server major version is not older than the source. This workflow does not support major-version downgrades.
- Install required PostgreSQL extensions on the development host before restoring. Extension availability and RDS-specific features should be checked separately.
- The target database owner role must already exist on the development server.
- The temporary dump contains production data. The temporary directory is restricted to the PostgreSQL OS account, but use encrypted storage and protect the development host appropriately.

The script refuses to overwrite an existing target database by default. To replace it, explicitly type `REPLACE` at the prompt. The dump is completed before an existing target database is dropped. If restore fails after replacement begins, the development database may be left partially restored; the RDS source remains untouched. Review and mask personal or sensitive production data before allowing developer access.

The underlying playbook can also be run directly with an inventory group named `postgresql_refresh_targets` and the variables defined in `ansible/roles/postgresql_refresh_dev/defaults/main.yml`. Keep source credentials in Ansible Vault or a protected vars file; never commit them.

## Security

- Never commit runner authentication tokens, registration tokens, private keys, or other secrets.
- Avoid placing credentials directly in shell scripts or command history.
- Use least-privilege access wherever possible.
- Verify the target GitLab instance and runner before registering or unregistering a runner.

## Roadmap

- [ ] Document registration and unregistration workflows with tested examples.
- [ ] Add input validation and clearer error handling.
- [ ] Add shell linting and automated tests.
- [ ] Add runner status and health-check utilities.
- [ ] Expand the collection with reusable DevOps automation.

## Project Philosophy

Tools should be practical, reusable, documented, and safe to run repeatedly where applicable.

## Support the Project

If this project helps you learn Platform Engineering, build your own
infrastructure laboratory, or explore Kubernetes automation, you can
support its continued development.

### 🇮🇩 Indonesia

Support via QRIS:

![QRIS support](assets/qris.png)

Scan the QRIS code to support the project.

### 🌎 International

International supporters can use Ko-fi:

[☕ Support via Ko-fi](https://ko-fi.com/wawangholanda)

Thank you for supporting open-source learning and continued development of the project.

## License

See the repository's `LICENSE` file, if present, for licensing terms.
