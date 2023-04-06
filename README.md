# Running Vault with ArgoCD

## Prerequisites

- Helm 3.0+
- Vault 1.13+
- Kubernetes 1.25+

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

1. Set up OpenShift projects for `vault`, the operator (`vault-secrets-operator`),
   and the application (`expenses`).
   ```shell
   make openshift-projects
   ```

1. Deploy the Vault Helm chart with OpenShift values. The values deploy
   a Vault cluster with one server (high availability configuration)
   and an injector.

    > Note: By default, HA mode [deploys 3 servers](https://www.vaultproject.io/docs/platform/k8s/helm/openshift#highly-available-raft-mode)
    > with a constraint of one server per unique host.
    > As a CRC cluster, we only have one host so I can only deploy one server.

   ```shell
   make openshift-vault
   ```

1. Vault starts out uninitialized and sealed! This is to protect the secrets. Unseal
   it with a key.

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

```shell
make vault-auth-method
```

## Configure bootstrap database password into a static secret

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

## Configure database username and password with dynamic secrets

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

## Using Vault Agent Injector

The [Vault agent injector](https://developer.hashicorp.com/vault/docs/platform/k8s/injector)
provides a secure way to inject secrets into the application
using pod volumes.

Deploy the application (`expense`) to the `expenses` namespace.

```shell
make expense-deploy
```

## Using Secrets Store CSI driver for Vault

If you don't want to run an agent sidecar, you can use the
[Secrets Store CSI driver for Vault](https://developer.hashicorp.com/vault/docs/platform/k8s/csi).

> NOTE: The Secrets Store CSI driver requires access to the host path! This is
> [not recommended](https://docs.openshift.com/container-platform/4.9/storage/persistent_storage/persistent-storage-hostpath.html)
> for OpenShift production clusters.

You can deploy a new application (`expense`) that uses Secrets Store CSI. This means
that you do not need the sidecar for Vault agent.

> NOTE: If you are using OpenShift, you need to add an OpenShift security context
> that allows the application's service account to access the host path for the
> CSI driver (`expense/csi/scc.yaml`).

1. Deploy a new Kubernetes manifest for the application that uses Secrets Store CSI.
   ```shell
   make expense-deploy-csi
   ```

## Using Vault Secrets Operator

If you do not want to the Secrets Store CSI Driver and instead want to use Kubernetes secrets,
you can use the [Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/platform/k8s/vso).

The operator supports custom resources that allow you to specify the Vault connection,
authentication method, and dynamic secrets to retrieve.

> NOTE: Find example custom resources in `expense/operator/`.

```shell
make expense-deploy-operator
```

## Test Application and Credentials

To test, you can add an expense.

```shell
make expense-post
```

To get a list of expenses, run:

```shell
make expense-get
```

Revoke all the leases for database usernames and passwords.

```shell
make vault-revoke
```

Check that the application gets a new set of credentials.