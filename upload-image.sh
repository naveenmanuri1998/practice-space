#!/bin/bash

set -e

# -------- CONFIG --------
VM_IP="10.30.1.40"
VM_USER="ubuntu"
REMOTE_DIR="/home/ubuntu/images"
STORAGE_CLASS="paradigm-storage"
KUBECONFIG_PATH="/home/Harvester.yaml"

# -------- INPUTS --------
LOCAL_FILE=$1
IMAGE_NAME=$2
NAMESPACE=$3

if [[ -z "$LOCAL_FILE" || -z "$IMAGE_NAME" || -z "$NAMESPACE" ]]; then
  echo "Usage:"
  echo "./upload-image.sh <local-file> <image-name> <namespace>"
  exit 1
fi

FILE_NAME=$(basename "$LOCAL_FILE")

echo "-----------------------------------"
echo "Step 1: Copying image to internal VM..."
scp "$LOCAL_FILE" ${VM_USER}@${VM_IP}:${REMOTE_DIR}/

echo "-----------------------------------"
echo "Step 2: Starting Python HTTP server on VM..."
ssh ${VM_USER}@${VM_IP} "cd ${REMOTE_DIR} && nohup python3 -m http.server 9000 --bind 0.0.0.0 > /tmp/httpserver.log 2>&1 &" || true

sleep 5

echo "-----------------------------------"
echo "Step 3: Exporting Kubeconfig..."
export KUBECONFIG=${KUBECONFIG_PATH}

#echo "-----------------------------------"
#echo "Step 4: Deleting existing image if present..."
#kubectl delete virtualmachineimage ${IMAGE_NAME} -n ${NAMESPACE} --ignore-not-found || true

sleep 5

echo "-----------------------------------"
echo "Step 5: Creating YAML..."
cat <<EOF > ${IMAGE_NAME}.yaml
apiVersion: harvesterhci.io/v1beta1
kind: VirtualMachineImage
metadata:
  name: ${IMAGE_NAME}
  namespace: ${NAMESPACE}
spec:
  displayName: ${IMAGE_NAME}
  sourceType: download
  url: http://${VM_IP}:9000/${FILE_NAME}
  storageClassParameters:
    storageClassName: ${STORAGE_CLASS}
EOF

echo "-----------------------------------"
echo "Step 6: Applying YAML to Harvester..."
kubectl apply -f ${IMAGE_NAME}.yaml

echo "-----------------------------------"
echo "Step 7: Watching Import Status..."
kubectl get virtualmachineimage -n ${NAMESPACE} -w

echo "-----------------------------------"
echo "DONE! Image uploaded successfully."
