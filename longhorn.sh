#!/bin/bash

# export NODE_LABEL_NAME=worker3
# export REPLICATION=33
# export DATA_PATH=/data
# export NEW_REPLICATION=77


if [ "$(whoami)" != "root" ]; then
  sudo su -c "bash $0"
  exit
fi

set -e  # Exit immediately if a command exits with a non-zero status

# Correctly set NODE_NAMES by replacing commas with spaces
# export NODE_NAMES=$(echo $NODE_LABEL_NAME | tr ',' ' ')

export NODE_NAMES=ori

# Check if the NODE_NAMES environment variable is set
if [ -z "$NODE_NAMES" ]; then
  echo "Please set the NODE_NAMES environment variable (e.g., export NODE_NAMES='node-1,node-2,node-3')"
  exit 1
fi

# Loop through each node name in the NODE_NAMES environment variable
for NODE_NAME in $NODE_NAMES; do
  echo "Labeling node: $NODE_NAME"
  kubectl label nodes "$NODE_NAME" node.longhorn.io/create-default-disk=true
done

# Optional: confirm the labels have been applied
echo "Labels applied to all provided nodes."

sed -i.bak "s|default-data-path:.*|default-data-path: $DATA_PATH|g" longhorn-1-7-3.yaml

sed -i 's|numberOfReplicas: "$REPLICA"|numberOfReplicas: "'"1"'"|' longhorn-1-7-3.yaml
#sed -i 's|numberOfReplicas: "$REPLICATION"|numberOfReplicas: "'"$NEW_REPLICATION"'"|' /home/ciuser/longhorn-1-7-3.yaml

# Apply the updated YAML file with 
kubectl apply -f longhorn-1-7-3.yaml

# #!/bin/bash

# if [ "$(whoami)" != "root" ]; then
#   sudo su -c "bash $0"
#   exit
# fi

# set -e  # Exit immediately if a command exits with a non-zero status

# # Apply Longhorn deployment
# echo "Applying Longhorn deployment..."
# kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.2/deploy/longhorn.yaml

# # Create Longhorn StorageClass with retain policy
# echo "Creating Longhorn StorageClass..."
# cat <<EOF > longhorn-storage-retain.yaml
# apiVersion: storage.k8s.io/v1
# kind: StorageClass
# metadata:
#   name: longhorn-storage-retain
#   annotations:
#     storageclass.kubernetes.io/is-default-class: "true"
# provisioner: driver.longhorn.io
# parameters:
#   fromBackup: ""
#   fsType: ext4
#   numberOfReplicas: "$REPLICATION"
#   staleReplicaTimeout: "30"
# reclaimPolicy: Delete
# volumeBindingMode: Immediate
# allowVolumeExpansion: true
# EOF

# # Sleep for 300 seconds to allow deployment to stabilize
# echo "Waiting for 300 seconds before proceeding..."
# sleep 300

# # Apply the new StorageClass
# echo "Applying Longhorn StorageClass..."
# kubectl apply -f longhorn-storage-retain.yaml

# # Remove default storage class annotation from "longhorn" StorageClass
# echo "Patching Longhorn StorageClass to remove default annotation..."
# kubectl patch storageclass longhorn -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": null}}}'

# echo "Longhorn setup completed successfully."