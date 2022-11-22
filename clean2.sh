kubectl delete -f subnet.yaml -f vpc.yaml
helm delete crossplane -n crossplane-system
kubectl delete namespace crossplane-system
