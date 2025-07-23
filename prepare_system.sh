#!/bin/bash
set -e

usage() {
    echo "Usage: $0 [-u]" >&2
    echo "  -u  Update repository and exit" >&2
    echo "  -h  Show this help message" >&2
}

UPDATE_ONLY=0
while getopts "hu" opt; do
    case $opt in
        u) UPDATE_ONLY=1 ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

# Install required packages unless only updating the repository
if [ "$UPDATE_ONLY" -eq 0 ]; then
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -y
        sudo apt-get install -y ansible git whiptail dialog wget
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y ansible git newt dialog wget
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y ansible git newt dialog wget
    else
        echo "Unsupported package manager. Install ansible, git, whiptail/newt, dialog, and wget manually." >&2
        exit 1
    fi
    # Install yq v4 for YAML processing used by configuration scripts
    sudo wget -qO /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
    sudo chmod +x /usr/local/bin/yq
fi

REPO_URL="https://github.com/XinnorLab/xiNAS/"
REPO_DIR="xiNAS"

# Determine if repo already exists in current directory
if [ -f "ansible.cfg" ] && [ -d "playbooks" ]; then
    REPO_DIR="$(pwd)"
else
    if [ ! -d "$REPO_DIR" ]; then
        git clone "$REPO_URL" "$REPO_DIR"
    fi
    cd "$REPO_DIR"
fi

# If only updating the repository, perform the update and exit
if [ "$UPDATE_ONLY" -eq 1 ]; then
    git reset --hard
    git pull origin main
    exit 0
fi

# Ensure the hardware key utility is executable
[ -x ./hwkey ] || chmod +x ./hwkey

chmod +x simple_menu.sh
./simple_menu.sh
