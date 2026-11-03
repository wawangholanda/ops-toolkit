# Ops Toolkit

A growing collection of reusable DevOps scripts and infrastructure automation tools.

This project starts with GitLab Runner lifecycle management, providing scripts to simplify runner registration and unregistration. The long-term goal is to build a practical toolkit for Linux system administration, CI/CD operations, and infrastructure automation.

## Current Features

- **GitLab Runner Registration** — automate the runner registration workflow.
- **GitLab Runner Unregistration** — simplify the runner unregistration workflow.
- **Redis Installation** — install and configure Redis on Debian and Ubuntu hosts using Ansible.

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
