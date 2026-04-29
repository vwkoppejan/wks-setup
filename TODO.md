# TODO — Code Quality Review & Devcontainer Extension Plan

Review of the `wks-setup` Ansible repository. Scope: `bootstrap.sh`, `Makefile`, `playbook.yml`, `inventory/`, `roles/{dev-deps,dev-tools,dotfiles}`.

_Last verified against the working tree: 2026-04-27._

---

## 1. Overall Impression

The repo is well-structured for a personal workstation bootstrapper:

- Clear three-role split (`dev-deps` for root packages, `dev-tools` for user-space binaries, `dotfiles` for config).
- Reusable artifact pattern via [`_download_artifact.yml`](roles/dev-tools/tasks/_download_artifact.yml) + [`_symlink_binaries.yml`](roles/dev-tools/tasks/_symlink_binaries.yml) keeps per-tool task files tiny and uniform.
- Version pinning is centralized in [`roles/dev-tools/defaults/main.yml`](roles/dev-tools/defaults/main.yml).
- Idempotency via `.artifact-<version>.installed` markers is a nice touch.
- Tag-based selection (`make dev-deps`, `make dev-tools`, `make dotfiles`) is clean.

The skeleton is sound. The issues below are mostly hygiene, portability, and security.

---

## 2. Code Quality — Issues & Recommended Fixes

### 2.1 High priority

- [ ] **Empty file:** [`roles/dev-tools/tasks/bash.yml`](roles/dev-tools/tasks/bash.yml) is empty. Either implement it or delete it — dead files invite confusion.
- [ ] **`x86_64` hard-coded in several roles.** [`aws-cli.yml`](roles/dev-tools/tasks/aws-cli.yml#L8) and [`python-tools.yml`](roles/dev-tools/tasks/python-tools.yml) use `linux-x86_64`/`x86_64-unknown-linux-gnu`. The Docker role already derives `docker_apt_arch` from `ansible_architecture` — apply the same pattern to all artifact URLs so arm64 (Apple Silicon, Graviton, Raspberry Pi, arm WSL) works.
- [ ] **`golang.yml` "Install gopls" / "Install golangci-lint" tasks are not idempotent** and have no `creates:` guard — they run on every play. Add `creates:` args or `changed_when` guards. Also: `golangci-lint`'s `install.sh | sh` pattern pipes a remote script into a shell — pin to a tagged version, not `master`.
- [ ] **`tmux.yml` "Install tmux plugins via tpm"** runs every time (no `creates:` / no idempotency). Wrap with a marker file or `changed_when: false`.
- [ ] **`_symlink_binaries.yml` uses `changed_when: false`** on the symlink task. That hides drift from `--check` and reports clean even when the link target changed. Remove it; the `file` module already reports `changed` correctly.
- [ ] **Missing `ansible.builtin.` FQCN consistency.** Most modules in `dev-tools` use the short form (`file`, `get_url`, `command`, `stat`, `unarchive`), while `dev-deps` mixes both. Pick one (FQCN preferred) and run `ansible-lint` to enforce.
- [ ] **No checksum verification on any download.** Every `get_url`/`unarchive` fetches over HTTPS but does not verify SHA256 — supply-chain risk. Add `checksum:` parameters (vars per tool, e.g. `kubectl_sha256`). At minimum, add for `kubectl`, `helm`, `terraform`, `golang`, `aws-cli`, `uv`.
- [ ] **`shell`/`command` tasks without quoting safety.** `python-tools.yml` runs `python3 {{ software_dir }}/poetry/install-poetry.py` — if `software_dir` ever contained a space it would break. Quote arguments, prefer `command:` over `shell:` where no shell features are needed.

### 2.1.a `pip.yml` follow-ups

The bootstrap venv approach in [pip.yml](roles/dev-tools/tasks/pip.yml) (creates `{{ bootstrap_venv_dir }}` from system `python3 -m venv` and installs `pip_packages` via `ansible.builtin.pip` with `virtualenv:`) resolved the original `--user` / system-`pip` / interpreter-pinning concerns. Remaining open items:

- [ ] **Decide on `ansible-core` duality.** [bootstrap.sh](bootstrap.sh) installs system `ansible-core`; [pip.yml](roles/dev-tools/tasks/pip.yml) also installs it into the venv. Pick one as the steady-state, document the other as bootstrap-only (or drop it).
- [ ] **Document play ordering.** `python3 -m venv` requires `python3-venv` (already in `debian_utils_packages`), so `dev-deps` must run before `dev-tools` on a fresh Debian/Ubuntu host. Note in README or add a pre-flight assert.
- [ ] **Verify `~/.local/bin` PATH precedence** so the venv-symlinked `ansible*` shadow the apt-installed ones; otherwise users keep hitting the older system Ansible.
- [ ] **Hard-coded symlink list** in [pip.yml](roles/dev-tools/tasks/pip.yml). New console scripts added to `pip_packages` won't be exposed unless added to the loop. Consider `find` + `with_fileglob` over `bootstrap_venv_dir/bin/`, or a per-package `symlinks:` field.
- [ ] **`pip` upgrade uses `state: latest`** — ansible-lint will flag the `package-latest` rule. Pin or accept the lint exception.
- [ ] **CLI tool isolation.** `ansible-lint` and `molecule` share the venv with `ansible-core`. If dependency conflicts surface, split into per-tool venvs or move to `pipx`.
- [ ] **Add `tags: [pip]`** on the import in [main.yml](roles/dev-tools/tasks/main.yml#L13) so it can be re-run selectively (also applies to all other tool imports — see 2.2).
- [ ] **Add explicit `become: false`** on the import for clarity (currently inherited from the play default).

### 2.2 Medium priority

- [ ] **`dev-tools/main.yml` is 16 nearly-identical `import_tasks` blocks.** Replace with a loop over a list of tool names, or use `include_tasks` with a `with_items`, to remove boilerplate.
- [ ] **Inventory only declares `localhost`.** Acceptable for a personal box, but document that running against remote hosts requires editing `inventory/hosts.ini` and dropping `ansible_connection=local`.
- [ ] **No `requirements.yml` / collections pinning.** The playbook relies on `ansible.builtin` and `community.general`-adjacent behavior implicitly. Add a `requirements.yml` and `ansible.cfg` to pin collection versions and set `ANSIBLE_STDOUT_CALLBACK=yaml`.
- [ ] **No linting / CI.** Add `ansible-lint` and `yamllint` configs and a GitHub Actions workflow that runs `make syntax` + `ansible-lint` on PRs.
- [ ] **No molecule / smoke test.** Even a single Docker-based molecule scenario for `dev-tools` would catch most regressions.
- [ ] **`Makefile` `.env` handling.** `-include .env` + `export` exports every variable in `.env` to all subprocesses. Either narrow to `EXTRA_VARS`/`TAGS`/`VAULT_PASS_FILE` explicitly, or document the leakage.
- [ ] **`Makefile` lacks a default target.** Running `make` with no arg prints help would be friendlier than running the full play.
- [ ] **Per-tool tags missing.** Currently only role-level tags exist. Adding `tags: [kubectl]` etc. on each `import_tasks` lets users re-run a single tool.
- [ ] **`devtools_home` hard-codes `/home/{{ devtools_user }}`.** Fails for `root`, macOS (`/Users/...`), or LDAP homes. Use `{{ ansible_env.HOME }}` or `getent passwd` lookup.
- [ ] **README inconsistency.** README lists `aws-session-manager-plugin`, `oci-cli`, `oci Terraform`, `eza` (the `eza_version` var in defaults) but the tasks dir contains `exa.yml` (legacy name) and no oci tooling. Reconcile names and either add or remove the missing tools.
- [ ] **`Setup poetry bash completions`** appends to `~/.poetry_completions` only on first run; if Poetry version bumps, completions are stale. Replace with a proper templated completions file.

### 2.3 Low priority / nice-to-have

- [ ] Add `meta/main.yml` to each role with a description, supported platforms, min Ansible version.
- [ ] Add a `vars/` per-OS file pattern instead of `when: ansible_os_family == "Debian"` branches.
- [ ] Use `ansible.builtin.dnf` instead of the deprecated `yum:` module in [utils.yml](roles/dev-deps/tasks/utils.yml#L10).
- [ ] Add `--diff` to a `make diff` target for previewing dotfile changes.
- [ ] Consider replacing the marker-file idempotency with `creates:` on `get_url`/`unarchive` directly — Ansible already supports this and it's one fewer task per tool.
- [ ] `playbook.yml` — switch `roles:` to `tasks:` + `import_role` so per-tool tags propagate cleanly, or use `pre_tasks` for fact gathering speedup (`gather_subset: min`).

### 2.4 Security checklist (OWASP-style)

- [ ] No checksum verification on any binary download (see 2.1).
- [ ] Piping `curl | sh` for `golangci-lint` — pin and verify.
- [ ] `bash_functions` and `bashrc` snippets shipped via `copy:` / `blockinfile:` should be reviewed; appended bashrc blocks can override security-relevant `PATH` ordering. Verify `~/.local/bin` is prepended, not appended, only after sanity-checking what's there.
- [ ] `Add user to docker group` grants effective root via the Docker socket. Document this trade-off in README.

### 2.5 Idempotency / `changed_when` audit

Every `command:`/`shell:` task and every `file:`/`pip:` task with non-default `state:` was checked. Findings:

| File | Task | Mechanism | Verdict |
|---|---|---|---|
| [pip.yml](roles/dev-tools/tasks/pip.yml) | Create bootstrap venv | `creates:` | ✅ idempotent |
| [pip.yml](roles/dev-tools/tasks/pip.yml) | Upgrade pip/setuptools/wheel | `state: latest` | ⚠️ always reports `changed`; ansible-lint `package-latest`. Pin or accept |
| [pip.yml](roles/dev-tools/tasks/pip.yml) | Install `pip_packages` | pinned `==version` | ✅ idempotent |
| [pip.yml](roles/dev-tools/tasks/pip.yml) | Symlink venv binaries | `state: link, force: true` | ⚠️ `force: true` will report `changed` whenever the link is recreated; OK but noisy. Consider dropping `force` or guarding with a stat |
| [_download_artifact.yml](roles/dev-tools/tasks/_download_artifact.yml) | Version-marker `file: state=touch` | gated by `when: not artifact_version_marker.stat.exists` | ✅ marker logic correct, only touches first time |
| [_download_artifact.yml](roles/dev-tools/tasks/_download_artifact.yml) | `get_url` / `unarchive` | gated by marker | ✅ but redundant with built-in `creates:`/`dest:` checks (see 2.3) |
| [_symlink_binaries.yml](roles/dev-tools/tasks/_symlink_binaries.yml) | Stat verification | `failed_when: not ...stat.exists` | ✅ correct |
| [_symlink_binaries.yml](roles/dev-tools/tasks/_symlink_binaries.yml) | Symlink with `force: true` | **`changed_when: false`** | ❌ **lies to the user** — masks the case where `src:` changed (e.g. version bump) and the link target was actually updated. Remove `changed_when`; the `file` module reports `changed` correctly. Listed previously in 2.1; called out again here for completeness |
| [aws-cli.yml](roles/dev-tools/tasks/aws-cli.yml) | Run `aws/install` | `command:` gated by separate `aws_cli_install_marker` | ✅ idempotent, but reinvents `creates:` — a single `creates: {{ local_bin_dir }}/aws` arg on the `command` would replace both the `stat` and the marker `touch` |
| [aws-cli.yml](roles/dev-tools/tasks/aws-cli.yml) | Marker `file: state=touch` | gated by `when` | ✅ |
| [aws-session-manager-plugin.yml](roles/dev-tools/tasks/aws-session-manager-plugin.yml) | Extract `.deb` shell | `creates:` | ✅ |
| [aws-session-manager-plugin.yml](roles/dev-tools/tasks/aws-session-manager-plugin.yml) | Extract `.rpm` shell | `creates:` | ✅ |
| [golang.yml](roles/dev-tools/tasks/golang.yml) | `Install gopls` (`go install ...@{{ gopls_version }}`) | **none** | ❌ runs on every play, always reports `changed`. Add `creates: {{ devtools_home }}/go/bin/gopls` (works since `gopls_version: latest` makes versioned guards meaningless — use a stat-based `when:` instead, or pin `gopls_version`) |
| [golang.yml](roles/dev-tools/tasks/golang.yml) | `Install golangci-lint` (`curl ... \| sh`) | **none** | ❌ same as above. Add `creates: {{ devtools_home }}/go/bin/golangci-lint` and pin the installer to a tag, not `master` |
| [python-tools.yml](roles/dev-tools/tasks/python-tools.yml) | Compile pyenv ext (`src/configure && make`) | `creates: src/realpath.o` | ✅ correct enough, though `realpath.o` is a single object — full build success is implied |
| [python-tools.yml](roles/dev-tools/tasks/python-tools.yml) | Install poetry | `creates: poetry/bin/poetry` | ✅ |
| [python-tools.yml](roles/dev-tools/tasks/python-tools.yml) | Poetry bash completions (`>> ~/.poetry_completions`) | `creates: ~/.poetry_completions` | ⚠️ correct first-run, but never refreshes on Poetry version bump (already in 2.2). Also: `>>` will keep appending if the `creates:` guard is ever removed |
| [vim.yml (dev-tools)](roles/dev-tools/tasks/vim.yml) | Compile vim (`./configure && make && make install`) | `creates: {{ software_dir }}/vim/bin/vim` | ❌ **broken guard** — vim's `--prefix` is `{{ software_dir }}/vim/vim-{{ vim_version }}`, so the binary lands at `{{ software_dir }}/vim/vim-{{ vim_version }}/bin/vim`, not at `{{ software_dir }}/vim/bin/vim`. The `creates:` path never matches → vim is recompiled on every play. Either fix the path to include `/vim-{{ vim_version }}` or change the `--prefix` |
| [tmux.yml (dotfiles)](roles/dotfiles/tasks/tmux.yml) | `tpm/bin/install_plugins` | **none** | ❌ runs every play, always `changed`. Add a marker file or `changed_when: "'already installed' not in result.stdout"` |
| [vim.yml (dotfiles)](roles/dotfiles/tasks/vim.yml) | `vim ... +PlugInstall +qall \|\| true` | **none**, plus `\|\| true` swallows errors | ❌ always runs, always `changed`, and any real failure is hidden. At minimum add `changed_when: false` (or a marker) and drop `\|\| true` so genuine breakage surfaces |
| [main.yml (dotfiles)](roles/dotfiles/tasks/main.yml) | `Touch huslog file` (`state: touch`) | none | ⚠️ `touch` updates mtime → always `changed`. Use `state: file` or `creates:` semantics if the goal is just "file exists" |
| [_download_artifact.yml](roles/dev-tools/tasks/_download_artifact.yml) | `get_url` for binary | `mode:` only, marker-gated | ⚠️ when the marker doesn't exist, `get_url` re-downloads the file. Add `checksum:` (see 2.1) so re-downloads are also integrity-checked |

#### Summary of action items from the audit

- [ ] Fix [vim.yml `creates:` path](roles/dev-tools/tasks/vim.yml) (recompiles every run today).
- [ ] Add `creates:` (or pinned-version stat guard) to `Install gopls` and `Install golangci-lint` in [golang.yml](roles/dev-tools/tasks/golang.yml).
- [ ] Add idempotency guard to `Install tmux plugins via tpm` in [tmux.yml](roles/dotfiles/tasks/tmux.yml).
- [ ] Drop `\|\| true` and add a guard in `Install vim plugins via vim-plug` in [dotfiles/vim.yml](roles/dotfiles/tasks/vim.yml).
- [ ] Replace `state: touch` with `state: file` for `~/.huslogin` in [dotfiles/main.yml](roles/dotfiles/tasks/main.yml).
- [ ] Remove `changed_when: false` from the symlink task in [_symlink_binaries.yml](roles/dev-tools/tasks/_symlink_binaries.yml) (also tracked in 2.1).
- [ ] Replace marker-file pattern in [_download_artifact.yml](roles/dev-tools/tasks/_download_artifact.yml) and [aws-cli.yml](roles/dev-tools/tasks/aws-cli.yml) with `creates:` on the underlying module (also tracked in 2.3).
- [ ] Pin `gopls_version` (currently `"latest"`) so the install task can use a deterministic `creates:` path.
- [ ] Either pin `aws_session_manager_plugin_version` (currently `"latest"`) or accept that the marker file in `_download_artifact.yml` is meaningless when the version string never changes.

### 2.6 Resolved

- [x] ~~`bootstrap.sh` shebang missing `!`~~ — file now starts with `#!/bin/bash` (verified 2026-04-27). Hardening (`set -euo pipefail`, `sudo` guard) still open under 2.1.
- [x] ~~Orphan file `roles/dev-tools/tasks/ansible.yml` not imported.~~ Renamed to [pip.yml](roles/dev-tools/tasks/pip.yml) and wired into [main.yml](roles/dev-tools/tasks/main.yml#L13).
- [x] ~~`ansible_pip_packages` → `pip_packages`~~ done in [defaults/main.yml](roles/dev-tools/defaults/main.yml).
- [x] ~~`pip --user` install of `ansible-core` shadows the apt copy~~ — replaced by a dedicated venv at `{{ bootstrap_venv_dir }}`.
- [x] ~~`pip` interpreter not pinned~~ — `virtualenv:` parameter forces the venv's pip.
- [x] ~~Library deps (`jmespath`, `netaddr`, `passlib`) installed where Ansible cannot see them~~ — they live in the venv alongside `ansible-core`.
- [x] ~~`bootstrap.sh` lacks `set -euo pipefail`.~~
- [x] ~~`bootstrap.sh` is not run as root but invokes `apt`/`dnf` without `sudo`.~~
---

## 3. Extending to a Devcontainer

Goal: produce a `Dockerfile` + `.devcontainer/devcontainer.json` so that the same Ansible roles build a reproducible container image usable in VS Code Dev Containers / GitHub Codespaces.

### 3.1 Approach options

| Option | Pros | Cons |
|--------|------|------|
| **A. Run Ansible inside the build** (`RUN ansible-playbook ...`) | Single source of truth, zero duplication | Larger image, slower builds, needs `ansible-core` in image |
| **B. Translate roles into a Dockerfile** | Smaller image, faster, no Ansible dependency | Drift between two sources of truth |
| **C. Hybrid** — use Ansible for `dev-tools` + `dotfiles`, native `RUN apt-get` for `dev-deps` | Best layer caching, skips Docker-in-Docker awkwardness | Slightly more complex |

**Recommended: Option C.** A devcontainer should not install Docker inside itself (use Docker-outside-of-Docker via socket mount, or the official `docker-in-docker` feature). Skip the `dev-deps` Docker tasks; keep the `utils` package install as a native `RUN`.

### 3.2 Concrete TODO list for the devcontainer

- [ ] **Add `--connection=local --inventory localhost,` support** so the playbook runs cleanly inside `docker build` with no SSH.
- [ ] **Refactor `dev-deps` to make Docker installation optional** behind a tag or a `dev_deps_install_docker: true` default var. The devcontainer build should set it to `false`.
- [ ] **Make `devtools_user` configurable at runtime** — devcontainers commonly use `vscode` (uid 1000) instead of the host user. Already parameterized via `devtools_user`; just verify nothing else hard-codes the username.
- [ ] **Drop `become: true` paths when running rootless / as a non-root container user.** The image build itself should switch `USER` after the root-only steps.
- [ ] **Create `.devcontainer/Dockerfile`** along these lines:

  ```dockerfile
  # syntax=docker/dockerfile:1.7
  FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

  ARG DEVTOOLS_USER=vscode

  # Minimal deps to run Ansible
  RUN apt-get update \
   && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ansible-core python3-pip git curl ca-certificates sudo \
   && rm -rf /var/lib/apt/lists/*

  # Copy the playbook tree
  COPY --chown=${DEVTOOLS_USER}:${DEVTOOLS_USER} . /opt/wks-setup
  WORKDIR /opt/wks-setup

  # Run dev-deps utils as root (skip docker tasks via tag exclusion)
  RUN ansible-playbook -i inventory/hosts.ini playbook.yml \
        --tags dev-deps --skip-tags docker \
        --connection=local

  USER ${DEVTOOLS_USER}

  # Run dev-tools + dotfiles as the target user
  RUN ansible-playbook -i inventory/hosts.ini playbook.yml \
        --tags dev-tools,dotfiles \
        --connection=local \
        -e devtools_user=${DEVTOOLS_USER}
  ```

- [ ] **Add `--skip-tags docker` capability.** Tag the docker import in `dev-deps/tasks/main.yml`:

  ```yaml
  - name: Install Docker
    import_tasks: docker/main.yml
    become: true
    tags: [docker]
  ```

- [ ] **Create `.devcontainer/devcontainer.json`:**

  ```jsonc
  {
    "name": "wks-setup",
    "build": { "dockerfile": "Dockerfile", "context": ".." },
    "remoteUser": "vscode",
    "features": {
      "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {}
    },
    "mounts": [
      "source=${localEnv:HOME}/.aws,target=/home/vscode/.aws,type=bind,consistency=cached"
    ],
    "customizations": {
      "vscode": {
        "extensions": [
          "golang.go",
          "ms-python.python",
          "hashicorp.terraform",
          "ms-azuretools.vscode-docker"
        ]
      }
    }
  }
  ```

- [ ] **Verify the artifact-marker idempotency works under image rebuilds.** It does — markers live in `{{ software_dir }}` inside the image — but document that bumping a `*_version` invalidates only that tool's layer.
- [ ] **Layer ordering for cache efficiency.** Group infrequently-changed installs (golang, kubectl) in early `RUN` steps and frequently-changed dotfiles last. Consider splitting the second `ansible-playbook` invocation into `dev-tools` then `dotfiles` so a dotfile edit doesn't reinstall toolchains.
- [ ] **Multi-arch build.** Once arch hard-coding (item 2.1) is fixed, build with `docker buildx --platform linux/amd64,linux/arm64`.
- [ ] **Add a `Makefile` target** `make devcontainer-build` that runs `docker build -f .devcontainer/Dockerfile -t wks-setup:dev .`.
- [ ] **CI:** add a job that builds the devcontainer image to catch playbook regressions early.
- [ ] **Document** in README a "Use as a devcontainer" section describing prerequisites (Docker, VS Code Dev Containers extension), `vscode` user mapping, and the omission of the in-container Docker engine.

### 3.3 Image-size strategy: base image & multi-stage build

The default Section-3.2 Dockerfile pulls everything into one stage. With ~20 tools to install — most prebuilt binaries, two compiled from source, plus a Python venv carrying `ansible-core` + `ansible-lint` + `molecule` — the final image is easily 1+ GB. Multi-stage staging cuts this substantially.

#### Base image candidates

| Image | Size | Use as |
|---|---|---|
| `mcr.microsoft.com/devcontainers/base:debian-12` | ~210 MB | **Recommended final stage** — pre-wired `vscode` user, `sudo`, `git`, locale; first-class with VS Code |
| `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` | ~250 MB | Alternate final stage if you need Ubuntu specifics |
| `debian:12-slim` | ~80 MB | Lean alternative final stage if you build the user/sudo wiring yourself |
| `debian:12` (full) | ~120 MB | **Builder stages** — has more dev tooling preinstalled |
| `golang:1.26-bookworm` | ~830 MB | **`gobuild` stage only** for `gopls`/`golangci-lint` |
| `cgr.dev/chainguard/wolfi-base` | ~15 MB | Possible final stage if you want minimal CVE surface; glibc-compatible |
| `alpine:3.20` | ~8 MB | **Avoid** — musl breaks `pyenv`-built CPython, AWS CLI v2's bundled Python, many Go cgo binaries |
| Distroless / `scratch` | <10 MB | **Avoid** — no shell, devcontainers need one |

**Recommendation:** `mcr.microsoft.com/devcontainers/base:debian-12` final, `debian:12` builders. The MS base saves significant friction; the size delta vs `debian:12-slim` (~130 MB) is dwarfed by the toolchain payload.

#### Why this repo benefits from multi-stage

Of the ~20 tools, only **two** need a build toolchain at runtime:

- [vim.yml](roles/dev-tools/tasks/vim.yml) compiles vim from source. (`nvim` is downloaded prebuilt — consider just dropping the source-built vim entirely.)
- [python-tools.yml](roles/dev-tools/tasks/python-tools.yml) compiles a small pyenv Bash speedup extension. The bigger concern: users running `pyenv install <ver>` *inside* the container will compile CPython, which permanently requires `build-essential`, `libssl-dev`, `libffi-dev`, `libsqlite3-dev`, `zlib1g-dev`, `libreadline-dev`, `libbz2-dev`, `liblzma-dev`, `libncurses-dev`, `tk-dev`, `uuid-dev` (~400 MB).

Everything else (`kubectl`, `helm`, `kind`, `k9s`, `terraform`, `eza`, `ccat`, `uv`, `golang`, `aws-cli`, `aws-session-manager-plugin`) is a prebuilt static or mostly-static binary that needs only glibc + ca-certificates at runtime — perfect candidates for `COPY --from=...`.

#### Proposed stage layout

```dockerfile
# syntax=docker/dockerfile:1.7

# Stage 1: downloader — fetches all prebuilt binaries
FROM debian:12-slim AS downloader
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl tar unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /out
COPY scripts/fetch-binaries.sh .
RUN bash fetch-binaries.sh    # mirrors _download_artifact.yml as plain curl

# Stage 2: compiler — vim + pyenv bash extension (drop if not needed)
FROM debian:12 AS compiler
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl autoconf \
      libncurses-dev libacl1-dev libgpm-dev \
 && rm -rf /var/lib/apt/lists/*
# ... compile vim → /opt/vim, pyenv shim → /opt/pyenv

# Stage 3: ansible-venv — pre-bakes the bootstrap venv
FROM debian:12-slim AS ansible-venv
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-venv ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN python3 -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir \
      'ansible-core==2.17.0' 'ansible-lint==24.9.2' 'molecule==24.9.0' \
      'jmespath==1.0.1' 'netaddr==1.3.0' 'passlib==1.7.4'

# Stage 4: gobuild — gopls + golangci-lint (optional)
FROM golang:1.26-bookworm AS gobuild
ARG GOPLS_VERSION=latest
RUN GOBIN=/out go install golang.org/x/tools/gopls@${GOPLS_VERSION}
RUN curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/v1.61.0/install.sh \
      | sh -s -- -b /out v1.61.0

# Final: thin runtime
FROM mcr.microsoft.com/devcontainers/base:debian-12 AS final
ARG DEVTOOLS_USER=vscode
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      git curl jq tmux tree htop unzip ca-certificates \
      libssl3 libffi8 libsqlite3-0 libreadline8 libbz2-1.0 \
      liblzma5 libncursesw6 libtk8.6 libuuid1 zlib1g \
      libacl1 libgpm2 \
      python3 python3-venv \
 && rm -rf /var/lib/apt/lists/*
COPY --from=downloader   /out/                 /usr/local/bin/
COPY --from=compiler     /opt/vim/bin/vim      /usr/local/bin/vim
COPY --from=compiler     /opt/pyenv            /home/${DEVTOOLS_USER}/software/ansible-managed/pyenv
COPY --from=gobuild      /out/                 /usr/local/bin/
COPY --from=ansible-venv /opt/venv             /home/${DEVTOOLS_USER}/software/ansible-managed/python/venvs/system/bootstrap
USER ${DEVTOOLS_USER}
RUN ansible-playbook -i inventory/hosts.ini playbook.yml --tags dotfiles --connection=local
```

#### Approximate size budget

| Stage payload forwarded | Size |
|---|---|
| `downloader` → final (`kubectl`, `helm`, `kind`, `k9s`, `terraform`, `uv`/`uvx`, `eza`, `ccat`, `aws-session-manager-plugin`, AWS CLI v2 install dir) | ~250–300 MB (AWS CLI v2 alone ~120 MB; terraform ~80 MB) |
| `compiler` → final (vim ~3 MB + pyenv tree ~10 MB) | ~15 MB |
| `gobuild` → final (gopls ~30 MB + golangci-lint ~80 MB) | ~110 MB *(decision point: skip and use `go install` lazily?)* |
| `ansible-venv` → final | ~150–200 MB |
| Base + apt runtime libs | ~210 MB + ~80 MB |

**Estimate:** ~750–900 MB with everything; ~500–600 MB if you drop the Go toolchain in-image and either drop molecule or split it out via pipx.

#### Repo-specific size wins

- [ ] **Don't ship the full Go SDK in runtime.** Copy only `go`, `gofmt`, `gopls`, `golangci-lint`. Skip `pkg/`, `src/`, `doc/`, `test/`, `api/`, `misc/` — that's ~120 MB of the 200 MB Go distribution.
- [ ] **Reconsider AWS CLI v2.** It bundles its own Python, ~120 MB. If your team's usage is shallow, `uv tool install awscli` (v1) at ~10 MB or staying on v2 only when needed is worth a look.
- [ ] **Drop the source-built `vim`.** apt's `vim` (already in `common_utils_packages`) plus the prebuilt `nvim` is enough; this removes the entire `compiler` stage's vim dep tree.
- [ ] **Pre-install one CPython via `pyenv install`** in a builder stage and copy it forward (~80 MB) so users skip a 5-min compile on first use. Net positive for devcontainer UX.
- [ ] **Don't bake `molecule` in the base venv** unless you actually run scenarios (~50 MB). Move to a separate `pipx`/venv layer that users opt into.
- [ ] **Discard `aws-session-manager-plugin` archive** after extraction — `software_dir` retains the `.deb`/`.rpm` today; in the image, only the binary needs to ship.
- [ ] **Strip Go binaries** with `-ldflags="-s -w"` for self-built `gopls`/`golangci-lint` (~30% smaller).
- [ ] **`--no-install-recommends`** on every apt invocation (current [utils.yml](roles/dev-deps/tasks/utils.yml) does not pass it). Saves 30–50 MB on Debian by skipping `perl`/`vim-runtime` doc recommendations.
- [ ] **`apt-get clean && rm -rf /var/lib/apt/lists/*`** in every `RUN apt-get` block across stages.
- [ ] **Drop Ansible caches in the final layer** — finish the dotfiles `ansible-playbook` run with `&& rm -rf /root/.ansible /tmp/* ~/.cache/pip`.

#### Required prerequisite: scripts/fetch-binaries.sh

The downloader stage needs a plain-`curl` mirror of [_download_artifact.yml](roles/dev-tools/tasks/_download_artifact.yml) so it doesn't have to drag Ansible in. Generating it from `defaults/main.yml` keeps the version pins as the single source of truth.

- [ ] Add `scripts/fetch-binaries.sh` that consumes the same version vars (e.g. via a `make fetch-script` target that templates from `defaults/main.yml`).
- [ ] Add `make devcontainer-build` (Section 3.2) and `make devcontainer-measure` running `dive wks-setup:dev` to spot regressions.
- [ ] Decide per-team: keep Go SDK in image? AWS CLI v2? molecule in the base venv? Each is a 50–120 MB knob — wire them as `ARG`s with sensible defaults.

---

## 4. Suggested Order of Work

1. Fix the high-priority hygiene bugs (2.1) — they're cheap and unblock everything else.
2. Add `ansible-lint` + `yamllint` + a CI workflow (2.2).
3. Parameterize architecture and tag the Docker subtree (prep for devcontainer).
4. Add `.devcontainer/` per Section 3 (single-stage first, then 3.3 multi-stage refactor once it works).
5. Tackle medium/low items as they come up.
