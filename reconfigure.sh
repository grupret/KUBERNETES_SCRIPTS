###Master

export interface="$(ip route | grep default | awk '{print $5}')"  # Find with 'ip addr'
export ipAddress="$(ip -o -4 addr show $interface | grep -v '127.0.0.1' | awk '{print $4}' | cut -d/ -f1)"   # Require even if 'configureTCPIPSetting' is set to 'false'.
export netmask="$(ip -o -4 addr show $interface | grep -v '127.0.0.1' | awk '{print $4}' | cut -d/ -f2)"
export defaultGateway="$(ip route | grep default | awk '{print $3}')"

local_ip="$(ip --json addr show $interface | jq -r '.[0].addr_info[] | select(.family == "inet") | .local')"
sudo tee /etc/default/kubelet > /dev/null << EOF
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
EOF

cat /etc/default/kubelet



kubeadm reset --force
kubeadm init


rm -rf ~/.kube/config
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl apply -f calico.yaml
kubectl apply -f metric.yaml 


##worker node

export interface="$(ip route | grep default | awk '{print $5}')"  # Find with 'ip addr'
export ipAddress="$(ip -o -4 addr show $interface | grep -v '127.0.0.1' | awk '{print $4}' | cut -d/ -f1)"   # Require even if 'configureTCPIPSetting' is set to 'false'.
export netmask="$(ip -o -4 addr show $interface | grep -v '127.0.0.1' | awk '{print $4}' | cut -d/ -f2)"
export defaultGateway="$(ip route | grep default | awk '{print $3}')"

local_ip="$(ip --json addr show $interface | jq -r '.[0].addr_info[] | select(.family == "inet") | .local')"
sudo tee /etc/default/kubelet > /dev/null << EOF
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
EOF

cat /etc/default/kubelet

kubeadm reset --force

kubeadm join 139.84.216.231:6443 --token q15bh0.la3vul52y3w3snpz \
	--discovery-token-ca-cert-hash sha256:77a112476163b15148b633e9f94f798ff48ee2da8e65f8bfc9da667f33c5637e

# kubeadm join 139.84.214.113:6443 --token mxpqbo.ir8q0tfd6pvxaifl \
# 	--discovery-token-ca-cert-hash sha256:9d3596513ff7c6adc74e75409decaad2d90f6fe968909e84aab8c744ee63e408 
