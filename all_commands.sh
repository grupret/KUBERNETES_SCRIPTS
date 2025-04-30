  1  git clone https://github.com/grupret/KUBERNETES_SCRIPTS.git
    2  ls
    3  cd KUBERNETES_SCRIPTS/
    4  ls
    5  vi master.sh 
    6  chmod +x master.sh 
    7  ./master.sh 
    8  ls
    9  vi calico.yaml 
   10  kubectl apply -f calico.yaml 
   11  kubectl apply -f metrics.yaml 
   12  kubectl taint nodes node-master node-role.kubernetes.io/control-plane-
   13  kubectl taint nodes ori node-role.kubernetes.io/control-plane-
   14  kubectl label nodes ori node.kubernetes.io/exclude-from-external-load-balancers-
   15  kubectl get pods -A
   16  vi metal.sh 
   17  chmod +x metal.sh 
   18  ./metal.sh 
   19  kubectl get pods -A
   20  ls
   21  vi longhorn.sh 
   22  chmod +x longhorn.sh 
   23  ./longhorn.sh 
   24  kubectl get pods -A
   25  watch kubectl get pods -A
   26  kubectl get pods -A
   27  nvidia-smi
   28  swapoff -a
   29  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
   30  apt-get update
   31  apt-get install -y nvidia-container-toolkit
   32  nvidia-container-cli --version
   33  ls
   34  vi install_helm.sh 
   35  chmod +x install_helm.sh 
   36  ./install_helm.sh 
   37  helm repo add nvidia https://nvidia.github.io/gpu-operator
   38  helm repo update
   39  helm install --wait --generate-name nvidia/gpu-operator
   40  kubectl get pods | grep nvidia
   41  watch kubectl get pods | grep nvidia
   42  kubectl get pods | grep nvidia
   43  kubectl describe nodes | grep nvidia
   44  kubectl describe nodes ori
   45  sudo snap install juju --channel=3.4/stable
   46  mkdir -p ~/.local/share
   47  kubectl config view --raw 
   48  kubectl config view --raw | juju add-k8s my-k8s --client
   49  juju bootstrap my-k8s uk8sx
   50  juju add-model kubeflow
   51  juju deploy kubeflow --trust --channel=1.9/stable
   52  kubectl get pods -A
   53  juju status --watch 
   54  juju status --watch 2
   55  juju status --watch 5s
   56  juju status 
   57  kubectl get pods -A
   58  kubectl get svc -A
   59  juju config dex-auth static-username=admin
   60  juju config dex-auth static-password=admin
