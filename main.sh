#!/usr/bin/env bash

# https://www.padok.fr/en/blog/kubernetes-infrastructure-crossplane
# https://grem1.in/post/crossplane/#provisioning-infrastructure
# https://pet2cattle.com/2022/02/crossplane-aws-provider
# https://www.innoq.com/en/articles/2022/07/infrastructure-self-service-with-crossplane/
# https://dev.to/timtsoitt/crossplane-is-better-than-terraform-in-k8s-world-g79

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
  name: provider-aws-config
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: crossplane-system
      name: crossplane-aws-credentials
      key: credentials
EOF

cat >role.yaml <<EOF
apiVersion: iam.aws.crossplane.io/v1beta1
kind: Role
metadata:
  name: crossplane-sample-role
  annotations: null
spec:
  deletionPolicy: Delete
  forProvider:
    description: A role created by Crossplane
    assumeRolePolicyDocument: |
      {
        "Version": "2012-10-17",
        "Statement": [
            {
              "Effect": "Allow",
              "Principal": {
                "Service": "ec2.amazonaws.com"
              },
              "Action": "sts:AssumeRole"
            }
        ]
      }
  providerConfigRef:
    name: provider-aws-config
EOF

cat >policy.yaml <<EOF
apiVersion: iam.aws.crossplane.io/v1beta1
kind: Policy
metadata:
  name: crossplane-sample-policy
spec:
  deletionPolicy: Delete
  forProvider:
    name: crossplane-sample-policy
    description: A policy created by Crossplane
    document: |
      {
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster"
            ],
            "Resource": "*"
          }
        ]
      }
  providerConfigRef:
    name: provider-aws-config
EOF

cat >rolepolicyattachment.yaml <<EOF
apiVersion: iam.aws.crossplane.io/v1beta1
kind: RolePolicyAttachment
metadata:
  name: crossplane-sample-role-policy-attachment
spec:
  deletionPolicy: Delete
  forProvider:
    roleNameRef:
      name: crossplane-sample-role
    policyArnRef:
      name: crossplane-sample-policy
  providerConfigRef:
    name: provider-aws-config
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
    name: provider-aws-config
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
    name: provider-aws-config
EOF

kind create cluster --wait 2m --name nightknow

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
kubectl wait --timeout=120s --for condition=healthy Provider provider-aws
kubectl --namespace crossplane-system describe provider
kubectl apply -f providerconfig.yaml -f vpc.yaml -f subnet.yaml
kubectl apply --wait --timeout=120s -f role.yaml
kubectl apply --wait --timeout=120s -f policy.yaml
kubectl apply --wait --timeout=120s -f rolepolicyattachment.yaml

kubectl wait --timeout=120s --for=condition=ready role.iam.aws.crossplane.io crossplane-sample-role
kubectl wait --timeout=120s --for=condition=ready policy.iam.aws.crossplane.io crossplane-sample-policy

kubectl get policy.iam.aws.crossplane.io
kubectl get rolepolicyattachment.iam.aws.crossplane.io

kubectl --namespace crossplane-system describe policy
#kubectl --namespace crossplane-system describe role
#kubectl --namespace crossplane-system describe RolePolicyAttachment

kubectl wait --timeout=120s --for=condition=ready --namespace crossplane-system vpc sandbox-vpc
kubectl wait --timeout=120s --for=condition=ready --namespace crossplane-system subnet sandbox-subnet

kubectl get --namespace crossplane-system providers.pkg.crossplane.io
kubectl get --namespace crossplane-system vpc
kubectl get --namespace crossplane-system subnet

kubectl --namespace crossplane-system describe vpc
kubectl --namespace crossplane-system describe subnet

kubectl get pkgrev,managed

echo 'https://eu-west-3.console.aws.amazon.com/vpc/home?region=eu-west-3#vpcs:'
