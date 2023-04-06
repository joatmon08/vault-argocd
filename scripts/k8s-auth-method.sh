#!/bin/bash

export VAULT_FORMAT=json
export VAULT_TOKEN=$(cat unseal.json | jq -r '.root_token')

set -o verbose

#### CREATE TOKEN FOR SERVICE ACCOUNT ####
kubectl apply -n vault -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vault-token
  annotations:
    kubernetes.io/service-account.name: vault
type: kubernetes.io/service-account-token
EOF

#### ENABLE KUBERNETES AUTH METHOD ####
vault auth enable kubernetes

#### GET SERVICE ACCOUNT JWTS and CLUSTER CERTIFICATES ####
KUBERNETES_SA_TOKEN_VALUE=$(kubectl get secrets -n vault vault-token -o jsonpath='{.data.token}' | base64 -d)
KUBERNETES_SA_CA_CERT=$(kubectl get secrets -n vault vault-token -o jsonpath="{.data['ca\.crt']}" | base64 -d)
KUBERNETES_PORT_443_TCP_ADDR=$(kubectl config view -o jsonpath='{.clusters[].cluster.server}')

#### CONFIGURE KUBERNETES AUTH METHOD ####
vault write auth/kubernetes/config issuer="" \
    token_reviewer_jwt="${KUBERNETES_SA_TOKEN_VALUE}" \
    kubernetes_host="${KUBERNETES_PORT_443_TCP_ADDR}" \
    kubernetes_ca_cert="${KUBERNETES_SA_CA_CERT}"