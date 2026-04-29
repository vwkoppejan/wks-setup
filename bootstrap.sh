#!/usr/bin/env bash
set -euo pipefail

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Re-running with sudo..."
    exec sudo "$0" "$@"
fi

if [ -x "$(command -v apt)" ]; then
    apt update -y
    apt install -y ansible-core
elif [ -x "$(command -v dnf)" ]; then
    dnf check-update -y
    dnf install -y ansible-core
else
    echo "Neither apt nor dnf package manager found. Please install ansible-core manually."
    exit 1
fi