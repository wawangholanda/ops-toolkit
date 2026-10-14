# Ops Toolkit

A growing collection of reusable DevOps scripts and infrastructure automation tools.

This project starts with GitLab Runner lifecycle management, providing scripts to simplify runner registration and unregistration. The long-term goal is to build a practical toolkit for Linux system administration, CI/CD operations, and infrastructure automation.

## Current Features

- **GitLab Runner Registration** — automate the runner registration workflow.
- **GitLab Runner Unregistration** — simplify the runner unregistration workflow.

## Requirements

- Linux environment with Bash.
- GitLab Runner installed on the target system, where required by the scripts.
- Network access to the GitLab instance.
- Appropriate permissions and credentials for the requested operation.

See each script's usage instructions for its exact requirements.

## Getting Started

Clone the repository:

```bash
git clone git@github.com:wawangholanda/ops-toolkit.git
cd ops-toolkit
```

Review the scripts and their usage instructions before execution. Use the appropriate command-line options and configuration supported by each script.

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
