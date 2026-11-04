# GitLab Runner Registration

Script: `scripts/gitlab-runner-reg.sh`

## Purpose

Register and configure a GitLab Runner on a remote Linux host through the repository's Ansible playbook.

## Requirements

- Linux control machine with Bash, Python 3, SSH client, and `mktemp`.
- Activate the repository's Python virtual environment with Ansible installed.
- SSH access and sudo privileges on the target host.
- `sshpass` on the control machine only when password-based SSH authentication is used.
- A GitLab Runner authentication token created in GitLab before starting.

## Run

From the repository root:

```bash
source .venv/bin/activate
bash scripts/gitlab-runner-reg.sh
```

## Interactive configuration

The script asks for:

- Runner server IP address or hostname and SSH username.
- Executor: Docker (default) or Shell.
- Runner name and comma-separated tags.
- GitLab base HTTPS URL (defaults to `https://gitlab.com`).
- Runner authentication token.
- SSH private-key path, or SSH and sudo passwords when key authentication is unavailable.

Review the target and executor summary before confirming.

## What it does

1. Checks the Ansible virtual environment and required local commands.
2. Creates or updates `ansible/inventory/dev/hosts.yml` after asking before overwriting an existing file.
3. Uses SSH key authentication when available, otherwise password authentication with `sshpass`.
4. Writes sensitive Ansible variables to a temporary file with mode `0600`.
5. Runs an Ansible syntax check, then the GitLab Runner playbook.
6. Removes temporary secret and authentication files on exit.

## Security notes

- Treat the Runner authentication token as a secret. It is entered without terminal echo and is not written to the inventory.
- Do not commit credentials, tokens, or private keys.
- Use a dedicated SSH account with only the required sudo privileges.
- Review the target host and GitLab URL before confirming.
- The script may overwrite the local development inventory, but asks for confirmation first.
