#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="monitoring"

echo "Stopping any active port-forwards..."
# Find and kill port-forward processes for Prometheus and Grafana
for port in 9090 13000; do
  PIDS=$(lsof -ti tcp:$port || true)
  if [ -n "$PIDS" ]; then
    echo "Killing processes on port $port: $PIDS"
    kill -9 $PIDS
  fi
done

echo "Uninstalling Prometheus release..."
helm uninstall prometheus -n $NAMESPACE || true

echo "Deleting namespace $NAMESPACE..."
kubectl delete namespace $NAMESPACE || true

echo "Cleanup complete!"
