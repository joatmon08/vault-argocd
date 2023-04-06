export VAULT_TOKEN=$(cat unseal.json | jq -r '.root_token')
export VAULT_ADDR=http://vault-vault.apps-crc.testing