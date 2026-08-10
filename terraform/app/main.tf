# =============================================================================
# VexarDrive Fleet Ping Service — APP Terraform Configuration
# -----------------------------------------------------------------------------
# PURPOSE: Deploy ONLY the application (Azure Container App) on top of the
# infrastructure provisioned by ../core. This config is applied on every
# CI/CD deploy; it never touches VNet, PostgreSQL, Key Vault, etc.
# It reads the shared infrastructure back via data sources.
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
  }
  backend "azurerm" {
    # Separate state key so app deploys don't contend with core changes
    # key = "app-fleet-ping.tfstate"
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

locals {
  tags = {
    Environment = var.environment
    Project     = "VexarDrive"
    Service     = "FleetPing"
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------------------------
# Data sources — read the infrastructure provisioned by the core config
# ---------------------------------------------------------------------------
data "azurerm_resource_group" "main" {
  name = "vexar-${var.environment}-rg"
}

data "azurerm_container_app_environment" "main" {
  name                = "vexar-${var.environment}-cae"
  resource_group_name = data.azurerm_resource_group.main.name
}

data "azurerm_key_vault" "main" {
  name                = var.key_vault_name
  resource_group_name = data.azurerm_resource_group.main.name
}

data "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  key_vault_id = data.azurerm_key_vault.main.id
}

data "azurerm_key_vault_secret" "jwt_secret" {
  name         = "jwt-secret"
  key_vault_id = data.azurerm_key_vault.main.id
}

data "azurerm_postgresql_flexible_server" "main" {
  name                = "vexar-${var.environment}-pg"
  resource_group_name = data.azurerm_resource_group.main.name
}

# ---------------------------------------------------------------------------
# Application deployment — the ONLY thing this config creates
# ---------------------------------------------------------------------------
resource "azurerm_container_app" "fleet_ping" {
  name                         = "vexar-${var.environment}-app"
  container_app_environment_id = data.azurerm_container_app_environment.main.id
  resource_group_name          = data.azurerm_resource_group.main.name
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

      liveness_probe {
        transport               = "HTTP"
        port                    = 3000
        path                    = "/health"
        interval_seconds        = 30
        timeout                 = 5
        failure_count_threshold = 3
      }

      readiness_probe {
        transport               = "HTTP"
        port                    = 3000
        path                    = "/ready"
        interval_seconds        = 15
        timeout                 = 5
        failure_count_threshold = 5
      }

      startup_probe {
        transport               = "HTTP"
        port                    = 3000
        path                    = "/health"
        interval_seconds        = 10
        timeout                 = 5
        failure_count_threshold = 10
      }

      env {
        name  = "NODE_ENV"
        value = var.environment
      }
      env {
        name  = "DB_HOST"
        value = data.azurerm_postgresql_flexible_server.main.fqdn
      }
      env {
        name  = "DB_PORT"
        value = "5432"
      }
      env {
        name  = "DB_USER"
        value = data.azurerm_postgresql_flexible_server.main.administrator_login
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

      # Secrets pulled from Key Vault (via data sources above)
      env {
        name        = "DB_PASSWORD"
        secret_name = "db-password"
      }
      env {
        name        = "JWT_SECRET"
        secret_name = "jwt-secret"
      }
    }

    scale_rule {
      name               = "http-scaling"
      custom_rule_type   = "http"
      custom_rule_metadata = {
        concurrentRequests = "100"
      }
    }
  }

  secret {
    name  = "db-password"
    value = data.azurerm_key_vault_secret.db_password.value
  }

  secret {
    name  = "jwt-secret"
    value = data.azurerm_key_vault_secret.jwt_secret.value
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
# Grant the Container App's identity read access to Key Vault secrets
# ---------------------------------------------------------------------------
resource "azurerm_key_vault_access_policy" "container_app" {
  key_vault_id      = data.azurerm_key_vault.main.id
  tenant_id         = data.azurerm_client_config.current.tenant_id
  object_id         = azurerm_container_app.fleet_ping.identity[0].principal_id
  secret_permissions = ["Get", "List"]
}

# ---------------------------------------------------------------------------
# Observability scoped to the application
# ---------------------------------------------------------------------------
data "azurerm_log_analytics_workspace" "main" {
  name                = "vexar-${var.environment}-logs"
  resource_group_name = data.azurerm_resource_group.main.name
}

resource "azurerm_monitor_diagnostic_setting" "container_app" {
  name                       = "vexar-${var.environment}-ca-diag"
  target_resource_id         = azurerm_container_app.fleet_ping.id
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.main.id
  enabled_log {
    category = "ContainerAppConsoleLogs"
  }
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_action_group" "critical" {
  name                = "vexar-${var.environment}-critical-ag"
  resource_group_name = data.azurerm_resource_group.main.name
  short_name          = "vex-critical"
  tags                = local.tags
  email_receiver {
    name                    = "oncall-team"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_metric_alert" "high_cpu" {
  name                = "vexar-${var.environment}-high-cpu"
  resource_group_name = data.azurerm_resource_group.main.name
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

resource "azurerm_monitor_metric_alert" "high_memory" {
  name                = "vexar-${var.environment}-high-memory"
  resource_group_name = data.azurerm_resource_group.main.name
  scopes              = [data.azurerm_container_app.fleet_ping.id]
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

resource "azurerm_monitor_metric_alert" "max_replicas" {
  name                = "vexar-${var.environment}-max-replicas"
  resource_group_name = data.azurerm_resource_group.main.name
  scopes              = [data.azurerm.container.app.fleet_ping.id]
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
