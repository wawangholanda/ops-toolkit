# Ops Toolkit

A collection of reusable **Bash tools and Ansible automation for DevOps operations**.

This repository brings common infrastructure and operational tasks into repeatable command-line workflows. The tools currently cover GitLab Runner management, Redis and PostgreSQL installation, and PostgreSQL development database operations.

The project is intended as a practical, evolving toolkit for Linux administration, CI/CD operations, and infrastructure automation.

## Available tools

| Tool | Purpose | Documentation |
| --- | --- | --- |
| `gitlab-runner-reg.sh` | Register and configure a GitLab Runner on a remote host. | [gitlab-runner-reg.md](docs/gitlab-runner-reg.md) |
| `gitlab-runner-unreg.sh` | List runners or unregister a selected runner. | [gitlab-runner-unreg.md](docs/gitlab-runner-unreg.md) |
| `redis-install.sh` | Install and configure Redis on Debian/Ubuntu. | [redis-install.md](docs/redis-install.md) |
| `postgresql-install.sh` | Install a selected PostgreSQL major version. | [postgresql-install.md](docs/postgresql-install.md) |
| `postgresql-refresh-dev.sh` | Refresh a development database from AWS RDS PostgreSQL. | [postgresql-refresh-dev.md](docs/postgresql-refresh-dev.md) |

Additional Ansible workflow:

- [PostgreSQL application access](docs/postgresql-app-access.md) — configure restricted network access for an existing database without refreshing its data.

## Getting started

Clone the repository:

```bash
git clone https://github.com/wawangholanda/ops-toolkit.git
cd ops-toolkit
```

Most quick-start scripts use the repository's Ansible virtual environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Then run the required script from the repository root, for example:

```bash
bash scripts/redis-install.sh
```

Each tool has its own prerequisites, prompts, configuration options, and operational impact. **Read its documentation in the `docs/` directory before running it**, especially for workflows that modify infrastructure or database contents.

## Repository layout

```text
ops-toolkit/
├── ansible/       # Ansible playbooks, roles, and inventory examples
├── docs/          # Per-tool usage and operational documentation
├── scripts/       # Bash quick-start and operational scripts
├── assets/        # Project assets
├── requirements.txt
└── README.md
```

## Operational principles

- Review the target host and requested operation before confirming execution.
- Prefer least-privilege SSH and sudo access.
- Keep passwords, tokens, private keys, and production data out of Git.
- Use narrow network allowlists; do not expose infrastructure services directly to the Internet.
- Understand destructive actions and their recovery implications before proceeding.

## Project philosophy

Tools should be practical, reusable, clearly documented, and safe to run repeatedly where applicable. Each tool's detailed usage guide and limitations are maintained separately in [`docs/`](docs/).

## Support the project

If this toolkit is useful for your DevOps learning or infrastructure work, you can support its continued development.

- **Indonesia:** scan the QRIS code in [`assets/qris.png`](assets/qris.png).
- **International:** [Support via Ko-fi](https://ko-fi.com/wawangholanda).

## License

See the repository's `LICENSE` file, if present, for licensing terms.
