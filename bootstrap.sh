#/bin/bash

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