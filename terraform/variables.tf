# =============================================================================
# Terraform Variables
# =============================================================================

variable "environment" {
  description = "Deployment environment (dev, staging, production)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

variable "container_image" {
  description = "Container image to deploy (e.g., ghcr.io/vexardrive/fleet-ping-service:latest)"
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the VNet"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "app_subnet_prefixes" {
  description = "Address prefixes for the app subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "db_subnet_prefixes" {
  description = "Address prefixes for the database subnet"
  type        = list(string)
  default     = ["10.0.2.0/24"]
}

variable "db_username" {
  description = "PostgreSQL administrator username"
  type        = string
  default     = "vexar_admin"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "vexar_fleet"
}

variable "db_sku" {
  description = "PostgreSQL Flexible Server SKU"
  type        = string
  default     = "B_Standard_B1ms"  # Burstable — cost-effective for dev/staging
}

variable "db_storage_mb" {
  description = "Storage size for PostgreSQL in MB"
  type        = number
  default     = 32768  # 32 GB
}

variable "db_backup_retention_days" {
  description = "Backup retention days for PostgreSQL"
  type        = number
  default     = 7
}

variable "app_cpu" {
  description = "CPU cores per container app replica"
  type        = number
  default     = 0.5
}

variable "app_memory" {
  description = "Memory per container app replica"
  type        = string
  default     = "1Gi"
}

variable "app_min_replicas" {
  description = "Minimum number of container app replicas"
  type        = number
  default     = 1
}

variable "app_max_replicas" {
  description = "Maximum number of container app replicas"
  type        = number
  default     = 10
}

variable "log_retention_days" {
  description = "Log retention in days for Log Analytics"
  type        = number
  default     = 30
}

variable "alert_email" {
  description = "Email address for critical alerts"
  type        = string
  default     = "oncall@vexardrive.com"
}
