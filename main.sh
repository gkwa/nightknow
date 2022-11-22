#!/bin/bash

# https://www.padok.fr/en/blog/kubernetes-infrastructure-crossplane

set -e
set -x

cat >provider.yaml <<EOF
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws
spec:
  package: crossplane/provider-aws:v0.32.0
EOF

cat >providerconfig.yaml <<EOF
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

cat >subnet.yaml <<EOF
apiVersion: ec2.aws.crossplane.io/v1beta1
kind: Subnet
metadata:
  name: sandbox-subnet
  labels:
    name: sandbox-subnet
spec:
  forProvider:
    region: eu-west-3
    availabilityZone: eu-west-3a
    vpcIdSelector:
      matchLabels:
        name: sandbox-vpc
    cidrBlock: 10.10.0.0/24
  providerConfigRef:
    name: aws-provider-config
EOF

cat >vpc.yaml <<EOF
apiVersion: ec2.aws.crossplane.io/v1beta1
kind: VPC
metadata:
  name: sandbox-vpc
  labels:
    name: sandbox-vpc
spec:
  forProvider:
    region: eu-west-3
    cidrBlock: 10.10.0.0/16
    enableDnsSupport: true
    enableDnsHostNames: true
  providerConfigRef:
    name: aws-provider-config
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
rm -f /tmp/creds.conf

kubectl apply --wait -f provider.yaml
kubectl wait Provider provider-aws --for condition=healthy --timeout=2m
kubectl --namespace crossplane-system describe provider
kubectl apply -f providerconfig.yaml -f vpc.yaml -f subnet.yaml

kubectl --namespace crossplane-system describe vpc
kubectl --namespace crossplane-system describe subnet

echo 'https://eu-west-3.console.aws.amazon.com/vpc/home?region=eu-west-3#vpcs:'
