Overview
This repository contains the complete solution for the VexarDrive Technologies DevOps & Cloud Infrastructure Engineer Technical Assessment.

The solution demonstrates production-readiness improvements to a Node.js/Express Fleet Ping Service, including:

- Security hardening — eliminated hardcoded secrets, SQL injection, auth bypasses
- Containerization — multi-stage Docker build, non-root user, health checks
- Azure Infrastructure as Code — Terraform for Container Apps + PostgreSQL + Key Vault
- CI/CD Pipeline — GitHub Actions with test → scan → build → deploy → verify
- Monitoring — health/readiness endpoints, structured logging, Azure Monitor alerts
- Database operations — connection pooling, PITR, least-privilege access
- Architecture diagram — component interactions and network boundaries
- Technical report — comprehensive documentation of all decisions

Repository Structure

vexar-drive-solution/
├── .github/
│   └── workflows/
│       └── ci-cd.yml              # CI/CD pipeline (GitHub Actions)
├── src/
│   ├── server.js                  # Production-ready application
│   ├── package.json               # Dependencies
│   ├── schema.sql                 # Database schema with indexes
│   ├── Dockerfile                 # Multi-stage production Dockerfile
│   └── .dockerignore              # Excludes from Docker build context
├── infra/
│   ├── core/    → INFRASTRUCTURE PROVISIONING (runs rarely)
│   |     ├── main.tf      
│   |     ├── variables.tf
│   |     ├── outputs.tf    
│   |     └── environments/ (dev/staging/production tfvars)
│   |
|   └── app/     → APPLICATION DEPLOYMENT (runs on every CI/CD deploy)
│        ├── main.tf      
│        ├── variables.tf
│        ├── outputs.tf
│        └── environments/ (dev/staging/production tfvars) 
|
├── docker-compose.yml             # Local development setup
└── README.md                      # This file
