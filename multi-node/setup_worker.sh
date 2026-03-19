#!/bin/bash
# =============================================================
# K3s Multi-Node — WORKER NODE SETUP
#
# Run on EACH worker node. Takes master IP and join token
# as arguments — get these by running collect_token.sh on master.
#
# USAGE:
#   bash setup_worker.sh <MASTER_IP> <K3S_TOKEN>
#
# Example:
#   bash setup_worker.sh 192.168.1.10 K10abc123::server:xyz456
# =============================================================

set -euo pipefail

# ── Argument validation ──────────────────────────────────────
if [[ $# -lt 2 ]]; then
    echo "ERROR: Missing arguments."
    echo "Usage: bash setup_worker.sh <MASTER_IP> <K3S_TOKEN>"
    exit 1
fi

MASTER_IP="$1"
K3S_TOKEN="$2"
K3S_VERSION="v1.27.2+k3s1"   # Must match master version exactly
K3S_URL="https://${MASTER_IP}:6443"

echo "======================================================"
echo " K3s Multi-Node — WORKER SETUP"
echo " Joining master at: ${K3S_URL}"
echo "======================================================"

# ┌────────────────────────────────────────────────────────────┐
# │  LAYER 1 — SYSTEM SETUP                                   │
# │  Workers need Docker only if you plan to build images     │
# │  here. For pure workers, only containerd (bundled with    │
# │  K3s) is strictly required. We install Docker anyway      │
# │  for consistency and potential local debug builds.        │
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

# ┌────────────────────────────────────────────────────────────┐
# │  LAYER 2 — K3s AGENT JOIN                                 │
# │                                                            │
# │  Key difference vs master:                                │
# │  - Mode is "agent" not "server"                           │
# │  - K3S_URL points to master's API server (port 6443)      │
# │  - K3S_TOKEN authenticates this node with the master      │
# │  - Workers do NOT get KUBECONFIG — kubectl runs on master │
# └────────────────────────────────────────────────────────────┘
echo ""
echo "══════════════════════════════════════"
echo " LAYER 2: K3s Worker Join"
echo "══════════════════════════════════════"

echo "[2a] Cleaning previous K3s installation (if any)..."
sudo systemctl stop k3s-agent 2>/dev/null || true
sudo /usr/local/bin/k3s-killall.sh 2>/dev/null || true
/usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || true

#Same Zombie Port Kill (WSL2 consistency) as in setup_master.sh
sudo pkill -9 -f k3s 2>/dev/null || true
sudo pkill -9 -f k3s-agent 2>/dev/null || true
sleep 2
for port in 6443 10250 10255; do
    if sudo lsof -i :${port} &>/dev/null; then
        echo "    WARNING: Port ${port} in use — force killing..."
        sudo fuser -k ${port}/tcp 2>/dev/null || true
    fi
done
sleep 2
sudo umount $(grep '/var/lib/kubelet' /proc/mounts | awk '{print $2}' | sort -r) 2>/dev/null || true
sudo rm -rf /etc/rancher /var/lib/rancher
sudo rm -rf /var/lib/kubelet 2>/dev/null || true
echo "    Cleanup done."

echo "[2b] Joining cluster as AGENT (worker)..."
echo "    Master URL : ${K3S_URL}"
echo "    Token      : ${K3S_TOKEN:0:20}... (truncated for display)"

curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION="${K3S_VERSION}" \
    K3S_URL="${K3S_URL}" \
    K3S_TOKEN="${K3S_TOKEN}" \
    sh -s - agent

# ── Wait for K3s agent service to be active ─────────────────
echo "[2c] Verifying K3s agent service is active..."
ACTIVE=false
for i in $(seq 1 18); do
    if sudo systemctl is-active k3s-agent &>/dev/null; then
        ACTIVE=true
        echo "    k3s-agent is active!"
        break
    fi
    echo "    ...attempt $i/18"
    sleep 5
done
if [[ "$ACTIVE" != "true" ]]; then
    echo "ERROR: k3s-agent failed to start."
    echo "       Check: sudo journalctl -u k3s-agent -n 50"
    exit 1
fi
sudo systemctl status k3s-agent --no-pager | head -20


echo ""
echo "======================================================"
echo " WORKER SETUP COMPLETE"
echo "======================================================"
echo " This node has joined the cluster."
echo " Verify from MASTER with:"
echo "   kubectl get nodes -o wide"
echo ""
echo " NEXT: After all workers are joined, run on master:"
echo "   bash verify_cluster.sh"
echo "======================================================"
