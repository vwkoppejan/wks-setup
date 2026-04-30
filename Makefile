-include .env
export

INVENTORY        ?= inventory/hosts.ini
PLAYBOOK         ?= playbook.yml
EXTRA_VARS       ?=
VAULT_PASS_FILE  ?=

# Build ansible-playbook flags from optional variables
_VAULT_FLAG  := $(if $(VAULT_PASS_FILE),--vault-password-file $(VAULT_PASS_FILE),)
_TAGS_FLAG   := $(if $(TAGS),--tags $(TAGS),)
_EXTRA_FLAG  := $(EXTRA_VARS)

ANSIBLE_FLAGS := -i $(INVENTORY) $(_VAULT_FLAG) $(_TAGS_FLAG) $(_EXTRA_FLAG)

.PHONY: run dev-deps dev-tools dotfiles check syntax bootstrap help

run:
	ansible-playbook $(ANSIBLE_FLAGS) -K $(PLAYBOOK)

dev-deps:
	ansible-playbook $(ANSIBLE_FLAGS) --tags dev-deps -K $(PLAYBOOK)

dev-tools:
	ansible-playbook $(ANSIBLE_FLAGS) --tags dev-tools $(PLAYBOOK)

dotfiles:
	ansible-playbook $(ANSIBLE_FLAGS) --tags dotfiles $(PLAYBOOK)

check:
	ansible-playbook $(ANSIBLE_FLAGS) --check $(PLAYBOOK)

## syntax: validate playbook syntax only
syntax:
	ansible-playbook $(ANSIBLE_FLAGS) --syntax-check $(PLAYBOOK)

galaxy:
	ansible-galaxy install -r requirements.yml

## bootstrap: install ansible-core on a fresh machine
bootstrap:
	bash bootstrap.sh

## help: show this message
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## //'
