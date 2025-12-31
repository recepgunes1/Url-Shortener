#!/bin/bash
set -e

if [ "$EUID" -eq 0 ]; then
    echo "Do not run this script as root. Run as a user with sudo privileges."
    exit 1
fi

if ! sudo -v &>/dev/null; then
    echo "User '$USER' does not have sudo privileges."
    exit 1
fi

sudo apt clean && sudo apt update -y && sudo apt upgrade -y && sudo apt dist-upgrade -y && sudo apt autoclean -y && sudo apt autoremove -y

sudo apt install -y curl git redis-tools postgresql-client

curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

mkdir -p ~/.kube

sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config

sudo chown $USER:$USER ~/.kube/config

chmod 600 ~/.kube/config

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_BASE_URL="https://raw.githubusercontent.com/recepgunes1/Url-Shortener/main/scripts"

download_if_missing() {
    local filename="$1"
    local filepath="${SCRIPT_DIR}/${filename}"
    
    if [ ! -f "$filepath" ]; then
        echo "Downloading ${filename}..."
        curl -fsSL "${REPO_BASE_URL}/${filename}" -o "$filepath"
        chmod +x "$filepath"
        echo "${filename} downloaded successfully"
    else
        echo "${filename} already exists, skipping download"
    fi
}

download_if_missing "deploy-stack.sh"
download_if_missing "test-postgresql-connection.sh"
download_if_missing "test-redis-connection.sh"
