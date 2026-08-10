# =============================================================================
# APP Terraform Outputs
# =============================================================================

output "container_app_name" {
  description = "Name of the deployed Container App"
  value       = azurerm_container_app.fleet_ping.name
}

output "container_app_url" {
  description = "Public URL of the Fleet Ping service"
  value       = "https://${azurerm_container_app.fleet_ping.latest_revision_fqdn}"
}
