# GitLab Runner Management

Script: `scripts/gitlab-runner-unreg.sh`

## Purpose

List registered runners on a remote GitLab Runner host or unregister one selected runner.

## Requirements

- Linux control machine with Bash, Python 3, SSH client, and `mktemp`.
- Activate the repository's Python virtual environment with Ansible installed.
- SSH access and sudo privileges on the target host.
- `sshpass` on the control machine only when password-based SSH authentication is used.

## Run

From the repository root:

```bash
source .venv/bin/activate
bash scripts/gitlab-runner-unreg.sh
```

## Interactive workflow

1. Choose **List runners** or **Unregister runner**.
2. Enter the Runner host and SSH username.
3. Authenticate using the default `~/.ssh/id_rsa` key when it works, otherwise use SSH password authentication.
4. The script runs the Ansible playbook and displays the runner list.
5. For unregister, enter the exact runner name and type `UNREGISTER` to confirm.

Choosing **List runners** is read-only. Leaving the runner name empty or declining the confirmation cancels the unregister operation.

## What it does

- Creates a private temporary inventory instead of overwriting the repository inventory.
- Stores SSH/sudo credentials in a temporary file with mode `0600`.
- Runs an Ansible syntax check before the operation.
- Lists runners before asking which one to unregister.
- Checks Ansible output for common cases where no target host matched.
- Removes temporary inventory, credentials, and captured output on exit.

## Security and impact

- Unregistering removes the selected runner registration from the target host; verify the host and runner name carefully.
- The script requires sudo access on the remote host.
- Never put passwords or tokens in command-line arguments or commit them to Git.
