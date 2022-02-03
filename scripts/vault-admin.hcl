path "expense/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "sys/mounts" {
  capabilities = ["read"]
}

path "sys/auth" {
  capabilities = ["read"]
}

path "auth/kubernetes/*" {
  capabilities = ["create", "update", "read", "delete", "sudo"]
}

path "sys/policy/expense" {
  capabilities = ["create", "update", "read", "delete"]
}

path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "sys/policies/acl" {
  capabilities = ["read"]
}

path "sys/policies/password/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "sys/policies/password" {
  capabilities = ["read"]
}