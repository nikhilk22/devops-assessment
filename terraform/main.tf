# =============================================================================
# VexarDrive Fleet Ping Service — Terraform (Azure)
# Architecture: Azure Container Apps + PostgreSQL Flexible Server + Key Vault
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Backend: Use Azure Storage for state management
  # backend "azurerm" {
  #   resource_group_name  = "terraform-state-rg"
  #   storage_account_name = "vexarterraformstate"
  #   container_name       = "tfstate"
  #   key                  = "fleet-ping-service.tfstate"
  # }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------
data "azurerm_client_config" "current" {}

# ---------------------------------------------------------------------------
# Resource naming
# ---------------------------------------------------------------------------
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  name_prefix = "vexar-${var.environment}"
  suffix      = random_string.suffix.result
  tags = {
    Environment = var.environment
    Project     = "VexarDrive"
    Service     = "FleetPing"
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = local.tags
}

resource "azurerm_subnet" "app" {
  name                 = "${local.name_prefix}-app-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.app_subnet_prefixes

  # Delegation for Container Apps
  delegation {
    name = "container-apps-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "db" {
  name                 = "${local.name_prefix}-db-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.db_subnet_prefixes

  # Delegation for PostgreSQL Flexible Server
  delegation {
    name = "db-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Private DNS zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${local.name_prefix}-postgres-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
  tags                  = local.tags
}

# ---------------------------------------------------------------------------
# Azure Container Apps Environment
# ---------------------------------------------------------------------------
resource "azurerm_container_app_environment" "main" {
  name                       = "${local.name_prefix}-cae"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  infrastructure_subnet_id   = azurerm_subnet.app.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.tags
}

resource "azurerm_container_app" "fleet_ping" {
  name                         = "${local.name_prefix}-app"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.tags

  template {
    min_replicas = var.app_min_replicas
    max_replicas = var.app_max_replicas

    container {
      name   = "fleet-ping"
      image  = var.container_image
      cpu    = var.app_cpu
      memory = var.app_memory

      # Liveness probe (health endpoint)
      liveness_probe {
        transport = "HTTP"
        port      = 3000
        path      = "/health"
        interval_seconds = 30
        timeout          = 5
        failure_count_threshold = 3
      }

      # Readiness probe
      readiness_probe {
        transport = "HTTP"
        port      = 3000
        path      = "/ready"
        interval_seconds = 15
        timeout          = 5
        failure_count_threshold = 5
      }

      # Startup probe (for slow-starting containers)
      startup_probe {
        transport = "HTTP"
        port      = 3000
        path      = "/health"
        interval_seconds     = 10
        timeout              = 5
        failure_count_threshold = 10
      }

      env {
        name  = "NODE_ENV"
        value = var.environment
      }

      env {
        name  = "DB_HOST"
        value = azurerm_postgresql_flexible_server.main.fqdn
      }

      env {
        name  = "DB_PORT"
        value = "5432"
      }

      env {
        name  = "DB_NAME"
        value = var.db_name
      }

      env {
        name  = "DB_SSL"
        value = "true"
      }

      env {
        name  = "DB_POOL_MAX"
        value = "20"
      }

      env {
        name  = "JWT_EXPIRY"
        value = "24h"
      }

      env {
        name  = "PORT"
        value = "3000"
      }

      # Managed Identity reference for DB user (injected at runtime)
      env {
        name  = "DB_USER"
        value = var.db_username
      }

      # Secrets from Key Vault (referenced via service connection)
      env {
        name        = "DB_PASSWORD"
        secret_name = "db-password"
      }

      env {
        name        = "JWT_SECRET"
        secret_name = "jwt-secret"
      }
    }

    # Scale rule based on HTTP traffic
    scale_rule {
      name               = "http-scaling"
      custom_rule_type   = "http"
      custom_rule_metadata = {
        concurrentRequests = "100"
      }
    }
  }

  # Secrets referenced from Key Vault via Managed Identity
  secret {
    name  = "db-password"
    value = azurerm_key_vault_secret.db_password.value
  }

  secret {
    name  = "jwt-secret"
    value = azurerm_key_vault_secret.jwt_secret.value
  }

  identity {
    type = "SystemAssigned"
  }

  ingress {
    external_enabled = true
    target_port      = 3000
    transport        = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

# ---------------------------------------------------------------------------
# Azure Database for PostgreSQL — Flexible Server
# ---------------------------------------------------------------------------
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "${local.name_prefix}-pg"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  version                = "16"
  delegated_subnet_id    = azurerm_subnet.db.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres.id
  administrator_login    = var.db_username
  administrator_password = random_password.db_password.result
  zone                   = "1"
  storage_mb             = var.db_storage_mb
  sku_name               = var.db_sku
  backup_retention_days  = var.db_backup_retention_days
  geo_redundant_backup_enabled = var.environment == "production" ? true : false
  tags                   = local.tags
}

resource "random_password" "db_password" {
  length  = 32
  special = true
}

# PostgreSQL database
resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = var.db_name
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.UTF8"
}

# Firewall rule (for management access only — all app traffic goes through private endpoint)
resource "azurerm_postgresql_flexible_server_firewall_rule" "management" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# ---------------------------------------------------------------------------
# Azure Key Vault
# ---------------------------------------------------------------------------
resource "azurerm_key_vault" "main" {
  name                       = "${local.name_prefix}-kv-${local.suffix}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags                       = local.tags
}

# Grant the Container App access to Key Vault
resource "azurerm_key_vault_access_policy" "container_app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_container_app.fleet_ping.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}

# Grant current user (dev/CI) access to Key Vault
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Purge"]
}

# Key Vault secrets
resource "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  value        = random_password.db_password.result
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "jwt_secret" {
  name         = "jwt-secret"
  value        = random_password.jwt_secret.result
  key_vault_id = azurerm_key_vault.main.id
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = true
}

# ---------------------------------------------------------------------------
# Log Analytics Workspace
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.name_prefix}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Diagnostic settings — send Container App logs to Log Analytics
# ---------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "container_app" {
  name                       = "${local.name_prefix}-ca-diag"
  target_resource_id         = azurerm_container_app.fleet_ping.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "ContainerAppConsoleLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ---------------------------------------------------------------------------
# Action Groups & Alerts
# ---------------------------------------------------------------------------
resource "azurerm_monitor_action_group" "critical" {
  name                = "${local.name_prefix}-critical-ag"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "vex-critical"
  tags                = local.tags

  email_receiver {
    name                    = "oncall-team"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

# Alert: Container App CPU > 80%
resource "azurerm_monitor_metric_alert" "high_cpu" {
  name                = "${local.name_prefix}-high-cpu"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.fleet_ping.id]
  description         = "Alert when CPU usage exceeds 80%"

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "CpuUsage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
    frequency        = "PT5M"
    window_size      = "PT15M"
  }

  action {
    action_group_id = azurerm_monitor_action_group.critical.id
  }

  tags = local.tags
}

# Alert: Container App memory > 80%
resource "azurerm_monitor_metric_alert" "high_memory" {
  name                = "${local.name_prefix}-high-memory"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.fleet_ping.id]
  description         = "Alert when memory usage exceeds 80%"

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "MemoryUsage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
    frequency        = "PT5M"
    window_size      = "PT15M"
  }

  action {
    action_group_id = azurerm_monitor_action_group.critical.id
  }

  tags = local.tags
}

# Alert: Replica count near max
resource "azurerm_monitor_metric_alert" "max_replicas" {
  name                = "${local.name_prefix}-max-replicas"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.fleet_ping.id]
  description         = "Alert when replicas reach maximum count"

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "Replicas"
    aggregation      = "Maximum"
    operator         = "GreaterThanOrEqual"
    threshold        = var.app_max_replicas - 1
    frequency        = "PT5M"
    window_size      = "PT15M"
  }

  action {
    action_group_id = azurerm_monitor_action_group.critical.id
  }

  tags = local.tags
}

# Alert: PostgreSQL connections > 80% of max
resource "azurerm_monitor_metric_alert" "db_connections" {
  name                = "${local.name_prefix}-db-high-connections"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_postgresql_flexible_server.main.id]
  description         = "Alert when database connections exceed 80% of max"

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "active_connections"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
    frequency        = "PT5M"
    window_size      = "PT15M"
  }

  action {
    action_group_id = azurerm_monitor_action_group.critical.id
  }

  tags = local.tags
}
