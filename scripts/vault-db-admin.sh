#!/bin/bash

export VAULT_FORMAT=json
export VAULT_TOKEN=$(cat unseal.json | jq -r '.root_token')

export DATABASE_PASSWORD=$(openssl rand -hex 16)

set -o verbose

#### SET UP STATIC SECRETS PATH ####
vault secrets enable -version=2 -path=expense/static kv

#### PUT DATABASE ADMIN PASSWORD IN VAULT ####
vault kv put expense/static/mysql db_login_password=${DATABASE_PASSWORD} | jq .

#### DEBUG: GET DATABASE PASSWORD FROM VAULT ####
vault kv get expense/static/mysql | jq '.data.data.db_login_password = "REDACTED"'

#### CREATE POLICY FOR KUBERNETES CLUSTER TO READ ADMIN PASSWORD ####
vault policy write expense-db-mysql database/vault-policy.hcl
vault write auth/kubernetes/role/expense-db-mysql \
    bound_service_account_names=expense-db-mysql \
    bound_service_account_namespaces=expenses \
    policies=expense-db-mysql \
    ttl=1h