# =============================================================================
# VexarDrive Fleet Ping Service — CORE Terraform Configuration
# -----------------------------------------------------------------------------
# PURPOSE: Provision the FOUNDATIONAL INFRASTRUCTURE (shared, rarely changes):
#   Resource Group, VNet + subnets, PostgreSQL, Key Vault + secrets,
#   Log Analytics, Container Apps Environment, private DNS.
# This config does NOT deploy the application. That lives in ../app (the
# azurerm_container_app resource). Split keeps infra changes out of every
# application deploy, and app deploys out of infra changes.
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
  backend "azurerm" {
    # Use a distinct state key so infra changes are separate from app deploys
    # key = "core-fleet-ping.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

data "azurerm_client_config" "current" {}

# ---------------------------------------------------------------------------
# Naming
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
# Networking (provisioned once; consumed by the app tier via the CAE)
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
  delegation {
    name = "db-delegation"
    service_delegation {
      name      = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions   = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

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
# Azure Container Apps Environment (host for the app-tier ACA)
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.name_prefix}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_container_app_environment" "main" {
  name                       = "${local.name_prefix}-cae"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  infrastructure_subnet_id   = azurerm_subnet.app.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.tags
}

# ---------------------------------------------------------------------------
# Azure Database for PostgreSQL — Flexible Server (private)
# ---------------------------------------------------------------------------
resource "random_password" "db_password" {
  length  = 32
  special = true
}

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

resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = var.db_name
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.UTF8"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "management" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# ---------------------------------------------------------------------------
# Key Vault + secrets (generated in core; consumed by the app via data sources)
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

# Dev/CI principal — manages secrets in the vault
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  secret_permissions = ["Get", "List", "Set", "Delete", "Purge"]
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = true
}

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
