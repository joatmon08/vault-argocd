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

1. Deploy the Secrets Store CSI driver and Vault Helm chart with OpenShift values.
   The values deploy a Vault cluster with one server (high availability configuration)
   and an injector.

    > Note: By default, HA mode [deploys 3 servers](https://www.vaultproject.io/docs/platform/k8s/helm/openshift#highly-available-raft-mode)
    > with a constraint of one server per unique host.
    > As a CRC cluster, we only have one host so I can only deploy one server.

   ```shell
   make openshift-csi
   ```

1. Vault starts out uninitialized and sealed! This is to protect the secrets.
   You need to give it __one__ unseal keys in order to open Vault for use.
   Copy the unseal key from `unseal_keys_hex` in `unseal.json`

   > Note: Vault's seal mechanism uses [Shamir's secret sharing](https://www.vaultproject.io/docs/concepts/seal).
   > This is a manual process to secure the cluster if it restarts. You can use
   > [auto-unseal](https://www.vaultproject.io/docs/configuration/seal) for
   > specific cloud providers to bypass the manual requirement.

   ```shell
   make vault-init
   ```

## Deploy ArgoCD

We use Red Hat's [Openshift GitOps](https://docs.openshift.com/container-platform/4.9/cicd/gitops/understanding-openshift-gitops.html)
to deploy ArgoCD to our cluster.

1. Deploy OpenShift GitOps into the `openshift-gitops` namespace.
   The command reinstalls ArgoCD with the `argocd-vault-plugin`.
   ```shell
   make openshift-gitops-deploy
   ```

## Set up Kubernetes authentication method

Vault uses the concept of authentication methods (AKA auth method) to allow an
entity to retrieve a secret.
[Authentication methods](https://www.vaultproject.io/docs/auth) are plugins that integrate
with authentication providers, like OIDC or Kubernetes.

We'll use the [Kubernetes auth method](https://www.vaultproject.io/docs/auth/kubernetes),
which uses a service account identity to allow a pod
to access a secret from Vault.

The Kubernetes auth method attaches to two Vault roles.

- `vault-admin`: for the `vault-config-operator` to configure secrets engines and policies
- `argocd`: for the `argocd-vault-plugin` to read secrets for the expense application

These two Vault roles ensure that you can audit and identify which entity accesses
Vault and for what purposes.

1. Set up the Kubernetes authentication method.
   ```shell
   make vault-auth-method
   ```

The command replaces the `ArgoCD` specification with a customized one that...

- Installs the `argocd-vault-plugin`
- Uses the `argocd` service account

## Deploy the Vault configuration operator

You can use Kubernetes manifests to configure Vault secrets engines
and policies. In this example, you'll pass custom resources to configure
KV and database secrets engines for the expense database and application.

1. Deploy the [Vault config operator](https://github.com/redhat-cop/vault-config-operator).
   ```shell
   make vault-config-operator
   ```

## Configure secrets engines, database, and applications

Set up a static secrets for the database root password using the
Vault config operator. It will create password policy and random secret,
stored in Vault's key-value store (version 1).

> Note: `RandomSecret` may not work with kv version 2.

1. Set up the ArgoCD project and secrets engines in Vault.
   ```shell
   make db-secrets
   ```

1. Deploy the database. This allows Vault to configure the database secrets engine.
   It uses the `argocd-vault-plugin` to inject secrets into the database.
   ```shell
   make db-deploy
   ```

1. Deploy the application. It uses the database secrets engine set up by the Vault
   config operator. However, the application includes Vault agent instead of the
   `argocd-vault-plugin`.
   ```shell
   make app-deploy
   ```

## Clean up

```shell
crc delete
```