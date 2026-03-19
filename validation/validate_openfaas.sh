#!/bin/bash
echo "=== Checking K3s Node ==="
kubectl get nodes

echo "=== Checking OpenFaaS Pods ==="
kubectl get pods -n openfaas

echo "=== Checking OpenFaaS Functions ==="
kubectl get pods -n openfaas-fn

echo "=== Gateway Reachability ==="
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:8080/healthz
