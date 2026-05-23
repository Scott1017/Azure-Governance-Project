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

## Components

azure-governance-project/
├── policies/
│   ├── governance-policy.ps1   # PowerShell deployment script
│   └── governance-policy.sh    # CLI (Bash) deployment script
└── identity/
├── dynamic-group.ps1       # Coming soon
└── dynamic-group.sh        # Coming soon

---

## Portal Walkthrough

### Creating a Deny Policy

1. In the Azure portal search bar type **Policy** and select **Azure Policy**
2. In the left menu select **Definitions** then click **+ Policy definition**
3. Set the **Definition location** to your subscription or management group
4. Enter a **Name** and **Description** for the policy
5. Under **Policy rule** paste the following JSON — replacing `YOUR-TAG-NAME` with your tag:
```json
    {
        "if": {
            "field": "tags['YOUR-TAG-NAME']",
            "exists": "false"
        },
        "then": {
            "effect": "deny"
        }
    }
```
6. Click **Save**
7. In the left menu select **Assignments** then click **+ Assign policy**
8. Set the **Scope** to your target Management Group, Subscription, Resource Group or Resource
9. Under **Policy definition** search for and select the policy you just created
10. Enter an **Assignment name** and click **Review + create** then **Create**

---

### Creating a Modify Policy

1. Follow steps 1-4 above
2. Under **Policy rule** paste the following JSON — replacing `YOUR-TAG-NAME` and `YOUR-TAG-VALUE`:
```json
    {
        "if": {
            "field": "tags['YOUR-TAG-NAME']",
            "exists": "false"
        },
        "then": {
            "effect": "modify",
            "details": {
                "roleDefinitionIds": [
                    "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
                ],
                "operations": [{
                    "operation": "add",
                    "field": "tags['YOUR-TAG-NAME']",
                    "value": "YOUR-TAG-VALUE"
                }]
            }
        }
    }
```
3. Click **Save**
4. Follow steps 7-10 from the Deny policy walkthrough above

---

### Verifying Compliance

1. In **Azure Policy** select **Compliance** from the left menu
2. Find your policy assignment in the list
3. Check the compliance state — **Compliant** or **Non-compliant**
4. Non-compliant resources are listed and can be remediated manually or via a remediation task

---

## Concepts Covered

These scripts demonstrate the creation and assignment of Deny and 
Modify policies to enforce tagging across Azure resources, groups, 
and subscriptions at a chosen scope level.

The scripts are built as a one size fits all interactive tool using 
functions, if statements, while loops and switch/case blocks. The 
user flow covers:

- Authenticating to Azure and confirming the active subscription
- Selecting Deny or Modify policy type
- Selecting the scope level — Management Group, Subscription, 
  Resource Group, or Resource
- Defining a tag name and display name
- Defining a default tag value (Modify only)
- Reviewing and correcting inputs before deployment
- Deploying the policy to the chosen scope