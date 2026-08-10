# =============================================================================
# VexarDrive Fleet Ping Service — Terraform (split into two independent configs)
# =============================================================================
#
# The infrastructure code is split into TWO separate Terraform configurations
# with separate state files, so that infrastructure provisioning and application
# deployment are independent of each other:
#
#   ├── core/   → FOUNDATIONAL INFRASTRUCTURE (provisioned rarely)
#   │             Resource Group, VNet, subnets, PostgreSQL, Key Vault,
#   │             Log Analytics, Container Apps Environment, private DNS.
#   │             State key: core-fleet-ping.tfstate
#   │
#   └── app/    → APPLICATION DEPLOYMENT (applied on every CI/CD deploy)
#   │             ONLY the azurerm_container_app + its scoped alerts/access.
#   │             Reads the shared infrastructure back via data sources.
#   │             State key: app-fleet-ping.tfstate
#
# To provision infrastructure (run once per environment):
#   cd core && terraform init && terraform apply \
#     -var="environment=production" -var-file=environments/production.tfvars
#
# To deploy the application (every release, done by CI/CD):
#   cd app && terraform init && terraform apply \
#       -var="environment=production" \
#       -var="key_vault_name=$(terraform -chdir=../core output -raw key_vault_name)" \
#       -var="container_image=ghcr.io/vexardrive/fleet-ping-service:<sha>" \
#       -var-file=environments/production.tfvars
# =============================================================================
