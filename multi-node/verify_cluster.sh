#!/bin/bash
# =============================================================
# K3s Multi-Node — CLUSTER VERIFICATION
#
# Run on the MASTER node after all workers have joined.
# Checks: node readiness, pod scheduling across workers,
# OpenFaaS health, and factorial function invocation.
#
# USAGE:
#   bash verify_cluster.sh
# =============================================================

set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

GATEWAY_PORT=31112
GATEWAY="http://127.0.0.1:${GATEWAY_PORT}"
OPENFAAS_PASSWORD=$(awk -F'\n' 'NR==2{print $1}' ~/openfaas-creds.txt)

echo "======================================================"
echo " K3s Multi-Node — CLUSTER VERIFICATION"
echo "======================================================"

# ┌────────────────────────────────────────────────────────────┐
# │  CHECK 1 — All nodes Ready                                 │
# └────────────────────────────────────────────────────────────┘
echo ""
echo "── CHECK 1: Node Status ──"
kubectl get nodes -o wide

NODE_COUNT=$(kubectl get nodes --no-headers | grep -c " Ready")
echo "    Ready nodes: ${NODE_COUNT}"

if [[ "${NODE_COUNT}" -lt 2 ]]; then
    echo "    WARNING: Fewer than 2 nodes ready."
    echo "    Run 'kubectl get nodes' on master to diagnose."
fi

# ┌────────────────────────────────────────────────────────────┐
# │  CHECK 2 — System pods healthy across all nodes            │
# └────────────────────────────────────────────────────────────┘
echo ""
echo "── CHECK 2: System Pods ──"
kubectl get pods -A -o wide | grep -v "Running\|Completed" || echo "    All pods Running/Completed."
kubectl get pods -A -o wide

# ┌────────────────────────────────────────────────────────────┐
# │  CHECK 3 — Cross-node pod scheduling smoke test            │
# │                                                            │
# │  Deploy a DaemonSet so one pod lands on EVERY node.        │
# │  This is stronger than a single Deployment for verifying   │
# │  that workers are accepting workloads.                     │
# └────────────────────────────────────────────────────────────┘
echo ""
echo "── CHECK 3: Cross-Node Scheduling (DaemonSet smoke test) ──"
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: smoke-ds
  namespace: default
spec:
  selector:
    matchLabels:
      app: smoke-ds
  template:
    metadata:
      labels:
        app: smoke-ds
    spec:
      tolerations:
        - key: "node-role.kubernetes.io/master"
          effect: NoSchedule
          operator: Exists
      containers:
        - name: smoke
          image: nginx:alpine
          resources:
            requests:
              cpu: "10m"
              memory: "16Mi"
EOF

echo "    Waiting 30s for DaemonSet pods to schedule..."
sleep 30
kubectl get pods -l app=smoke-ds -o wide

DS_READY=$(kubectl get daemonset smoke-ds -o jsonpath='{.status.numberReady}')
DS_DESIRED=$(kubectl get daemonset smoke-ds -o jsonpath='{.status.desiredNumberScheduled}')
echo "    DaemonSet: ${DS_READY}/${DS_DESIRED} pods ready"

kubectl delete daemonset smoke-ds 2>/dev/null || true

# ┌────────────────────────────────────────────────────────────┐
# │  CHECK 4 — OpenFaaS gateway health                         │
# └────────────────────────────────────────────────────────────┘
echo ""
echo "── CHECK 4: OpenFaaS Gateway ──"
kubectl -n openfaas rollout status deploy/gateway --timeout=60s
curl -sf -u "admin:${OPENFAAS_PASSWORD}" \
    "${GATEWAY}/system/info" | python3 -m json.tool || true

# ┌────────────────────────────────────────────────────────────┐
# │  CHECK 5 — Factorial function invocation                   │
# └────────────────────────────────────────────────────────────┘
echo ""
echo "── CHECK 5: Factorial Function ──"
kubectl get pods -n openfaas-fn -o wide

echo "    Invoking factorial(500)..."
RESULT=$(echo "500" | faas-cli invoke factorial --gateway "${GATEWAY}")
echo "    Result: ${RESULT}"

echo "    Invoking factorial(1000) to stress-test across nodes..."
RESULT2=$(echo "1000" | faas-cli invoke factorial --gateway "${GATEWAY}")
echo "    Result: ${RESULT2}"

# ┌────────────────────────────────────────────────────────────┐
# │  CHECK 6 — Show pod placement (which worker ran it?)       │
# └────────────────────────────────────────────────────────────┘
echo ""
echo "── CHECK 6: Function Pod Placement ──"
kubectl get pods -n openfaas-fn -o wide

echo ""
echo "======================================================"
echo " VERIFICATION COMPLETE"
echo "======================================================"
echo " Gateway:  ${GATEWAY}"
echo " UI:       ${GATEWAY}/ui/"
echo " Creds:    admin / (see ~/openfaas-creds.txt)"
echo ""
echo " NEXT: Create your CloudLab profile."
echo "   - Attach setup_master.sh to master node"
echo "   - Attach setup_worker.sh to worker nodes"
echo "   - collect_token.sh + verify_cluster.sh run manually"
echo "======================================================"
