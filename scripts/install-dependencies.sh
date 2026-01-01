#!/bin/bash

# Exit immediately if any command fails
set -e

# Prevent running as root - k3s and user config should be set up for normal user
if [ "$EUID" -eq 0 ]; then
    echo "Do not run this script as root. Run as a user with sudo privileges."
    exit 1
fi

# Verify the user has sudo privileges for package installation
if ! sudo -v &>/dev/null; then
    echo "User '$USER' does not have sudo privileges."
    exit 1
fi

# Perform comprehensive system update
# - apt clean: Clear local repository cache
# - apt update: Refresh package lists
# - apt upgrade: Install available updates
# - apt dist-upgrade: Handle dependencies intelligently
# - apt autoclean: Remove obsolete package files
# - apt autoremove: Remove orphaned packages
sudo apt clean && sudo apt update -y && sudo apt upgrade -y && sudo apt dist-upgrade -y && sudo apt autoclean -y && sudo apt autoremove -y

# Install required command-line tools:
# - curl: HTTP client for downloading installers
# - git: Version control (for repository management)
# - redis-tools: Redis CLI for connectivity testing
# - postgresql-client: PostgreSQL CLI (psql) for connectivity testing
sudo apt install -y curl git redis-tools postgresql-client

# Install k3s using the official installer script
# - --write-kubeconfig-mode 644: Makes kubeconfig readable by non-root users
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

# Create the standard kubectl config directory
mkdir -p ~/.kube

# Copy k3s kubeconfig to standard kubectl location
# k3s places its config at /etc/rancher/k3s/k3s.yaml by default
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config

# Change ownership from root to current user
sudo chown $USER:$USER ~/.kube/config

# Set secure permissions (readable only by owner)
chmod 600 ~/.kube/config

# Install Helm using the official installer script
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Base URL for downloading additional scripts from the repository
REPO_BASE_URL="https://raw.githubusercontent.com/recepgunes1/Url-Shortener/main/scripts"

# Downloads a script file if it doesn't already exist locally
download_if_missing() {
    local filename="$1"
    local filepath="${SCRIPT_DIR}/${filename}"
    
    if [ ! -f "$filepath" ]; then
        echo "Downloading ${filename}..."
        curl -fsSL "${REPO_BASE_URL}/${filename}" -o "$filepath"
        
        # Make the script executable
        chmod +x "$filepath"
        echo "${filename} downloaded successfully"
    else
        echo "${filename} already exists, skipping download"
    fi
}

# Download the deployment and testing scripts if not present
download_if_missing "deploy-stack.sh"
download_if_missing "test-postgresql-connection.sh"
download_if_missing "test-redis-connection.sh"