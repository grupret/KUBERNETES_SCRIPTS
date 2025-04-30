#!/bin/bash

set -euo pipefail

# --- Input & Configuration ---
if [ $# -ne 1 ]; then
  echo "Usage: $0 <LOAD_BALANCER_IP>"
  exit 1
fi
LOAD_BALANCER_IP="$1"
NAMESPACE="hugs"
RELEASE_NAME="hugs-gateway"
HUGS_HELM_REPO="https://huggingface.github.io/hugs"
HUGS_CHART="hugs/hugs"
HUGS_CHART_VERSION="0.3.0"
HF_TOKEN=$TOKEN

# --- Prerequisites check ---
helm version --short >/dev/null 2>&1 || { echo "Helm v3+ is required"; exit 1; }
kubectl version --client --short >/dev/null 2>&1 || { echo "kubectl is required"; exit 1; }

# --- Namespace & Helm repo setup ---
kubectl create namespace $NAMESPACE >/dev/null 2>&1 || echo "Namespace '$NAMESPACE' exists" :contentReference[oaicite:2]{index=2}
helm repo add hugs $HUGS_HELM_REPO >/dev/null
helm repo update >/dev/null

# --- Create HF token secret ---
kubectl -n $NAMESPACE create secret generic huggingface-token \
  --from-literal=token=$HF_TOKEN \
  --dry-run=client -o yaml | kubectl apply -f - :contentReference[oaicite:3]{index=3}

# --- Generate override values for LoadBalancer service ---
cat <<EOF > hugsv2-values.yaml
# Override the default NodePort service to LoadBalancer:
service:
  type: LoadBalancer      # Externally-facing LB service :contentReference[oaicite:4]{index=4}
  port: 80                # External port
  targetPort: 8080        # Pod port to route traffic to
  loadBalancerIP: $LOAD_BALANCER_IP  # Static IP to assign :contentReference[oaicite:5]{index=5}
# Use the HF token secret
env:
  HUGGINGFACE_TOKEN:
    valueFrom:
      secretKeyRef:
        name: huggingface-token
        key: token
EOF

# --- Deploy/Upgrade HUGS with Helm ---
helm upgrade --install $RELEASE_NAME hugs/hugs \
  --namespace $NAMESPACE \
  --version $HUGS_CHART_VERSION \
  -f hugsv2-values.yaml :contentReference[oaicite:6]{index=6}

# --- Wait for rollout ---
echo "⏳ Waiting for HUGS deployment to become ready..."
kubectl rollout status deployment/$RELEASE_NAME -n $NAMESPACE --timeout=180s

# --- Output ---
echo "✅ HUGS is available via LoadBalancer IP: $LOAD_BALANCER_IP on port 80"
