# Governance Policy Deployment

## Overview

These scripts deploy Deny and Modify policies to enforce resource tagging
across an Azure environment. Both PowerShell and CLI (Bash) versions are
provided depending on environment and preference.

- **Deny policy** — blocks the creation of any resource that does not
  include a required tag. Enforces tagging at the point of deployment.
- **Modify policy** — automatically adds a missing tag to a resource after
  it has been created. Used to remediate existing non-compliant resources.

Policies can be scoped to a Management Group, Subscription, Resource Group,
or individual Resource depending on how broadly the rule needs to apply.

---

## What the Scripts Do

Both scripts follow the same interactive flow:

1. Authenticate to Azure and confirm the active subscription
2. Select policy type — Deny or Modify
3. Select scope level — Management Group, Subscription, Resource Group, or Resource
4. Define a tag name and display name
5. Define a default tag value (Modify only)
6. Review all inputs before deployment — edit any step if needed
7. Deploy the policy to the chosen scope

No resources are deployed until confirmed at the review screen.

---

## Prerequisites

**Licensing:**
- Any Azure subscription — no premium licensing required for policy deployment

**PowerShell modules (installed automatically if missing):**
- `Az.Accounts` — Azure authentication
- `Az.Resources` — Policy and resource management

**CLI requirements:**
- Azure CLI installed and up to date
- Run `az login` before executing the script if not already authenticated

**Permissions required:**
- `Resource Policy Contributor` — to create and assign policies
- `Owner` or `User Access Administrator` — if assigning at Management Group scope

---

## Running the Script

**PowerShell:**
```powershell
.\governance-policy.ps1
```

**CLI (Bash):**
```bash
chmod +x governance-policy.sh
./governance-policy.sh
```

Follow the prompts — a review screen is shown before anything is deployed.

---

## Prompt Reference

| Step | Prompt | Example Input |
|------|--------|---------------|
| 1 | Policy type | Deny or Modify |
| 2 | Scope level | Subscription |
| 3 | Scope name | My-Subscription |
| 4 | Tag name | environment |
| 5 | Display name | Require Environment Tag |
| 6 | Tag value (Modify only) | production |
| 7 | Review and confirm | C to confirm, E to edit, X to exit |

---

## Portal Walkthrough

### Creating a Deny Policy

1. In the Azure portal search bar type **Policy** and select **Azure Policy**
2. In the left menu select **Definitions** then click **+ Policy definition**
3. Set the **Definition location** to your subscription or management group
4. Enter a **Name** and **Description** for the policy
5. Under **Policy rule** paste the following JSON — replacing `YOUR-TAG-NAME`
   with your tag:
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
8. Set the **Scope** to your target Management Group, Subscription,
   Resource Group, or Resource
9. Under **Policy definition** search for and select the policy you just created
10. Enter an **Assignment name** and click **Review + create** then **Create**

---

### Creating a Modify Policy

1. Follow steps 1–4 from the Deny policy walkthrough above
2. Under **Policy rule** paste the following JSON — replacing `YOUR-TAG-NAME`
   and `YOUR-TAG-VALUE`:
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
4. Follow steps 7–10 from the Deny policy walkthrough above

---

### Verifying Compliance

1. In **Azure Policy** select **Compliance** from the left menu
2. Find your policy assignment in the list
3. Check the compliance state — **Compliant** or **Non-compliant**
4. Non-compliant resources are listed and can be remediated manually
   or via a remediation task

---

## Concepts Covered

These scripts demonstrate how Azure Policy can be used to enforce governance
standards across an environment without relying on manual processes or user
compliance.

Key concepts demonstrated:

- **Policy effects** — the difference between Deny (preventative) and Modify
  (corrective) and when to use each
- **Scope inheritance** — how policies assigned at a higher scope automatically
  apply to all child resources beneath it
- **Remediation tasks** — how Modify policies require a remediation task to
  apply changes to existing non-compliant resources
- **Interactive scripting patterns** — functions, switch/case blocks, while
  loops, and review screens used to build safe, user-friendly deployment tools

---

## Notes

- Deny policies apply at the point of resource creation — they do not
  affect resources that already exist
- Modify policies apply to existing resources — a remediation task must
  be triggered manually in the portal or via script to apply the tag
  retrospectively
- Policies assigned at a higher scope (e.g. Management Group) inherit
  down to all child subscriptions and resource groups automatically
- Allow up to 30 minutes for a newly assigned policy to take effect
  across all in-scope resources
