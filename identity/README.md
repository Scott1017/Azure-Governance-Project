# Azure Audit Access Setup

## Overview

This script creates a time-bound, read-only audit access group in Microsoft
Entra ID, scoped to a specific department. It is designed for scenarios where
temporary access to Azure resources is required — such as an audit, compliance
review, or third-party assessment — and where that access must expire
automatically without manual intervention.

The script is interactive, prompting for all required inputs before deployment.
A review screen is shown before anything is created, with the option to edit
any step or exit without deploying.

Two licensing paths are supported:

- **P1 path** — uses dynamic security groups, Conditional Access, resource
  tags, Action Groups, and an Automation Runbook to manage time-bound access
- **P2 path** — uses Privileged Identity Management (PIM) for native
  time-bound access with automatic expiry and no manual cleanup required

---

## How It Works

```

Department selected
↓
Dynamic security group created — membership rule auto-adds matching users
↓
Resource tags applied — marks target resource with audit context and expiry date
↓
Reader role assigned — read-only access scoped to the target resource
↓
Conditional Access policy created — enforces MFA and/or device compliance
↓
P1: Action Group configured — email alert fires before expiry
P2: PIM role assignment configured — access expires automatically
↓
Post-deployment actions displayed — required and recommended steps listed

```

---

## Prerequisites

**Licensing:**
- Microsoft Entra ID P1 (minimum) — dynamic groups, Conditional Access
- Microsoft Entra ID P2 (recommended) — adds PIM for native time-bound access

**PowerShell modules (installed automatically if missing):**
- `Microsoft.Graph` — Entra ID, groups, Conditional Access, PIM
- `Az.Accounts` — Azure authentication
- `Az.Resources` — resource and tag management
- `Az.Monitor` — Action Groups and alert rules

**Permissions required:**
- `Global Administrator` or `Privileged Role Administrator` — to create
  groups and assign roles
- `Security Administrator` — to configure Conditional Access policies
- `Contributor` or `Owner` on the target resource — to assign RBAC

---

## Licensing Paths

### P1 Path — Tag-based Expiry

The P1 path uses a combination of Azure components to replicate what PIM
handles natively at P2. Each component is a link in the chain — if any
one is missing, the expiry mechanism will not function correctly.

| Component | Purpose |
|-----------|---------|
| Dynamic security group | Auto-manages membership based on department attribute |
| Resource tags | Marks resource with expiry date for tracking and automation |
| RBAC Reader role | Grants read-only access scoped to the target resource |
| Conditional Access | Enforces MFA and/or device compliance for the group |
| Action Group | Sends email notification before access expires |
| Log Analytics workspace | Required for date-triggered alert rules |
| Automation Runbook | Removes role assignment automatically on expiry date |

> **Important:** The Log Analytics workspace and Automation Runbook are not
> created by this script. They must be configured manually after deployment.
> See [Post-Deployment Steps — P1 Setup](#p1-setup) for full guidance.

---

### P2 Path — Privileged Identity Management (PIM)

The P2 path uses PIM to manage time-bound access natively. The role
assignment expires automatically on the configured date with no manual
cleanup required.

| Component | Purpose |
|-----------|---------|
| Dynamic security group | Auto-manages membership based on department attribute |
| Resource tags | Marks resource with audit context for tracking |
| PIM role assignment | Grants time-bound Reader access — expires automatically |
| Conditional Access | Enforces MFA and/or device compliance for the group |

> **Note:** Custom notification recipients must be configured in the portal
> after deployment. PIM notifies role owners by default.
> See [Post-Deployment Steps — P2 Setup](#p2-setup) for guidance.

---

## Running the Script

**PowerShell:**
```powershell
.\Invoke-AuditAccessSetup.ps1
```

Follow the prompts — a review screen is shown before anything is deployed.
You can edit any step or exit without deploying from the review screen.

---

## Prompt Reference

| Step | Prompt | Example Input |
|------|--------|---------------|
| 1 | Department name | Finance |
| 2 | Number of users | 3 |
| 3 | Target resource name | finance-storage-account |
| 4 | Access duration (days) | 14 |
| 5 | Require MFA | Y |
| 6 | Require compliant device | N |
| 7 | Send expiry notification | Y |
| 7a | Notification email | admin@contoso.com |
| 7b | Days before expiry to alert | 3 |
| 8 | P2 licensing available | N |
| 9 | Review and confirm | C to confirm, E to edit, X to exit |

---

## Post-Deployment Steps

### P1 Setup

The following steps are **required** for the P1 path to function correctly.
Without them, access will not expire on schedule and alerts will not fire.

#### Log Analytics Workspace

A Log Analytics workspace is required to trigger date-based alert rules at
P1 level. Azure Monitor alert rules need a data source to query against —
without it the alert rule has nothing to evaluate and will never fire.

1. In the Azure portal search for **Log Analytics workspaces**
2. Click **+ Create**
3. Select your **Subscription** and **Resource Group**
4. Enter a **Name** (e.g. `audit-log-workspace`)
5. Select your **Region** and click **Review + Create** then **Create**
6. Once created, navigate to **Azure Monitor > Alerts > Alert rules**
7. Click **+ Create** and link the rule to your new workspace
8. Set the **Alert condition** to trigger on the expiry date calculated
   by the script
9. Under **Actions** select the Action Group created by the script
10. Click **Review + Create** then **Create**

---

#### Automation Runbook

An Automation Runbook is required to remove the Reader role assignment
when access expires. At P1 there is no native mechanism to expire a role
assignment by date — the Runbook reads the expiry tag and removes the
assignment automatically.

**Without this, access will remain in place indefinitely regardless of
the expiry tag.**

1. In the Azure portal search for **Automation Accounts**
2. Click **+ Create** and configure a new Automation Account
3. Inside the account select **Runbooks** then **+ Create a runbook**
4. Set **Runbook type** to **PowerShell**
5. Paste the following script — replacing the placeholder values:

```powershell
# Automation Runbook — Remove expired audit access role assignment
# Reads the expiry tag on the target resource and removes the Reader
# role assignment if the expiry date has been reached

Connect-AzAccount -Identity

$resourceName  = "YOUR-RESOURCE-NAME"
$groupName     = "YOUR-GROUP-NAME"
$expiryDateStr = (Get-AzResource -Name $resourceName).Tags["expiry"]
$expiryDate    = [datetime]::ParseExact($expiryDateStr, "yyyy-MM-dd", $null)

if ((Get-Date) -ge $expiryDate) {
    $resource = Get-AzResource -Name $resourceName
    $group    = Get-AzADGroup -DisplayName $groupName

    Remove-AzRoleAssignment `
        -ObjectId           $group.Id `
        -RoleDefinitionName "Reader" `
        -Scope              $resource.ResourceId

    Write-Output "Role assignment removed for $groupName on $resourceName"
} else {
    Write-Output "Access has not yet expired — no action taken."
}
```

6. Click **Save** then **Publish**
7. Under **Schedules** link the Runbook to run daily from the start date
   so it checks the expiry tag each day

---

#### Testing Your Alert

Before relying on the alert for production use, verify email delivery:

1. In the Azure portal navigate to **Azure Monitor > Alerts > Action Groups**
2. Find the Action Group created by the script —
   `Audit-Expiry-AG-[department]`
3. Click **Test** and select **Email**
4. Confirm the test email is received at the configured address
5. If not received, check spam filters and verify the email address
   entered during setup

---

### P2 Setup

PIM handles expiry and cleanup automatically. The following steps are
recommended but not required.

#### PIM Notifications

By default PIM notifies role owners when an assignment is created or
expires. To add a custom notification recipient:

1. In the Azure portal navigate to **Entra ID > Privileged Identity
   Management**
2. Select **Azure Resources** then find your target resource
3. Select **Roles** then **Reader**
4. Click **Role settings** then **Edit**
5. Under **Notification** add the required email address as a recipient
6. Click **Update**

---

## Portal Walkthrough

The following steps cover how to configure audit access manually in the
Azure portal without running the script. Useful for one-off setups or
for verifying what the script has deployed.

### Creating a Dynamic Security Group

1. In the Azure portal navigate to **Entra ID > Groups**
2. Click **+ New group**
3. Set **Group type** to **Security**
4. Enter a **Group name** (e.g. `Audit-Access-Finance`)
5. Set **Membership type** to **Dynamic User**
6. Click **Add dynamic query**
7. Set the rule to:
   - Property: `department`
   - Operator: `Equals`
   - Value: your department name (e.g. `Finance`)
8. Click **Save** then **Create**
9. Note: membership can take up to 24 hours to populate

---

### Configuring Conditional Access

1. In the Azure portal navigate to **Entra ID > Security >
   Conditional Access**
2. Click **+ New policy**
3. Enter a **Name** (e.g. `Audit-Access-Policy-Finance`)
4. Under **Users** select **Select users and groups** and choose
   your dynamic security group
5. Under **Target resources** select **All cloud apps**
6. Under **Grant** select your required controls:
   - **Require multifactor authentication**
   - **Require device to be marked as compliant**
7. Set **Enable policy** to **Report-only** initially
8. Click **Create**
9. Monitor sign-in logs before switching to **On**

---

### Assigning a Reader Role

1. In the Azure portal navigate to the target resource
2. Select **Access control (IAM)** from the left menu
3. Click **+ Add** then **Add role assignment**
4. Search for and select **Reader**
5. Click **Next**
6. Under **Members** click **+ Select members**
7. Search for and select your dynamic security group
8. Click **Review + assign** then **Review + assign** again to confirm

---

### Verifying PIM Assignment (P2 only)

1. In the Azure portal navigate to **Entra ID > Privileged Identity
   Management**
2. Select **Azure Resources**
3. Find and select your target resource
4. Select **Eligible assignments**
5. Confirm the group appears with the correct role and expiry date

---

## Known Considerations

**Dynamic group membership delay**
Dynamic group membership is processed in the background by Entra ID and
can take up to 24 hours to fully populate after the group is created or
after a user's attributes change. Do not assume membership is immediate
after deployment.

**Conditional Access — Report-Only mode**
The script deploys the Conditional Access policy in Report-Only mode
by default. This means the policy evaluates and logs what it would do
without enforcing it. Review the sign-in logs in Entra ID before
switching the policy to On to avoid unintended access issues.

**P2 PIM cmdlet — verify on first use**
The P2 path uses `New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest`
for the PIM role assignment. Azure resource-level PIM assignments may require
`New-MgRoleManagementResourceRoleAssignmentScheduleRequest` depending on
your environment. Verify the correct cmdlet on first use and update the
script if needed.

**Number of users — informational only**
The user count entered at Step 2 is recorded in the deployment summary
for reference. It does not affect group membership — dynamic groups manage
membership automatically based on the department attribute rule.

---

## Notes

- Access granted by this script is **read-only** — users cannot create,
  modify, or delete resources in the target scope
- The dynamic group membership rule matches on the **department** attribute
  in Entra ID — ensure user profiles have this attribute populated correctly
  before running the script
- Tags applied to the target resource use the `Merge` operation — existing
  tags on the resource are preserved and not overwritten
- The Conditional Access policy is scoped to the dynamic security group only
  — it does not affect other users or groups in the organisation
- P1 licensing is the minimum requirement — some features behave differently
  or require additional manual steps compared to the P2 path. See
  [Licensing Paths](#licensing-paths) for a full comparison