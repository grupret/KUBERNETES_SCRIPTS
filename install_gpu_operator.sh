#!/bin/bash

set -e

echo "=== Step 1: Adding NVIDIA GPG key and container toolkit repo ==="
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

echo "=== Step 2: Installing NVIDIA Container Toolkit ==="
apt-get update
apt-get install -y nvidia-container-toolkit

echo "=== Step 3: Verifying NVIDIA container CLI installation ==="
nvidia-container-cli --version

echo "=== Step 4: Adding NVIDIA Helm repo ==="
helm repo add nvidia https://nvidia.github.io/gpu-operator
helm repo update

echo "=== Step 5: Installing NVIDIA GPU Operator ==="
helm install --wait --generate-name nvidia/gpu-operator

echo "=== ✅ NVIDIA GPU Operator deployed successfully ==="
