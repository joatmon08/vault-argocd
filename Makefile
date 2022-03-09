export VAULT_TOKEN=$(shell cat unseal.json | jq -r '.root_token')
export VAULT_ADDR=http://vault-vault.apps-crc.testing
export ARGO_URL=$(shell oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}{"\n"}')
export ARGO_PASSWORD=$(shell oc get secret/openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d)

docker-build:
	cd argocd-vault-plugin && docker build -t quay.io/joatmon080/argocd-vault-plugin:1.8.0 .
	docker push quay.io/joatmon080/argocd-vault-plugin:1.8.0

crc-start:
	crc setup
	crc start > crc-login
	oc login -u kubeadmin https://api.crc.testing:6443

helm-setup:
	helm repo add hashicorp https://helm.releases.hashicorp.com
	helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts

openshift-projects:
	oc new-project vault || true
	oc new-project expenses || true

csi-deploy:
	helm upgrade --install --namespace=vault --version=1.1.1 --values=helm/csi.openshift.yaml csi secrets-store-csi-driver/secrets-store-csi-driver
	helm upgrade --install --namespace=vault --version=0.19.0 --values=helm/vault.openshift.yaml --values=helm/vault-csi.openshift.yaml vault hashicorp/vault
	kubectl patch --namespace=vault daemonset vault-csi-provider --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/securityContext", "value": {"privileged": true} }]'

openshift-csi: csi-deploy
	oc adm policy add-scc-to-user privileged system:serviceaccount:vault:secrets-store-csi-driver
	oc adm policy add-scc-to-user privileged system:serviceaccount:vault:vault-csi-provider

vault-init:
	kubectl exec -ti --namespace=vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json > unseal.json
	kubectl exec -ti --namespace=vault vault-0 -- vault operator unseal

openshift-gitops-deploy:
	oc apply -f argocd/install/gitops.yaml
	oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller

vault-auth-method:
	bash scripts/k8s-auth-method.sh
	oc delete -f argocd/install/argocd.yaml
	oc apply -f argocd/install/argocd.yaml

vault-config-operator:
	oc new-project vault-config-operator || true
	kubectl create --save-config --dry-run=client secret generic vault \
		--from-literal=VAULT_ADDR=http://vault.vault:8200 \
		--from-literal=VAULT_TOKEN=$(shell cat unseal.json | jq -r '.root_token') \
		-o yaml | kubectl apply --namespace vault-config-operator -f -
	kubectl apply -f vault-config/install/vault.yaml
	oc new-project namespace-configuration-operator || true
	kubectl apply -f vault-config/install/namespace.yaml

db-secrets:
	argocd login --insecure --grpc-web ${ARGO_URL}  --username admin --password ${ARGO_PASSWORD}
	kubectl apply -f argocd/project.yaml
	kubectl apply -f argocd/secrets.yaml

db-deploy:
	kubectl apply -f argocd/database.yaml
	argocd app sync expense-secrets --replace

app-deploy:
	kubectl apply -f argocd/expense.yaml

expense-port-forward:
	kubectl port-forward --namespace=expenses svc/expense 15001:5001

expense-test:
	curl -X POST 'http://localhost:15001/api/expense' -H 'Content-Type:application/json' -d @data/expense.json
	curl 'http://localhost:15001/api/expense' -H 'Content-Type:application/json'

expense-csi:
	kubectl apply -f expense/csi/ -n expenses

clean:
	crc delete