# vault-k8s-init

Can be used as a guide to initialize and auto-unseal a Vault cluster running on AKS, then write the root token to a Kubernetes secret. Beware that the output of the initialization command is written to the filesystem of the first vault instance in the cluster. Use with caution.
