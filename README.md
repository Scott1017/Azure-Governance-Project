# Azure Governance Project

Contains PowerShell and CLI scripts for deploying Azure governance
policies and managing Entra ID dynamic security groups.

---

## Overview

The purpose of this project is to provide easy to run, interactive
deployment scripts for Azure governance policies and dynamic security
group management. Scripts have been created for both PowerShell and
CLI (Bash) depending on environment and preference.

Identity and governance is important in any Azure environment — it
enables compliance with legislation such as GDPR, supports cost
management, and ensures resources are organised and auditable
across the organisation.

---

## Structure

```
azure-governance-project/
├── policies/
│   ├── governance-policy.ps1       # PowerShell deployment script
│   ├── governance-policy.sh        # CLI (Bash) deployment script
│   └── README.md                   # Policy deployment guide
└── identity/
    ├── Invoke-AuditAccessSetup.ps1 # PowerShell deployment script
    ├── Invoke-AuditAccessSetup.sh  # CLI (Bash) deployment script
    └── README.md                   # Audit access setup guide

```
---

## Components

### Policies
Deploys Deny and Modify policies to enforce resource tagging across
Azure resources at a chosen scope. See [policies/README.md](policies/README.md)
for full deployment guide and portal walkthrough.

### Identity
Sets up time-bound, read-only audit access groups in Microsoft Entra ID
using dynamic security groups, Conditional Access, and RBAC. Supports
both P1 and P2 licensing paths. See [identity/README.md](identity/README.md)
for full deployment guide and portal walkthrough.