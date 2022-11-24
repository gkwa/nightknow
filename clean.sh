#!/usr/bin/env bash

set -e
set -x

kubectl delete --wait -f subnet.yaml -f vpc.yaml
kubectl delete --wait -f role.yaml -f policy.yaml -f rolepolicyattachment.yaml
helm uninstall --wait crossplane -n crossplane-system
kubectl delete --wait namespace crossplane-system

# Helm does not delete CRD objects. You can delete the ones Crossplane
# created with the following commands:
kubectl patch lock lock -p '{"metadata":{"finalizers": []}}' --type=merge kubectl get crd -o name | grep crossplane.io | xargs kubectl delete

kind delete cluster --name nightknow
