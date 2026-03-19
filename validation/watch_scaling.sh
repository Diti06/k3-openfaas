#!/bin/bash
echo "Watching replica count every 3 seconds. Press Ctrl+C to stop."
while true; do
  REPLICAS=$(kubectl get deployment factorial -n openfaas-fn \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  echo "$(date +%H:%M:%S) — factorial replicas: ${REPLICAS:-0}"
  sleep 3
done
