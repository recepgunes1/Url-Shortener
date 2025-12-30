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

sudo apt install -y curl git

curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

mkdir -p ~/.kube

sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config

sudo chown $USER:$USER ~/.kube/config

chmod 600 ~/.kube/config

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
