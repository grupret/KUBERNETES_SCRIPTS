#!/bin/bash

# Prompt user for external IP
read -p "Enter the external IP address to expose Ollama service: " IP_ADDRESS

# Add Helm repo
helm repo add ollama-helm https://otwld.github.io/ollama-helm/
helm repo update

# Create Kubernetes namespace
kubectl create namespace ollama

# Deploy Ollama with GPU enabled
helm install appli-ollama ollama-helm/ollama \
  --namespace ollama \
  --set ollama.gpu.enabled=true \
  --set ollama.gpu.number=1 \
  --set ollama.gpu.type=nvidia

# Wait for the pod to be ready
echo "Waiting for Ollama pods to be ready..."
kubectl wait --for=condition=Ready pods --all --namespace ollama --timeout=120s

# Show pod details
kubectl get pods -n ollama -o wide

# Create a NodePort service using the provided external IP
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ollamanodeportservice
  namespace: ollama
spec:
  selector:
    app.kubernetes.io/name: ollama
  type: NodePort
  ports:
    - protocol: TCP
      port: 80
      targetPort: 11434
  externalIPs:
    - ${IP_ADDRESS}
EOF

# Confirm service creation
echo "Ollama NodePort service created with external IP: $IP_ADDRESS"
kubectl get svc -n ollama
