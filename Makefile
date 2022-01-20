export VAULT_TOKEN=$(shell cat unseal.json | jq -r '.root_token')
export VAULT_ADDR=http://localhost:8200

crc-start:
	crc setup
	crc start
	oc login -u kubeadmin https://api.crc.testing:6443

helm-setup:
	helm repo add hashicorp https://helm.releases.hashicorp.com
	helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts

openshift-projects:
	oc new-project vault
	oc new-project expenses

csi-deploy:
	helm upgrade --install --namespace=vault --version=0.2.0 --values=helm/csi.openshift.yaml csi secrets-store-csi-driver/secrets-store-csi-driver
	helm upgrade --install --namespace=vault --version=0.19.0 --values=helm/vault.openshift.yaml --values=helm/vault-csi.openshift.yaml vault hashicorp/vault
	kubectl patch --namespace=vault daemonset vault-csi-provider --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/securityContext", "value": {"privileged": true} }]'

openshift-csi:
	oc adm policy add-scc-to-user privileged system:serviceaccount:vault:secrets-store-csi-driver
	oc adm policy add-scc-to-user privileged system:serviceaccount:vault:vault-csi-provider

vault-deploy:
	helm upgrade --install --namespace=vault --version=0.19.0 --values=helm/vault.openshift.yaml vault hashicorp/vault

vault-init:
	kubectl exec -ti --namespace=vault vault-0 -- vault operator init -format=json > unseal.json
	kubectl exec -ti --namespace=vault vault-0 -- vault operator unseal
	kubectl exec -ti --namespace=vault vault-0 -- vault operator unseal
	kubectl exec -ti --namespace=vault vault-0 -- vault operator unseal

vault-port-forward:
	kubectl port-forward --namespace=vault svc/vault 8200

vault-auth-method:
	@kubectl exec -ti --namespace=vault vault-0 -- /bin/sh -c 'export VAULT_TOKEN='$(shell cat unseal.json | jq -r '.root_token')' && /bin/sh'
	# vault auth enable kubernetes
	# vault write auth/kubernetes/config \
		issuer="" \
 		token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
 		kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
 		kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

vault-db-configure:
	vault secrets enable -version=2 -path=expense/static kv
	vault kv put expense/static/mysql db_login_password=${MYSQL_DB_PASSWORD}
	vault kv get expense/static/mysql
	vault policy write expense-db-mysql database/vault-policy.hcl
	vault write auth/kubernetes/role/expense-db-mysql \
		bound_service_account_names=expense-db-mysql \
		bound_service_account_namespaces=expenses \
		policies=expense-db-mysql \
		ttl=1h

database-deploy:
	kubectl apply --namespace=expenses -f database/deployment.yaml

vault-expense-configure:
	vault secrets enable -path=expense/database/mysql database
	vault write expense/database/mysql/config/mysql \
		plugin_name=mysql-database-plugin \
		connection_url="{{username}}:{{password}}@tcp(expense-db-mysql.expenses:3306)/" \
		allowed_roles="expense" \
		username="root" \
		password="${MYSQL_DB_PASSWORD}"
	vault write expense/database/mysql/roles/expense \
		db_name=mysql \
		creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT ALL PRIVILEGES ON DemoExpenses.expense_item TO '{{name}}'@'%';" \
		default_ttl="1h" \
		max_ttl="24h"
	vault policy write expense expense/vault-policy.hcl
	vault write auth/kubernetes/role/expense \
		bound_service_account_names=expense \
		bound_service_account_namespaces=expenses \
		policies=expense \
		ttl=1h

expense-deploy:
	kubectl delete --namespace=expenses -f expense/deployment-csi.yaml --ignore-not-found
	kubectl apply --namespace=expenses -f expense/service.yaml
	kubectl apply --namespace=expenses -f expense/deployment-agent.yaml

expense-deploy-csi:
	kubectl delete --namespace=expenses -f expense/deployment-agent.yaml --ignore-not-found
	kubectl apply --namespace=expenses -f expense/service.yaml
	kubectl apply --namespace=expenses -f expense/deployment-csi.yaml

expense-port-forward:
	kubectl port-forward --namespace=expenses svc/expense 15001:5001

expense-test:
	curl -X POST 'http://localhost:15001/api/expense' -H 'Content-Type:application/json' -d @data/expense.json
	curl 'http://localhost:15001/api/expense' -H 'Content-Type:application/json'

clean:
	kubectl delete --namespace=expenses -f expense/deployment-agent.yaml --ignore-not-found
	kubectl delete --namespace=expenses -f expense/deployment-csi.yaml --ignore-not-found
	kubectl delete --namespace=expenses -f expense/service.yaml --ignore-not-found
	vault lease revoke -f -prefix expense/database/mysql/ || true
	kubectl delete --namespace=expenses -f database/deployment.yaml --ignore-not-found
	helm uninstall --namespace=vault vault || true
	kubectl delete pvc data-vault-0 --ignore-not-found
	helm uninstall --namespace=vault csi || true
	oc adm policy remove-scc-from-user privileged system:serviceaccount:vault:vault-csi-provider || true
	oc adm policy remove-scc-from-user privileged system:serviceaccount:vault:secrets-store-csi-driver || true
	oc delete project expenses || true
	oc delete project vault