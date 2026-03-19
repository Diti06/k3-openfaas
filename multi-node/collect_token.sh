#!/bin/bash
# =============================================================
# K3s Multi-Node — TOKEN COLLECTOR
#
# Run on the MASTER node after setup_master.sh completes.
# Prints the exact export commands needed by setup_worker.sh.
#
# USAGE:
#   bash collect_token.sh
# =============================================================

set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# ── Retrieve master IP (prefer external, fall back to internal) ──
MASTER_IP=$(kubectl get nodes \
    -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' \
    2>/dev/null || true)

if [[ -z "${MASTER_IP}" ]]; then
    MASTER_IP=$(kubectl get nodes \
        -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
fi

# ── Read the K3s node token ──────────────────────────────────
# This token is generated automatically during K3s server init.
# Workers present it to authenticate the join request.
K3S_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)

echo ""
echo "======================================================"
echo " K3s Join Credentials — copy these to each worker"
echo "======================================================"
echo ""
echo "  Master IP : ${MASTER_IP}"
echo "  Token     : ${K3S_TOKEN}"
echo ""
echo "  Run on each worker node:"
echo "    bash setup_worker.sh ${MASTER_IP} ${K3S_TOKEN}"
echo ""
echo "======================================================"

# Also save to file for convenience
cat > ~/k3s_join_info.txt <<EOF
MASTER_IP=${MASTER_IP}
K3S_TOKEN=${K3S_TOKEN}
EOF
chmod 600 ~/k3s_join_info.txt
echo "  (Also saved to ~/k3s_join_info.txt)"
