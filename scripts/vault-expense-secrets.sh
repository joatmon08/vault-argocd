#!/bin/bash

export VAULT_TOKEN=$(cat unseal.json | jq -r '.root_token')

MYSQL_DB_PASSWORD=$(vault kv get -format=table -field=db_login_password expense/static/mysql)

set -o verbose

#### ENABLE DATABASE SECRETS ENGINE ####
vault secrets enable -path=expense/database/mysql database

#### SET UP CONNECTION STRING  ####
vault write expense/database/mysql/config/mysql \
    plugin_name=mysql-database-plugin \
    disable_escaping=true \
    connection_url="{{username}}:{{password}}@tcp(expense-db-mysql.expenses:3306)/" \
    allowed_roles="expense" \
    username="root" \
    password="${MYSQL_DB_PASSWORD}"

#### CONFIGURE VAULT TO CREATE USER IN DATABASE ####
vault write expense/database/mysql/roles/expense \
    db_name=mysql \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT ALL PRIVILEGES ON DemoExpenses.expense_item TO '{{name}}'@'%';" \
    default_ttl="5m" \
    max_ttl="24h"

#### CONFIGURE VAULT TO CREATE USER IN DATABASE ####
vault policy write expense expense/vault-policy.hcl
vault write auth/kubernetes/role/expense \
    bound_service_account_names=expense \
    bound_service_account_namespaces=expenses \
    policies=expense \
    ttl=10m