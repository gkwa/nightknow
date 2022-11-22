#!/usr/bin/env bash

set -e
set -x

kubectl delete --wait -f subnet.yaml -f vpc.yaml
helm uninstall --wait crossplane -n crossplane-system
kubectl delete --wait namespace crossplane-system
kind delete cluster --name nightknow
