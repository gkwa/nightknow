#!/bin/bash

# https://www.padok.fr/en/blog/kubernetes-infrastructure-crossplane

set -e
set -x

#cat >secret.yaml <<EOF
#apiVersion: v1
#kind: Secret
#metadata:
#  name: crossplane-aws-credentials
#  namespace: crossplane-system
#type: Opaque
#data:
#  credentials: <crossplane_user_credentials_base64_encoded>
#EOF

cat >provider.yaml <<'EOF'
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws
spec:
  package: crossplane/provider-aws:v0.32.0
EOF

cat >providerconfig.yaml <<'EOF'
apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: aws-provider-config
spec:
  credentials:
    source: InjectedIdentity
EOF

cat >providerconfig.yaml <<'EOF'
apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: aws-provider-config
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: crossplane-system
      name: crossplane-aws-credentials
      key: credentials
EOF

kind create cluster --wait 2m

kubectl create namespace crossplane-system
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update crossplane-stable
helm install --wait crossplane --namespace crossplane-system crossplane-stable/crossplane
helm list --namespace crossplane-system
kubectl get all --namespace crossplane-system
helm list --namespace crossplane-system
kubectl get all --namespace crossplane-system

AWS_PROFILE=default && echo -e "[default]\naws_access_key_id = $(aws configure get aws_access_key_id --profile $AWS_PROFILE)\naws_secret_access_key = $(aws configure get aws_secret_access_key --profile $AWS_PROFILE)" >/tmp/creds.conf
kubectl create secret generic crossplane-aws-credentials --namespace crossplane-system --from-file=credentials=/tmp/creds.conf
# rm -f /tmp/creds.conf

kubectl apply --wait -f provider.yaml
kubectl wait Provider provider-aws --for condition=healthy
kubectl get Provider
kubectl apply -f providerconfig.yaml
kubectl apply -f vpc.yaml

# kubectl get pod --namespace crossplane-system
# kubectl --namespace crossplane-system describe provider
kubectl --namespace crossplane-system describe vpc
