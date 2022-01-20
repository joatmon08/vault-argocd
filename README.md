# Running Vault with ArgoCD

## Prerequisites

- Helm 3.0+
- Vault 1.9+

## Install Vault

### OpenShift

This is an example! You can try it with Red Hat CodeReady Containers.

1. Install CRC.

1. Set up a cluster. Make sure to paste the pull secret when prompted.
   The command will log you in as an administrator.
   ```shell
   make crc-start
   ```

1. Add the Secrets Store CSI driver and HashiCorp Helm repositories.
   ```shell
   make helm-setup
   ```

1. Set up OpenShift projects for `vault` and the application (`expenses`).
   ```shell
   make openshift-projects
   ```

1. Deploy the Vault Helm chart with OpenShift values. The values deploy
   a Vault cluster with one server (high availability configuration)
   and an injector. Make sure to copy the output!

    > Note: By default, HA mode [deploys 3 servers](https://www.vaultproject.io/docs/platform/k8s/helm/openshift#highly-available-raft-mode)
    > with a constraint of one server per unique host.
    > As a CRC cluster, we only have one host so I can only deploy one server.

   ```shell
   make vault-deploy
   ```

1. Vault starts out uninitialized and sealed! This is to protect the secrets.
   You need to give it __three__ different unseal keys in order to open Vault for use.
   Copy three keys from `unseal_keys.txt`

   > Note: Vault's seal mechanism uses [Shamir's secret sharing](https://www.vaultproject.io/docs/concepts/seal).
   > This is a manual process to secure the cluster if it restarts. You can use
   > [auto-unseal](https://www.vaultproject.io/docs/configuration/seal) for
   > specific cloud providers to bypass the manual requirement.

   ```shell
   make vault-init
   ```

## Set up Kubernetes authentication method

Vault uses the concept of authentication methods (AKA auth method) to allow an
entity to retrieve a secret.
[Authentication methods](https://www.vaultproject.io/docs/auth) are plugins that integrate
with authentication providers, like OIDC or Kubernetes.

We'll use the [Kubernetes auth method](https://www.vaultproject.io/docs/auth/kubernetes),
which uses a service account identity to allow a pod
to access a secret from Vault.

1. Go into the `vault-0` pod.
   ```shell
   make vault-auth-method
   ```

1. Enable the Kubernetes auth method.
   ```shell
   vault auth enable kubernetes
   ```

1. Set up the Kubernetes configuration to use Vault's service account JWT.
   ```shell
   vault write auth/kubernetes/config issuer="" \
 		token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
 		kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
 		kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
   ```

1. Exit from the `vault-0` pod.

## Using Sidecar for Vault Agent

Typically, you run a sidecar with Vault agent. The Helm chart sets up a mutating webhook
that adds the sidecar to deployments with the annotation `vault.hashicorp.com/agent-inject: "true"`.

1. Set up port-forward for Vault in a different terminal session.
   ```shell
   make vault-port-forward
   ```

### Configure bootstrap database password into a static secret

Vault can support the storage of static secrets, like a password for bootstrapping
a database. You can store static secrets into Vault's
[key-value secrets engine](https://www.vaultproject.io/docs/secrets/kv/kv-v2).

1. Enable the KV secrets engine and create a Vault role that allows a pod to
   read the static database password at `expense/static/mysql`.
   ```shell
   make vault-db-configure
   ```

1. Deploy the database to the `expenses` namespace.
   ```shell
   make database-deploy
   ```

1. You can log into the database with the `db_login_password` you put into Vault's KV.

### Configure database username and password with dynamic secrets

Vault can also support the management and rotation of dynamic secrets,
like a set of usernames and passwords for databases. You can configure a
[database secrets engine](https://www.vaultproject.io/docs/secrets/databases).

We'll use the
[MySQL database secrets engine](https://www.vaultproject.io/docs/secrets/databases/mysql-maria)
with the application (called `expense`).

1. Enable the database secrets engine and create a Vault role that allows a pod to
   read the dynamic database username and password at `expense/database/mysql`.
   ```shell
   make vault-expense-configure
   ```

1. Deploy the application (`expense`) to the `expenses` namespace.
   ```shell
   make expense-deploy
   ```

1. You can port forward the expense application to check out the API.
   ```shell
   make expense-port-forward
   ```

1. Run an example call to write an expense to the `expense` API. It should succeed.
   ```shell
   curl -X POST 'http://localhost:15001/api/expense' \
      -H 'Content-Type:application/json' -d @data/expense.json
   ```

## Using Secrets Store CSI driver for Vault

If you don't want to run an agent sidecar, you can use the Secrets Store CSI driver for Vault.

> NOTE: The Secrets Store CSI driver requires access to the host path! This is
> [not recommended](https://docs.openshift.com/container-platform/4.9/storage/persistent_storage/persistent-storage-hostpath.html)
> for OpenShift production clusters.
### Install

1. Deploy [Secrets Store CSI driver](https://secrets-store-csi-driver.sigs.k8s.io/getting-started/installation.html).
   ```shell
   make csi-deploy
   ```

1. On OpenShift, you need to give Vault and Secrets Store CSI driver
   privileged access.
   ```shell
   make openshift-csi
   ```

### Update application to use Secrets Store CSI driver

You can deploy a new application (`expense`) that uses Secrets Store CSI. This means
that you do not need the sidecar for Vault agent.

> NOTE: If you are using OpenShift, you need to add an OpenShift security context
> that allows the application's service account to access the host path for the
> CSI driver (`expense/service.yaml`).

1. Deploy a new Kubernetes manifest for the application that uses Secrets Store CSI.
   ```shell
   make expense-deploy-csi
   ```

### General OpenShift Configuration for Secrets Store CSI

In general, you need configure the following:

- Add `securityContext.privileged = true` to your secrets store CSI driver pod specification

- Allow privileged access to provider and driver service accounts.
  ```shell
  oc adm policy add-scc-to-user privileged system:serviceaccount:$NAMESPACE:secrets-store-csi-driver
  oc adm policy add-scc-to-user privileged system:serviceaccount:$NAMESPACE:vault-csi-provider
  ```

- Allow host path access to application service accounts.
  ```yaml
  apiVersion: security.openshift.io/v1
  kind: SecurityContextConstraints
  metadata:
    name: vault-csi-provider
  allowPrivilegedContainer: false
  allowHostDirVolumePlugin: true
  allowHostNetwork: true
  allowHostPorts: true
  allowHostIPC: false
  allowHostPID: false
  readOnlyRootFilesystem: false
  defaultAddCapabilities:
  - SYS_ADMIN
  runAsUser:
    type: RunAsAny
  seLinuxContext:
    type: RunAsAny
  fsGroup:
    type: RunAsAny
  users:
  - system:serviceaccount:$NAMESPACE:$APPLICATION_SERVICE_ACCOUNT
  ```
