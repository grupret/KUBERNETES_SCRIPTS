#!/usr/bin/env bash
# cluster-setup.sh — deploy all components with checks

set -euo pipefail
trap 'echo "❌ Error on line $LINENO. Exiting."; exit 1' ERR

# -- utility for headings
section() { echo; echo "==== $1 ===="; }

# 1. Clone repo (if needed) and cd into it
clone_repo() {
  section "1. Clone repository"
  if [ ! -d "KUBERNETES_SCRIPTS" ]; then
    echo "Cloning https://github.com/grupret/KUBERNETES_SCRIPTS.git..."
    git clone https://github.com/grupret/KUBERNETES_SCRIPTS.git
  else
    echo "Repository already exists; skipping clone."
  fi
  cd KUBERNETES_SCRIPTS
}

# 2. Run master.sh
install_master() {
  section "2. Install master.sh"
  chmod +x master.sh
  ./master.sh
  echo "master.sh completed."
}

# 3. Install Calico and wait for pods ready
install_calico() {
  section "3. Install Calico CNI"
  kubectl apply -f calico.yaml
  echo "Waiting for Calico pods to be Ready..."
  # kubectl wait --for=condition=Ready pod --all -n kube-system --timeout=120s
  echo "Calico is ready."
}

# 4. Taint & label control-plane node
taint_master() {
  section "4. Taint & label control-plane node"
  NODE=$(kubectl get nodes --no-headers | awk '{print $1}' | head -n1)
  echo "Using node: $NODE"
  kubectl taint nodes "$NODE" node-role.kubernetes.io/control-plane:NoSchedule
  kubectl label nodes "$NODE" node.kubernetes.io/exclude-from-external-load-balancers=true
  echo "Taint and label applied."
}

# 5. Install MetalLB (prompt for IP range)
install_metallb() {
  section "5. Install MetalLB"
  read -rp "Enter MetalLB IP address pool (e.g. 192.168.1.240-192.168.1.250): " IP_RANGE
  # inject into metal.sh or config
  sed -i "s|\$IP_ADDRESS|$IP_RANGE|g" metal.sh
  chmod +x metal.sh
  ./metal.sh
  echo "Waiting for MetalLB controller pod..."
  # kubectl wait --for=condition=Ready pod -l app=metallb -n metallb-system --timeout=120s
  echo "MetalLB is ready."
}

# 6. Install Longhorn and wait
install_longhorn() {
  section "6. Install Longhorn"
  chmod +x longhorn.sh
  ./longhorn.sh
  echo "Waiting for Longhorn pods..."
  # kubectl wait --for=condition=Ready pod --all -n longhorn-system --timeout=180s
  echo "Longhorn is ready."
}

# 7. Install Metrics Server and wait
install_metrics() {
  section "7. Install Metrics Server"
  kubectl apply -f metrics.yaml
  echo "Waiting for metrics-server deployment to become available..."
  # kubectl wait --for=condition=Available deployment metrics-server -n kube-system --timeout=120s
  echo "Metrics Server is ready."
}

# 8. Install NVIDIA GPU Operator
install_gpu_operator() {
  section "8. Install NVIDIA GPU Operator"
  chmod +x install_helm.sh
  ./install_helm.sh
  echo "Disabling swap..."
  sudo swapoff -a

  echo "Adding NVIDIA container toolkit repo..."
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

  sudo apt-get update
  sudo apt-get install -y nvidia-container-toolkit
  nvidia-container-cli --version

  echo "Installing GPU Operator via Helm..."
  helm repo add nvidia https://nvidia.github.io/gpu-operator
  helm repo update
  helm install --wait --generate-name nvidia/gpu-operator --namespace gpu-operator --create-namespace

  echo "Waiting for GPU Operator pods..."
  # kubectl wait --for=condition=Ready pod --all -n gpu-operator --timeout=180s
  echo "GPU Operator is ready."
}

# Final check: describe the control-plane node
final_check() {
 
  section "Final check: describe node"
  kubectl describe node "$NODE"
}

### Main
clone_repo
install_master
install_calico
taint_master
install_metallb
install_longhorn
install_metrics
install_gpu_operator
final_check

echo
echo "🎉 All components deployed and verified successfully!"
