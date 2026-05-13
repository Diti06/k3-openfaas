#!/bin/bash
# =============================================================
# K3s + OpenFaaS Multi-Node — MASTER NODE SETUP
#
# Run this FIRST on the master node.
# After this completes, run collect_token.sh to get the
# join token, then run setup_worker.sh on each worker.
#
# USAGE:
#   1. Set DHUB_USER below
#   2. Run: docker login
#   3. Run: bash setup_master.sh
# =============================================================

set -euo pipefail

# ══════════════════════════════════════════════════════════════
#  CONFIG — Edit before running
# ══════════════════════════════════════════════════════════════
DHUB_USER="diti06"
K3S_VERSION="v1.27.2+k3s1"
HELM_VERSION="3.11.0"
OPENFAAS_CHART="14.2.136"
GATEWAY_PORT=31112
GATEWAY="http://127.0.0.1:${GATEWAY_PORT}"
FN_DIR="${HOME}/factorial-fn"
# ══════════════════════════════════════════════════════════════

echo "======================================================"
echo " K3s + OpenFaaS Multi-Node — MASTER SETUP"
echo " K3s: ${K3S_VERSION} | Chart: ${OPENFAAS_CHART}"
echo "======================================================"

# ┌────────────────────────────────────────────────────────────┐
# │  LAYER 1 — SYSTEM SETUP                                   │
# └────────────────────────────────────────────────────────────┘
echo ""
echo "══════════════════════════════════════"
echo " LAYER 1: System Setup"
echo "══════════════════════════════════════"

echo "[1a] Installing Docker..."
sudo apt-get update -qq
sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
     -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -qq
sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io
sudo usermod -aG docker "$USER" || true
sudo service docker start || true
sleep 3
echo "    Docker: $(docker --version)"

echo "[1b] Installing faas-cli..."
curl -sSL https://cli.openfaas.com | sudo sh
echo "    faas-cli: $(faas-cli version --short-version 2>/dev/null || true)"

# ┌────────────────────────────────────────────────────────────┐
# │  LAYER 2 — K3s MASTER INIT                                │
# │                                                           │
# │  Key difference vs single-node:                           │
# │  - No extra flags needed; K3s server mode IS the master.  │
# │  - Token is auto-generated at /var/lib/rancher/k3s/       │
# │    server/node-token — workers use this to join.          │
# │  - --cluster-init enables etcd (HA-ready), optional but   │
# │    good habit for multi-node CloudLab experiments.        │
# └────────────────────────────────────────────────────────────┘
echo ""
echo "══════════════════════════════════════"
echo " LAYER 2: K3s Master Init"
echo "══════════════════════════════════════"

echo "[2a] Cleaning previous K3s installation (if any)..."
sudo systemctl stop k3s 2>/dev/null || true
sudo /usr/local/bin/k3s-killall.sh 2>/dev/null || true
/usr/local/bin/k3s-uninstall.sh 2>/dev/null || true

# Kill any zombie k3s processes holding ports (WSL2 issue)
sudo pkill -9 -f k3s 2>/dev/null || true
sudo pkill -9 -f k3s-server 2>/dev/null || true
sudo pkill -9 -f k3s-agent 2>/dev/null || true
sleep 2
# Verify critical ports are free before proceeding
for port in 6443 6444 2379 2380 10250; do
    if sudo lsof -i :${port} &>/dev/null; then
        echo "    WARNING: Port ${port} still in use — force killing..."
        sudo fuser -k ${port}/tcp 2>/dev/null || true
    fi
done
sleep 2

sudo umount $(grep '/var/lib/kubelet' /proc/mounts | awk '{print $2}' | sort -r) 2>/dev/null || true
sudo rm -rf /etc/rancher /var/lib/rancher
sudo rm -rf /var/lib/kubelet 2>/dev/null || true
echo "    Cleanup done."

echo "[2b] Installing K3s ${K3S_VERSION} in SERVER (master) mode..."
curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION="${K3S_VERSION}" \
    sh -s - server \
        --write-kubeconfig-mode 644 \
        --disable traefik \
        --cluster-init

# ── Export KUBECONFIG ──────────────────────────────────────

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
grep -qxF 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' ~/.bashrc \
    || echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc

echo "[2c] Waiting for master node to be Ready..."
READY=false
for i in $(seq 1 24); do
    STATUS=$(kubectl get nodes 2>/dev/null \
        | awk 'NR>1 {print $2}' | head -1)
    if [[ "$STATUS" == "Ready" ]]; then
        READY=true
        break
    fi
    echo "    ...attempt $i/24 (status: ${STATUS:-unknown})"
    sleep 5
done
if [[ "$READY" != "true" ]]; then
    echo "ERROR: Node never became Ready. Check: journalctl -u k3s -n 50"
    exit 1
fi
kubectl get nodes -o wide

# Save master IP for workers to use
MASTER_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "${MASTER_IP}" > ~/master_ip.txt
echo "    Master IP: ${MASTER_IP} (saved to ~/master_ip.txt)"

# ┌────────────────────────────────────────────────────────────┐
# │  LAYER 3 — OpenFaaS SETUP (identical to single-node)       │
# └────────────────────────────────────────────────────────────┘
echo ""
echo "══════════════════════════════════════"
echo " LAYER 3: OpenFaaS Setup"
echo "══════════════════════════════════════"

echo "[3a] Installing Helm ${HELM_VERSION}..."
curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
    -o /tmp/helm.tar.gz
tar -xzf /tmp/helm.tar.gz -C /tmp
sudo mv /tmp/linux-amd64/helm /usr/local/bin/helm
echo "    Helm: $(helm version --short)"

echo "[3b] Cleaning previous OpenFaaS installation (if any)..."
helm uninstall openfaas -n openfaas 2>/dev/null || true
kubectl delete namespace openfaas    2>/dev/null || true
kubectl delete namespace openfaas-fn 2>/dev/null || true

for ns in openfaas openfaas-fn; do
    kubectl get namespace "$ns" -o json 2>/dev/null \
        | python3 -c "
import json,sys
data=sys.stdin.read()
if not data.strip(): exit(0)
ns=json.loads(data)
ns['spec']['finalizers']=[]
print(json.dumps(ns))
" | kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
done

until ! kubectl get namespace openfaas    &>/dev/null; do sleep 3; done
until ! kubectl get namespace openfaas-fn &>/dev/null; do sleep 3; done
echo "    Namespaces cleared."

echo "[3c] Creating namespaces and credentials..."
kubectl create namespace openfaas
kubectl create namespace openfaas-fn

OPENFAAS_PASSWORD=$(head -c 12 /dev/urandom | sha256sum | cut -d' ' -f1)
printf "admin\n%s\n" "$OPENFAAS_PASSWORD" > ~/openfaas-creds.txt
chmod 600 ~/openfaas-creds.txt
echo "    Password saved to ~/openfaas-creds.txt"

kubectl -n openfaas create secret generic basic-auth \
    --from-literal=basic-auth-user=admin \
    --from-literal=basic-auth-password="${OPENFAAS_PASSWORD}"

echo "[3d] Installing OpenFaaS chart ${OPENFAAS_CHART}..."
helm repo add openfaas https://openfaas.github.io/faas-netes/ 2>/dev/null || true
helm repo update

helm upgrade --install openfaas openfaas/openfaas \
    --namespace openfaas \
    --version "${OPENFAAS_CHART}" \
    --set functionNamespace=openfaas-fn \
    --set generateBasicAuth=false \
    --set basic_auth=true \
    --set serviceType=NodePort \
    --set gateway.nodePort="${GATEWAY_PORT}" \
    --set operator.create=false \
    --set clusterRole=true \
    --set faasnetes.imagePullPolicy=IfNotPresent \
    --wait --timeout 5m

echo "[3e] Waiting for gateway..."
kubectl -n openfaas rollout status deploy/gateway --timeout=300s
echo "    Gateway is up!"

echo "[3e] Waiting for gateway HTTP endpoint to be ready..."
for i in $(seq 1 20); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "admin:${OPENFAAS_PASSWORD}" \
        "${GATEWAY}/system/functions" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
        echo "    Gateway HTTP: OK (${HTTP_CODE})"
        break
    fi
    echo "    ...attempt $i/20 (HTTP ${HTTP_CODE})"
    sleep 5
done

echo "${OPENFAAS_PASSWORD}" | faas-cli login \
    --username admin \
    --password-stdin \
    --gateway "${GATEWAY}"

echo "[3f] Verifying gateway responds..."
curl -sf -u "admin:${OPENFAAS_PASSWORD}" \
    "${GATEWAY}/system/info" | python3 -m json.tool || true

# ┌────────────────────────────────────────────────────────────┐
# │  LAYER 4 — FUNCTION DEPLOYMENT                             │
# └────────────────────────────────────────────────────────────┘
echo ""
echo "══════════════════════════════════════"
echo " LAYER 4: Function Deployment"
echo "══════════════════════════════════════"

echo "[4a] Setting up function scaffold..."
mkdir -p "${FN_DIR}"
cd "${FN_DIR}"
faas-cli template store pull python3-http 2>/dev/null || true
mkdir -p "${FN_DIR}/factorial"
touch "${FN_DIR}/factorial/requirements.txt"

echo "[4b] Writing handler (factorial(500))..."
cat > "${FN_DIR}/factorial/handler.py" <<'EOF'
import math

def handle(event, context):
    n = int(event.body.decode('utf-8').strip()) if event.body else 500
    result = math.factorial(n)
    return {
        "statusCode": 200,
        "body": f"factorial({n}) has {len(str(result))} digits\n"
    }
EOF

echo "[4c] Writing stack.yaml..."
cat > "${FN_DIR}/stack.yaml" <<EOF
version: 1.0
provider:
  name: openfaas
  gateway: ${GATEWAY}

functions:
  factorial:
    lang: python3-http
    handler: ./factorial
    image: ${DHUB_USER}/factorial:latest
EOF

echo "[4d] Building Docker image..."
cd "${FN_DIR}"
faas-cli build -f stack.yaml

echo "[4e] Pushing to Docker Hub as ${DHUB_USER}/factorial:latest..."
docker tag factorial:latest "${DHUB_USER}/factorial:latest"
docker push "${DHUB_USER}/factorial:latest"

echo "[4f] Deploying function..."
faas-cli deploy -f "${FN_DIR}/stack.yaml" --gateway "${GATEWAY}"

echo "[4g] Waiting 25s for function pod..."
for i in $(seq 1 20); do
    PHASE=$(kubectl get pods -n openfaas-fn \
        -l "faas_function=factorial" \
        -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Pending")
    if [[ "$PHASE" == "Running" ]]; then
        echo "    Pod is Running!"
        break
    fi
    echo "    ...attempt $i/20 (phase: ${PHASE})"
    sleep 5
done
kubectl get pods -n openfaas-fn

echo "[4h] Invoking factorial(500)..."
RESULT=$(echo "500" | faas-cli invoke factorial --gateway "${GATEWAY}")
echo "    Result: ${RESULT}"

# ══════════════════════════════════════════════════════════════
echo ""
echo "======================================================"
echo " MASTER SETUP COMPLETE"
echo "======================================================"
echo " Master IP:   ${MASTER_IP}"
echo " Gateway:     ${GATEWAY}"
echo " Credentials: admin / ${OPENFAAS_PASSWORD}"
echo "              (saved at ~/openfaas-creds.txt)"
echo ""
echo " NEXT STEPS:"
echo "   1. Run: bash collect_token.sh"
echo "      → Copy the K3S_URL and K3S_TOKEN output"
echo "   2. On each worker: bash setup_worker.sh <MASTER_IP> <TOKEN>"
echo "   3. Back on master: bash verify_cluster.sh"
echo "======================================================"
