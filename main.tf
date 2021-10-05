resource "kubernetes_namespace" "vault" {
  metadata {
    annotations = {
      name = "vault"
    }
    name = "vault"
  }
}

data "template_file" "vault_values" {
  template = file("${path.module}/resources/vault-values.yaml.tpl")

  vars = {
    image_tag           = var.image_tag
    vault_k8s_image_tag = var.k8s_image_tag
    ingress_host        = "vault.${var.k8s_domain}"
    server_replicas     = var.server_replicas
    injector_replicas   = var.injector_replicas
    node_selector       = var.node_selector
    tenant_id           = data.azurerm_client_config.current.tenant_id
    keyvault_name       = azurerm_key_vault.vault.name
    key_name            = azurerm_key_vault_key.generated.name
  }
}

resource "helm_release" "vault" {
  name       = var.release_name
  namespace  = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"

  values = [
    data.template_file.vault_values.rendered
  ]

  depends_on = [azurerm_key_vault.vault]
}

resource "azurerm_resource_group" "keyvault" {
  name     = "vault-keyvault-${var.location}-${var.platform}-${var.core_type}"
  location = var.location
}

resource "random_id" "keyvault" {
  byte_length = 4
  prefix      = "${var.platform}-${var.core_type}-"
}

resource "azurerm_key_vault" "vault" {
  name                = random_id.keyvault.hex
  location            = azurerm_resource_group.keyvault.location
  resource_group_name = azurerm_resource_group.keyvault.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  enabled_for_deployment = true

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_user_assigned_identity.aks_nodepool.principal_id

    key_permissions = [
      "get",
      "wrapKey",
      "unwrapKey",
    ]
  }

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "get",
      "list",
      "create",
      "delete",
      "update",
      "purge",
      "recover",
    ]
  }

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
}

resource "azurerm_monitor_diagnostic_setting" "key_vault_logging" {
  name                       = "keyvault-vault-${azurerm_resource_group.keyvault.location}"
  target_resource_id         = azurerm_key_vault.vault.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  log {
    category = "AuditEvent"
    enabled  = true
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }

  lifecycle {
    ignore_changes = [
      log,
      metric,
    ]
  }
}

resource "azurerm_key_vault_key" "generated" {
  name         = "vault-akv-key-${azurerm_resource_group.keyvault.location}"
  key_vault_id = azurerm_key_vault.vault.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "wrapKey",
    "unwrapKey",
  ]
}

resource "null_resource" "persist_root_token" {
  provisioner "local-exec" {
    environment = {
      CLUSTER_ENDPOINT = var.k8s_cluster_auth.host
      CLIENT_CERT      = var.k8s_cluster_auth.client_certificate
      CLIENT_KEY       = var.k8s_cluster_auth.client_key
      CLUSTER_CA       = var.k8s_cluster_auth.cluster_ca_certificate
    }
    command     = file("${path.module}/resources/persist_root_token.sh")
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    helm_release.vault
  ]
}
