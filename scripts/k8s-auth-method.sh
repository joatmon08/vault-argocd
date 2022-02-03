#!/bin/bash

vault auth enable kubernetes

KUBERNETES_SA_TOKEN_NAME=$(kubectl get serviceaccounts -n vault vault -o json | jq -r '.secrets[] | select(.name | test("-token-")).name')
KUBERNETES_SA_TOKEN_VALUE=$(kubectl get secrets -n vault ${KUBERNETES_SA_TOKEN_NAME} -o jsonpath='{.data.token}' | base64 -d)
KUBERNETES_SA_CA_CERT=$(kubectl get secrets -n vault ${KUBERNETES_SA_TOKEN_NAME} -o jsonpath="{.data['ca\.crt']}" | base64 -d)
KUBERNETES_PORT_443_TCP_ADDR=$(kubectl config view -o jsonpath='{.clusters[].cluster.server}')

vault write auth/kubernetes/config issuer="" \
    token_reviewer_jwt="${KUBERNETES_SA_TOKEN_VALUE}" \
    kubernetes_host="${KUBERNETES_PORT_443_TCP_ADDR}" \
    kubernetes_ca_cert="${KUBERNETES_SA_CA_CERT}"

## Set up vault-admin for Vault Config operator
vault policy write vault-admin scripts/vault-admin.hcl

vault write auth/kubernetes/role/vault-admin \
    bound_service_account_names=vault-admin \
    bound_service_account_namespaces=expenses \
    policies=vault-admin ttl=1h

kubectl apply --namespace expenses -f vault-config/vault-admin.yaml


## Set up argocd-plugin for ArgoCD Vault plugin
vault policy write argocd scripts/argocd.hcl

vault write auth/kubernetes/role/argocd \
    bound_service_account_names=argocd \
    bound_service_account_namespaces=openshift-gitops \
    policies=argocd ttl=1h

kubectl apply --namespace openshift-gitops -f vault-config/argocd.yaml