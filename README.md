# ansible-wks-setup

Ansible playbook to set up a development environment on a fresh Linux or WSL instance.

## Roles

| Role | Description |
|------|-------------|
| `dev-deps` | System-wide installs requiring root: common utility packages and Docker |
| `dev-tools` | User-space developer tools: kubectl, kind, k9s, helm, AWS CLI, OCI CLI, oci Terraform, Go (+ gopls, golangci-lint), Python (pyenv, poetry, uv), exa, ccat |
| `dotfiles` | User configuration: bash settings and tmux config |


1. Clone this repo and run the bootstrap script to install `ansible-core`:

   ```bash
   git clone <repo-url> ansible-wks-setup
   cd ansible-wks-setup
   sudo bash bootstrap.sh
   ```

2. Run the playbook:

   ```bash
   ansible-playbook -i inventory/hosts.ini playbook.yml -K  -e "git_name=< your name>" -e "git_email=<your email adress>"
   ```

   `-K` prompts for the sudo password, which is required for tasks that need elevated privileges (package installation, Docker setup). The inventory is currently set up for localhost, but can be modified to target remote hosts as needed.

## Running by tag

To run only a specific role, use `--tags`:

```bash
ansible-playbook -i inventory/hosts.ini playbook.yml -K --tags dev-tools
ansible-playbook -i inventory/hosts.ini playbook.yml --tags dev-deps
ansible-playbook -i inventory/hosts.ini playbook.yml --tags dotfiles -e "git_name=< your name>" -e "git_email=<your email adress>"
```

Please note that the `dev-tools` role requires the `dev-deps` role to be run first, as it depends on some of the packages installed by `dev-deps`. `dotfiles` sets up config but bashrc entries expect the tools to be present, so it should also be run after `dev-deps` and `dev-tools`.
