# ansible-wks-setup

Ansible playbook to set up a development environment on a fresh Linux or WSL instance.

## Roles

| Role | Description |
|------|-------------|
| `dev-deps` | System-wide installs requiring root: common utility packages and Docker |
| `dev-tools` | User-space developer tools: kubectl, kind, k9s, helm, AWS CLI, OCI CLI, oci Terraform, Go (+ gopls, golangci-lint), Python (pyenv, poetry, uv), exa, ccat |
| `dotfiles` | User configuration: bash settings and tmux config |


1. Clone this repo and install `ansible-core`:

   ```bash
   git clone <repo-url> ansible-wks-setup
   cd ansible-wks-setup
   make bootstrap
   ```

2. Copy `.env.example` to `.env` and fill in your details:

   ```bash
   cp .env.example .env
   ```

   `.env` is gitignored. At minimum set your git identity:

   ```
   EXTRA_VARS=-e "git_name=Your Name" -e "git_email=you@example.com"
   ```

3. Run the playbook:

   ```bash
   make run        # full playbook (prompts for sudo)
   ```

## Make targets

| Target | Description |
|--------|-------------|
| `make run` | Full playbook (prompts for sudo via `-K`) |
| `make dev-deps` | System packages + Docker only (requires sudo) |
| `make dev-tools` | User-space tools only |
| `make dotfiles` | Dotfiles only |
| `make check` | Dry-run the full playbook |
| `make syntax` | Validate playbook syntax |
| `make bootstrap` | Install `ansible-core` on a fresh machine |

Tags can also be passed at runtime to override `run`:

```bash
make run TAGS=dev-tools,dotfiles
```

> **Note:** `dev-tools` depends on packages from `dev-deps`. Run `make dev-deps` first on a fresh machine, then `make dev-tools` and `make dotfiles`.
