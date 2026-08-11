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
