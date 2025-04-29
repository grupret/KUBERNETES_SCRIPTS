#!/bin/bash

if [ "$(whoami)" != "root" ]; then
  sudo su -c "bash $0"
  exit
fi

export DEBIAN_FRONTEND=noninteractive

# Define variables
METALLB_MANIFEST_URL="https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml"
METALLB_CONFIG_FILE="metallb-config.yaml"

# Step 1: Install MetalLB using the manifest
echo "Applying MetalLB manifest..."
kubectl apply -f $METALLB_MANIFEST_URL
if [ $? -ne 0 ]; then
  echo "Failed to apply MetalLB manifest."
  exit 1
fi

echo "Sleep 60s"
sleep 60

# Step 2: Create MetalLB ConfigMap YAML with IP address pool and advertisement Example:- 10.0.0.103-10.0.0.104
echo "Creating MetalLB configuration..."

cat > $METALLB_CONFIG_FILE <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: metallb
  namespace: metallb-system
spec:
  addresses:
  - $IP_ADDRESS

---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: kubeflow-advert
  namespace: metallb-system
EOF

# Step 3: Apply the MetalLB configuration

echo "Sleep 60s"
sleep 60
echo "Applying MetalLB configuration..."

kubectl apply -f $METALLB_CONFIG_FILE
if [ $? -ne 0 ]; then
  echo "Failed to apply MetalLB configuration."
  exit 1
fi

# Step 4: Verify the installation
echo "Verifying MetalLB installation..."
kubectl get pods -n metallb-system
if [ $? -ne 0 ]; then
  echo "MetalLB installation verification failed."
  exit 1
fi

echo "MetalLB setup completed successfully."
