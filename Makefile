export VAULT_ADDR=http://vault-vault.apps-crc.testing

crc-start:
	crc setup
	crc start > crc-login
	oc login -u kubeadmin https://api.crc.testing:6443

helm-setup:
	helm repo add hashicorp https://helm.releases.hashicorp.com
	helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts

openshift-projects:
	oc new-project vault || true
	oc new-project vault-secrets-operator || true
	oc new-project expenses || true

vault-deploy: openshift-projects
	helm upgrade --install --namespace=vault --version=1.3.2 --values=helm/csi.openshift.yaml csi secrets-store-csi-driver/secrets-store-csi-driver
	helm upgrade --install --namespace=vault --version=0.23.0 --values=helm/vault.openshift.yaml --values=helm/vault-csi.openshift.yaml vault hashicorp/vault
	kubectl patch --namespace=vault daemonset vault-csi-provider --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/securityContext", "value": {"privileged": true} }]'
	helm upgrade --install --namespace=vault-secrets-operator --version 0.1.0-beta vault-secrets-operator hashicorp/vault-secrets-operator

openshift-vault: vault-deploy
	oc adm policy add-scc-to-user privileged system:serviceaccount:vault:secrets-store-csi-driver
	oc adm policy add-scc-to-user privileged system:serviceaccount:vault:vault-csi-provider

vault-init:
	kubectl exec -ti --namespace=vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json > unseal.json
	sleep 10
	kubectl exec -ti --namespace=vault vault-0 -- vault operator unseal $(shell cat unseal.json | jq -r '.unseal_keys_hex[0]')

vault-auth-method:
	bash scripts/k8s-auth-method.sh

vault-db-configure:
	bash scripts/vault-db-admin.sh

database-deploy:
	kubectl apply --namespace=expenses -f database/deployment.yaml

vault-expense-configure:
	bash scripts/vault-expense-secrets.sh

expense-deploy:
	kubectl delete --namespace=expenses -f expense/csi/ --ignore-not-found
	kubectl delete --namespace=expenses -f expense/operator/ --ignore-not-found
	kubectl apply --namespace=expenses -f expense/service.yaml
	kubectl apply --namespace=expenses -f expense/deployment-agent.yaml
	oc expose service expense --namespace=expenses

expense-deploy-csi:
	kubectl delete --namespace=expenses -f expense/deployment-agent.yaml --ignore-not-found
	kubectl delete --namespace=expenses -f expense/operator/ --ignore-not-found
	kubectl apply --namespace=expenses -f expense/service.yaml
	kubectl apply --namespace=expenses -f expense/csi/
	oc expose service expense --namespace=expenses

expense-deploy-operator:
	kubectl delete --namespace=expenses -f expense/deployment-agent.yaml --ignore-not-found
	kubectl delete --namespace=expenses -f expense/csi/ --ignore-not-found
	kubectl apply --namespace=expenses -f expense/service.yaml
	kubectl apply --namespace=expenses -f expense/operator/
	oc expose service expense --namespace=expenses

expense-post:
	curl --silent -X POST 'http://expense-expenses.apps-crc.testing/api/expense' -H 'Content-Type:application/json' -d @data/expense.json | jq

expense-get:
	curl --silent 'http://expense-expenses.apps-crc.testing/api/expense' -H 'Content-Type:application/json' | jq

vault-revoke:
	vault list sys/leases/lookup/expense/database/mysql/creds/expense
	vault lease revoke -prefix expense/database/mysql/creds

clean:
	crc delete