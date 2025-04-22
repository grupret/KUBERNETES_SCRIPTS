#!/bin/bash

if [ "$(whoami)" != "root" ]; then
  sudo su -c "bash $0"
  exit
fi

# set -e  # Exit immediately if a command exits with a non-zero status
# set -o pipefail  # Return the exit code of the first failed command in a pipeline

# set -x  # Enable command tracing for debugging

# ------------------------------
# Host TCP/IP Settings
# ------------------------------
export configureTCPIPSetting=false
export interface="$(ip route | grep default | awk '{print $5}')"  # Find with 'ip addr'
export ipAddress="$(ip -o -4 addr show $interface | grep -v '127.0.0.1' | awk '{print $4}' | cut -d/ -f1)"   # Require even if 'configureTCPIPSetting' is set to 'false'.
export netmask="$(ip -o -4 addr show $interface | grep -v '127.0.0.1' | awk '{print $4}' | cut -d/ -f2)"
export defaultGateway="$(ip route | grep default | awk '{print $3}')"
export dnsServers=("8.8.8.8" "8.8.4.4")                     # Don't specify more than 3. K8s will only use the first three and throw errors.
export DEBIAN_FRONTEND=noninteractive

# export dnsSearch=("domain.local")  # Your local DNS search domain if you have one.
# ------------------------------
# export kube_version=1.31
# # Example: Display IP address of the selected interface

# ip addr show "$interface"
echo "Lan Interface $interface"
echo "Lan Ip-Address $ipAddress"

# ------------------------------
# Parameters
# ------------------------------
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --configure-tcpip) configureTCPIPSetting="$2"; shift; shift;;
        --interface) interface="$2"; shift; shift;;
        --ip-address) ipAddress="$2"; shift; shift;;
        --netmask) netmask="$2"; shift; shift;;
        --default-gateway) defaultGateway="$2"; shift; shift;;
        --dns-servers) dnsServers=($2); shift; shift;;
        --dns-search) dnsSearch=($2); shift; shift;;
        --k8s-version) k8sVersion="$2"; shift; shift;;
        --k8s-load-balancer-ip-range) k8sLoadBalancerIPRange="$2"; shift; shift;;
        --k8s-allow-master-node-schedule) k8sAllowMasterNodeSchedule="$2"; shift; shift;;
        *) echo -e "\e[31mError:\e[0m Parameter \e[35m$key\e[0m is not recognised."; exit 1;;
    esac
done

# Perform Validation
# # # --------------------------------------------------------------------------------------------------------------------------------------------------------
# CPU Informations x86-64-level
echo "====== Starting the Script ======"

# Check if x86-64-level file already exists
if [ ! -f "./x86-64-level" ]; then
  echo "[Step 1/3] Info: x86-64-level not found. Downloading..."
  curl -L -O https://raw.githubusercontent.com/HenrikBengtsson/x86-64-level/main/x86-64-level > /dev/null 2>&1
  chmod ugo+x x86-64-level
  echo "[Success] x86-64-level downloaded and made executable."
else
  echo "[Step 1/3] Info: x86-64-level already exists. Skipping download."
  # Check if file is executable; if not, set the executable permission
  if [ ! -x "./x86-64-level" ]; then
    echo "[Step 1.1] Info: x86-64-level exists but is not executable. Setting permissions..."
    chmod ugo+x x86-64-level
  fi
fi

# Run the command to get CPU version
echo "[Step 2/3] Checking CPU version..."
cpu_version=$(./x86-64-level)

# Check if the CPU version is 3 or 4
if [[ "$cpu_version" == "3" || "$cpu_version" == "4" ]]; then
  echo "[Step 3/3] Processor version is suitable: x86-64-v$cpu_version. Continuing with the script..."
  echo "[Success Phase] Running the final script and outputting results..."
else
  echo "Error: Processor version x86-64-v$cpu_version is not suitable. Stopping the script."
  exit 1
fi

# Debugging Information
echo "Debug Information:"
echo "-> CPU version detected: $cpu_version"
echo "====== Script Completed Successfully ======"

# -----------------------------------------------------------------------------------------------------------------------------------------------------------
# Privileges Check
check_sudo_privileges() {
  echo -e "\033[32mChecking root access\033[0m"
  if [ "$(id -u)" -ne 0 ]; then
    echo -e "\033[31mYou must run this script as root\033[0m"
    exit 1
  fi
}

check_sudo_privileges

# Check & keep running
echo -e "\033[32mChecking root access\033[0m"

if [ "$(id -u)" -ne 0 ]; then
  echo -e "\033[31mYou must run this script as root\033[0m"
  exit
fi

# Prevent interactive needsrestart command
export NEEDSRESART_CONF="/etc/needrestart/needrestart.conf"

if [ -f $NEEDSRESART_CONF ]; then 
  echo -e "\033[32mDisabling needsrestart interactive mode\033[0m"  
  sed -i "/#\$nrconf{restart} = 'i';/s/.*/\$nrconf{restart} = 'a';/" $NEEDSRESART_CONF
fi

## ----------------------------------------------------------------------------------------------------------------------------------------------------
## Firewal Disable 

systemctl disable --now ufw

# ------------------------------------------------------------------------------------------------------------------------------------------------------
echo "====== Step 1: Displaying Current Swaps ======"
cat /proc/swaps

# Check if swap is active (excluding header)
ACTIVE_SWAP_COUNT=$(awk 'NR>1 {count++} END {print count+0}' /proc/swaps)
if [ "$ACTIVE_SWAP_COUNT" -eq 0 ]; then
  echo "No active swap found. Swap is already disabled."
else
  echo "====== Step 2: Disabling Swap ======"
  echo "Disabling all swap partitions and files..."
  swapoff -a
  echo "[Success] Swap has been disabled."
fi

echo "====== Step 3: Removing Swap Entries from /etc/fstab ======"

# Backup /etc/fstab if not already backed up.
if [ ! -f /etc/fstab.bak ]; then
  echo "Creating backup of /etc/fstab..."
  cp /etc/fstab /etc/fstab.bak
  echo "[Success] Backup created at /etc/fstab.bak."
else
  echo "[Info] Backup /etc/fstab.bak already exists. Skipping backup."
fi

# Check for any active (uncommented) swap entries.
if grep -E '^[[:space:]]*[^#].*\bswap\b' /etc/fstab > /dev/null; then
  echo "Commenting out swap entries in /etc/fstab..."
  # Comment out any line with "swap" that is not already commented.
  sed -i.bak '/^[[:space:]]*[^#].*\bswap\b/ s/^/#/' /etc/fstab
  echo "[Success] Swap entries have been commented out in /etc/fstab."
else
  echo "No active swap entries found in /etc/fstab. Skipping modification."
fi

echo "====== Swap has been successfully disabled! ======"
## -----------------------------------------------------------------------------------------------------------------------------------------------------
# Creating Huge Page Service Configuration
# Function to create the service file

SERVICE_PATH="/etc/systemd/system/hugepage-setup.service"

# Expected service content
read -r -d '' EXPECTED_CONTENT << 'EOF'
[Unit]
Description=Set Huge Page Parameters

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo defer+madvise > /sys/kernel/mm/transparent_hugepage/defrag && echo always > /sys/kernel/mm/transparent_hugepage/enabled && echo 0 > /proc/sys/vm/swappiness'

[Install]
WantedBy=multi-user.target
EOF

# Create or update the service file only if necessary.
if [ ! -f "$SERVICE_PATH" ] || ! diff -q <(echo "$EXPECTED_CONTENT") "$SERVICE_PATH" >/dev/null; then
  echo "Updating $SERVICE_PATH..."
  echo "$EXPECTED_CONTENT" | sudo tee "$SERVICE_PATH" > /dev/null
else
  echo "$SERVICE_PATH already exists with the expected content. Skipping creation."
fi

# Reload systemd manager configuration.
sudo systemctl daemon-reload

# Enable the service to start at boot if not already enabled.
if ! systemctl is-enabled hugepage-setup.service >/dev/null 2>&1; then
  echo "Enabling hugepage-setup.service..."
  sudo systemctl enable hugepage-setup.service
else
  echo "hugepage-setup.service is already enabled."
fi

# Start the service immediately.
echo "Starting hugepage-setup.service..."
sudo systemctl start hugepage-setup.service

# Confirm the service is enabled.
if systemctl is-enabled hugepage-setup.service >/dev/null 2>&1; then
  echo "hugepage-setup.service has been successfully enabled."
else
  echo "Failed to enable hugepage-setup.service."
fi

## ------------------------------------------------------------------------------------------------------------------------------------------------------
## Limits Configuration

# File path for limits.conf
LIMITS_FILE="/etc/security/limits.conf"

# Backup the existing limits.conf file
BACKUP_FILE="/etc/security/limits.conf.bak"
if [ -f "$LIMITS_FILE" ]; then
    echo "Backing up existing limits.conf to $BACKUP_FILE"
    sudo cp "$LIMITS_FILE" "$BACKUP_FILE"
fi

# Add or update entries in limits.conf
sudo sed -i "/^\*.*nofile/d" "$LIMITS_FILE"
sudo sed -i "/^\*.*stack/d" "$LIMITS_FILE"
sudo sed -i "/^\*.*memlock/d" "$LIMITS_FILE"

cat <<EOF | sudo tee -a "$LIMITS_FILE"
# File Descriptor Limits
*       hard    nofile  4294967295
*       soft    nofile  4294967295

# Stack Size
*       hard    stack   2147483647
*       soft    stack   2147483647

# Memory Lock
*       hard    memlock 17592186044416
*       soft    memlock 17592186044416
EOF

# Confirm the changes
if grep -q "4294967295" "$LIMITS_FILE"; then
    echo "Limits successfully updated in $LIMITS_FILE."
else
    echo "Failed to update limits in $LIMITS_FILE."
fi

###------------------------------------------------------------------------------------------------------------------------------------###
echo "====== Starting Containerd Installation ======"

# Pre-check: If containerd is active and required components exist, skip installation.
if sudo systemctl is-active --quiet containerd && \
   [ -f /etc/containerd/config.toml ] && \
   [ -x /usr/local/sbin/runc ] && \
   [ -f /usr/lib/systemd/system/containerd.service ] && \
   [ -d /opt/cni/bin ] && [ "$(ls -A /opt/cni/bin 2>/dev/null)" ]; then
  echo "Containerd, runc, and CNI plugins are already installed and running. Skipping installation."
else
  # Step 1: Download and install containerd
  CONTAINERD_TARBALL="containerd-1.6.2-linux-amd64.tar.gz"
  if [ ! -f "$CONTAINERD_TARBALL" ]; then
    echo "[Step 1/9] Downloading containerd tarball..."
    wget https://github.com/containerd/containerd/releases/download/v1.6.2/containerd-1.6.2-linux-amd64.tar.gz
  else
    echo "[Step 1/9] containerd tarball already exists. Skipping download."
  fi

  echo "[Step 2/9] Installing containerd..."
  sudo tar -C /usr/local -xvzf $CONTAINERD_TARBALL

  # Step 2: Download and move containerd service file
  SERVICE_FILE="containerd.service"
  SERVICE_DEST="/usr/lib/systemd/system/containerd.service"
  if [ ! -f "$SERVICE_FILE" ]; then
    echo "[Step 3/9] Downloading containerd service file..."
    wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
  else
    echo "[Step 3/9] containerd service file already exists locally. Skipping download."
  fi

  if [ ! -f "$SERVICE_DEST" ]; then
    echo "[Step 3/9] Moving containerd service file to /usr/lib/systemd/system/..."
    sudo mv $SERVICE_FILE $SERVICE_DEST
  else
    echo "[Step 3/9] containerd service file already present at $SERVICE_DEST. Skipping move."
  fi

  # Step 3: Reload systemd, enable, and start containerd
  echo "[Step 4/9] Reloading systemd and starting containerd..."
  sudo systemctl daemon-reload
  sudo systemctl enable --now containerd

  # Step 4: Download and install runc
  RUNC_FILE="runc.amd64"
  if [ ! -f "$RUNC_FILE" ]; then
    echo "[Step 5/9] Downloading runc..."
    wget https://github.com/opencontainers/runc/releases/download/v1.1.1/runc.amd64
  else
    echo "[Step 5/9] runc file already exists. Skipping download."
  fi

  echo "[Step 5/9] Installing runc..."
  sudo install -m 755 $RUNC_FILE /usr/local/sbin/runc

  # Step 5: Create containerd configuration
  echo "[Step 6/9] Creating containerd configuration..."
  sudo mkdir -p /etc/containerd/
  containerd config default | sudo tee /etc/containerd/config.toml

  # Step 6: Update SystemdCgroup setting in configuration
  echo "[Step 7/9] Updating SystemdCgroup setting in containerd config..."
  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
  sudo systemctl restart containerd

  # Step 7: Set up CNI plugins
  CNI_TARBALL="cni-plugins-linux-amd64-v1.1.1.tgz"
  echo "[Step 8/9] Setting up CNI plugins..."
  sudo mkdir -p /opt/cni/bin/
  if [ ! -f "$CNI_TARBALL" ]; then
    echo "[Step 8/9] Downloading CNI plugins tarball..."
    wget https://github.com/containernetworking/plugins/releases/download/v1.1.1/cni-plugins-linux-amd64-v1.1.1.tgz
  else
    echo "[Step 8/9] CNI plugins tarball already exists. Skipping download."
  fi

  echo "[Step 8/9] Extracting CNI plugins..."
  sudo tar -C /opt/cni/bin -xzvf $CNI_TARBALL

  # Step 8: Cleanup downloaded files
  echo "[Step 9/9] Cleaning up downloaded files..."
  rm -f $CONTAINERD_TARBALL $RUNC_FILE $CNI_TARBALL
fi

echo "====== Containerd Installation Completed ======"

# Continue with next parts of your script...
echo "Limits successfully updated in /etc/security/limits.conf."
# ... (next steps go here)

# -------------------------------------------------------------------------------------------------------- #
# Step 1: Configuring Kernel Modules
echo "====== Step 1: Configuring Kernel Modules ======"

# Check if the kernel modules configuration file already exists
if [ -f /etc/modules-load.d/k8s.conf ]; then
  echo "[Info] /etc/modules-load.d/k8s.conf already exists. Skipping creation."
else
  echo "Creating /etc/modules-load.d/k8s.conf..."
  cat <<EOF | tee /etc/modules-load.d/k8s.conf > /dev/null
overlay
br_netfilter
EOF
  echo "[Success] Kernel module configuration file created."
fi

# Loading kernel modules
echo "Loading kernel modules 'overlay' and 'br_netfilter'..."
modprobe overlay
modprobe br_netfilter
echo "[Success] Kernel modules loaded."

# Step 2: Configuring Sysctl Settings
echo "====== Step 2: Configuring Sysctl Settings ======"

# Check if the sysctl configuration file already exists
if [ -f /etc/sysctl.d/k8s.conf ]; then
  echo "[Info] /etc/sysctl.d/k8s.conf already exists. Skipping creation."
else
  echo "Creating /etc/sysctl.d/k8s.conf with necessary settings..."
  cat <<EOF | tee /etc/sysctl.d/k8s.conf > /dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
  echo "[Success] Sysctl configuration file created."
fi

# Check if the line is already present in /etc/sysctl.conf before appending
if grep -q "^net.ipv4.ip_forward\s*=\s*1" /etc/sysctl.conf; then
  echo "[Info] 'net.ipv4.ip_forward = 1' already exists in /etc/sysctl.conf. Skipping append."
else
  echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
  echo "[Success] 'net.ipv4.ip_forward = 1' appended to /etc/sysctl.conf."
fi

# Apply sysctl settings
sysctl net.bridge.bridge-nf-call-iptables=1 > /dev/null
sysctl --system
sysctl -p

echo "[Success] Sysctl settings applied."

##############################################################################################################

echo "====== Step 1: Backing Up Sysctl Configuration ======"
if [ -f /etc/sysctl.conf.bak ]; then
  echo "[Info] Backup already exists at /etc/sysctl.conf.bak. Skipping backup."
else
  echo "Creating a backup of the current sysctl configuration..."
  cp /etc/sysctl.conf /etc/sysctl.conf.bak
  echo "[Success] Backup created at /etc/sysctl.conf.bak."
fi

echo "====== Step 2: Updating Sysctl Configuration ======"
echo "Adding required settings to /etc/sysctl.conf..."

# Check and add tcp_max_tw_buckets setting
if grep -q "^net.ipv4.tcp_max_tw_buckets" /etc/sysctl.conf; then
  echo "[Info] net.ipv4.tcp_max_tw_buckets is already set. Skipping addition."
else
  echo "net.ipv4.tcp_max_tw_buckets = 10485760" >> /etc/sysctl.conf  # Increased to handle 10M TCP connections
  echo "[Success] net.ipv4.tcp_max_tw_buckets added to /etc/sysctl.conf."
fi

# Check and add somaxconn setting
if grep -q "^net.core.somaxconn" /etc/sysctl.conf; then
  echo "[Info] net.core.somaxconn is already set. Skipping addition."
else
  echo "net.core.somaxconn = 655350" >> /etc/sysctl.conf             # Increased to handle 650K socket backlogs
  echo "[Success] net.core.somaxconn added to /etc/sysctl.conf."
fi

# Check and add fs.file-max setting
if grep -q "^fs.file-max" /etc/sysctl.conf; then
  echo "[Info] fs.file-max is already set. Skipping addition."
else
  echo "fs.file-max = 20971520" >> /etc/sysctl.conf                 # Increased to handle 20M open files
  echo "[Success] fs.file-max added to /etc/sysctl.conf."
fi

echo "====== Step 3: Applying Sysctl Changes ======"
echo "Reloading system configuration to apply changes..."
sysctl net.ipv4.tcp_max_tw_buckets=10485760 > /dev/null
sysctl net.core.somaxconn=655350 > /dev/null
sysctl fs.file-max=20971520 > /dev/null
sysctl --system > /dev/null
sysctl -p > /dev/null
echo "[Success] Sysctl changes applied successfully."

echo "====== Step 4: Verifying Settings ======"
echo "Current sysctl settings:"
sysctl net.ipv4.tcp_max_tw_buckets
sysctl net.core.somaxconn
sysctl fs.file-max

echo "Setting ulimit values..."
ulimit -f unlimited
ulimit -t unlimited
ulimit -v unlimited
ulimit -n 992400
ulimit -m unlimited
ulimit -u unlimited

echo "Applying additional inotify sysctl settings..."
sysctl fs.inotify.max_user_instances=92800000
sysctl fs.inotify.max_user_watches=955360000

echo "[Success] Verification and additional settings completed."

# ##----------------------------------------------------------------------------------------------------------##
echo "====== Step 2: Updating Package List ======"
echo "Running 'apt-get update' to refresh package information..."
apt update -y
apt upgrade -y --allow-downgrades --allow-remove-essential --allow-change-held-packages -o Dpkg::Options::="--force-confnew"
echo "[Success] Package list updated."

echo "====== Step 3: Installing Required Packages ======"
echo "Installing 'ca-certificates', 'curl', 'gnupg', and 'lsb-release'..."
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release nfs-common jq gpg
echo "[Success] Required packages installed."

SERVICE_FILE="/lib/systemd/system/containerd.service"
echo "====== Step 4: Updating containerd.service ======"
# Check if LimitNOFILE=infinity already exists (ignoring leading whitespace)
if grep -q "^[[:space:]]*LimitNOFILE=infinity" "$SERVICE_FILE"; then
    echo "[Info] 'LimitNOFILE=infinity' already exists in $SERVICE_FILE. Skipping addition."
else
    echo "Adding 'LimitNOFILE=infinity' to $SERVICE_FILE..."
    # Check if LimitCORE=infinity exists (ignoring leading whitespace)
    if grep -q "^[[:space:]]*LimitCORE=infinity" "$SERVICE_FILE"; then
        sed -i '/^[[:space:]]*LimitCORE=infinity/a LimitNOFILE=infinity' "$SERVICE_FILE"
    else
        echo "LimitNOFILE=infinity" >> "$SERVICE_FILE"
    fi
    echo "[Success] 'LimitNOFILE=infinity' added to $SERVICE_FILE."
fi

echo "====== Step 5: Reloading systemd and Restarting containerd ======"
systemctl daemon-reload
systemctl restart containerd
echo "[Success] containerd configured and restarted."

##-------------------------------------------------------------------------------------------------------------------------------
#Memory Cache Clean every 3 Hours

# Create the script to clear the cache
echo "#!/bin/bash
sudo sync; echo 3 > /proc/sys/vm/drop_caches" > /usr/local/bin/clear_cache.sh

# Make the script executable
chmod +x /usr/local/bin/clear_cache.sh

# Add the cron job
(crontab -l 2>/dev/null; echo "0 */3 * * * /usr/local/bin/clear_cache.sh") | crontab -

echo "Bash script and cron job created successfully."

###-----------------------------------------------------------------------------------------------------------------------------
sudo tee /usr/local/bin/unused_images_log_cleanup.sh > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail

# Optional configuration variables:
# DRY_RUN: When set to 'true', commands will only be echoed, not executed.
# CLEAN_LOGS: When set to 'true', the script will truncate current logs and archive rotated logs.
DRY_RUN=${DRY_RUN:-false}      # Default is false (execute commands)
CLEAN_LOGS=${CLEAN_LOGS:-false}  # Default is false (skip log cleanup)

# Log file for script output
LOGFILE="/var/log/cleanup_script.log"
exec >> "$LOGFILE" 2>&1

echo "===== Cleanup Script Started at $(date) ====="
echo "DRY_RUN mode: $DRY_RUN"
echo "CLEAN_LOGS mode: $CLEAN_LOGS"

# Function to run commands (respects DRY_RUN mode)
run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    echo "DRY_RUN: $*"
  else
    echo "Running: $*"
    eval "$*"
  fi
}

###############################
# Container Cleanup
###############################
echo "---- Container Cleanup ----"
if command -v crictl >/dev/null; then
  echo "Pruning unused container images..."
  run_cmd "crictl rmi --prune || echo 'Warning: crictl image prune failed.'"
  
  # Only remove exited containers
  STOPPED_CONTAINERS=$(crictl ps --state=exited -q || true)
  if [ -n "$STOPPED_CONTAINERS" ]; then
    echo "Removing stopped containers..."
    run_cmd "crictl rm $STOPPED_CONTAINERS || echo 'Warning: failed to remove one or more stopped containers.'"
  else
    echo "No stopped containers found."
  fi
else
  echo "crictl not found; skipping container cleanup."
fi

echo "Skipping container runtime restart to avoid disruption in production."
# Uncomment the following line only if a restart is absolutely necessary:
# run_cmd "systemctl restart containerd"

###############################
# Log Management
###############################
echo "---- Log Management ----"
echo "Note: In production, it is recommended to use a log rotation system (e.g., logrotate) rather than deleting logs outright."

if [ "$CLEAN_LOGS" = true ]; then
  # Truncate current audit and auth logs if present.
  LOG_FILES=( "/var/log/audit/audit.log" "/var/log/auth.log" )
  for file in "${LOG_FILES[@]}"; do
    if [ -f "$file" ]; then
      echo "Truncating log file $file..."
      run_cmd "truncate -s 0 $file"
    else
      echo "Log file $file not found, skipping."
    fi
  done
  
  # Archive rotated logs
  echo "Archiving rotated logs for audit and auth..."
  BACKUP_DIR="/var/log/backup_logs"
  run_cmd "mkdir -p $BACKUP_DIR"
  ARCHIVE_NAME="$BACKUP_DIR/rotated_logs_$(date +%F_%H-%M-%S).tar.gz"
  run_cmd "tar -czf $ARCHIVE_NAME /var/log/auth.log.* /var/log/audit/audit.log.* || echo 'No rotated logs found to archive.'"
  run_cmd "rm -f /var/log/auth.log.* /var/log/audit/audit.log.*"
  echo "[Success] Rotated logs archived to $ARCHIVE_NAME."
  
  echo "Vacuuming journal logs older than 1 day and exceeding 100MB..."
  run_cmd "journalctl --vacuum-time=1d"
  run_cmd "journalctl --vacuum-size=100M"
  
  # Archive pod-specific logs
  if [ -d /var/log/pods ]; then
    echo "Archiving pod-specific logs..."
    PODS_ARCHIVE_NAME="$BACKUP_DIR/pod_logs_$(date +%F_%H-%M-%S).tar.gz"
    run_cmd "tar -czf $PODS_ARCHIVE_NAME /var/log/pods && rm -rf /var/log/pods/*"
    echo "[Success] Pod logs archived to $PODS_ARCHIVE_NAME."
  else
    echo "/var/log/pods directory not found, skipping pod logs cleanup."
  fi
else
  echo "CLEAN_LOGS is false; skipping log truncation and archiving. Use logrotate for managing logs in production."
fi

echo "===== Cleanup Script Completed at $(date) ====="
EOF

##---------------------------------------------------------------------------------------------------------------------------------
# Environment variables (edit as needed)
export k8sAllowMasterNodeSchedule=true                      # Allow master node scheduling (required for single-node setups with MetalLB)

# Kubernetes Repo Stable Version setup

# Create the keyrings directory if it doesn't exist.
if [ ! -d /etc/apt/keyrings ]; then
  mkdir -p /etc/apt/keyrings
fi

# Install Kubernetes apt key if not already installed.
if [ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
  echo "Installing Kubernetes apt key..."
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
else
  echo "Kubernetes apt key already exists, skipping key installation."
fi

# Add the Kubernetes apt repository if it isn't already configured.
if [ ! -f /etc/apt/sources.list.d/kubernetes.list ]; then
  echo "Adding Kubernetes apt repository..."
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
else
  echo "Kubernetes apt repository already configured, skipping repository addition."
fi

# Check and install Kubernetes components (kubelet, kubeadm, kubectl) if missing.
missing_packages=""
for pkg in kubelet kubeadm kubectl; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    missing_packages="$missing_packages $pkg"
  fi
done

if [ -n "$missing_packages" ]; then
  echo "Missing Kubernetes packages detected: $missing_packages. Installing..."
  apt-get update
  apt-get install -y $missing_packages
else
  echo "Kubernetes components are already installed, skipping package installation."
fi

# Enable and start the kubelet service.
echo "Enabling and starting kubelet..."
systemctl enable --now kubelet

##Adding Ip address into /etc/default/kubelet 
local_ip="$(ip --json addr show $interface | jq -r '.[0].addr_info[] | select(.family == "inet") | .local')"
sudo tee /etc/default/kubelet > /dev/null << EOF
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
EOF

cat /etc/default/kubelet

# Init Kubernetes
echo -e "\033[32mInitializing Kubernetes\033[0m"

kubeadm init --pod-network-cidr=$pod_network_cidr

# Setup kube config files
echo -e "\033[32mSetting up kubectl config files\033[0m"
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Export KUBECONFIG environment variable
export KUBECONFIG=/etc/kubernetes/admin.conf

# Print success message and tips

export JOIN_COMMAND_OUTPUT=$(kubeadm token create --print-join-command)
read -ra JOIN_WORDS <<< "$JOIN_COMMAND_OUTPUT"

export JOIN_IP=$(echo ${JOIN_WORDS[2]} | cut -d: -f1)
export JOIN_PORT=$(echo ${JOIN_WORDS[2]} | cut -d: -f2)
export JOIN_TOKEN="${JOIN_WORDS[4]}"
export JOIN_CERT_HASH="${JOIN_WORDS[6]}"

echo $JOIN_COMMAND_OUTPUT

# Confirmation message
echo -e "\033[32mKubernetes control-plane has been initialized and kubectl config setup completed.\033[0m"

##---------------------------------------------------------------------------------------------------------------------------------
#Install Calico 

# Step 1: Download Calico manifest
echo "Downloading Calico manifest..."
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.26.3/manifests/calico.yaml

# Step 2: Modify the CALICO_IPV4POOL_CIDR value
echo "Modifying CIDR in calico.yaml..."
sed -i '/# - name: CALICO_IPV4POOL_CIDR/,+1 s/# //' calico.yaml
sed -i 's|value: "192.168.0.0/16"|value: "172.168.0.0/12"|' calico.yaml

# Step 3: Apply the configuration to Kubernetes
echo "Applying calico.yaml to Kubernetes..."
kubectl apply -f calico.yaml
