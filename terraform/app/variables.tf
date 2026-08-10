# =============================================================================
# APP Terraform Variables (application deployment only)
# =============================================================================

variable "environment" {
  description = "Deployment environment (dev, staging, production)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "key_vault_name" {
  description = "Name of the Key Vault created by the core config (set from core output)"
  type        = string
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "vexar_fleet"
}

variable "container_image" {
  description = "Container image to deploy (e.g., ghcr.io/vexardrive/fleet-ping-service:<sha>)"
  type        = string
}

variable "app_cpu" {
  description = "CPU cores per replica"
  type        = number
  default     = 0.5
}

variable "app_memory" {
  description = "Memory per replica"
  type        = string
  default     = "1Gi"
}

variable "app_min_replicas" {
  description = "Minimum replicas"
  type        = number
  default     = 1
}

variable "app_max_replicas" {
  description = "Maximum replicas"
  type        = number
  default     = 10
}

variable "alert_email" {
  description = "Email for critical alerts"
  type        = string
  default     = "oncall@vexardrive.com"
}
