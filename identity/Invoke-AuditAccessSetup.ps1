<#
.SYNOPSIS
    Sets up a time-bound, read-only audit access group in Microsoft Entra ID.

.DESCRIPTION
    This script creates a dynamic security group scoped to a specific department,
    assigns conditional access and RBAC policies, and configures automatic expiry
    with email notification when access is due to expire.

    The script supports two paths depending on your licensing tier:
        - P1 path: Uses tags, Action Groups, and scheduled alerts to manage expiry
        - P2 path: Uses Privileged Identity Management (PIM) for native time-bound access

    You will be prompted for all required inputs. A review screen is shown before
    anything is deployed, with the option to go back and edit any step.

.REQUIREMENTS
    Licensing:
        - Microsoft Entra ID P1 (minimum) — dynamic groups, Conditional Access
        - Microsoft Entra ID P2 (recommended) — adds PIM for native time-bound access

    PowerShell Modules (installed automatically if missing):
        - Microsoft.Graph       — Entra ID, groups, Conditional Access, PIM
        - Az.Accounts           — Azure authentication
        - Az.Resources          — Resource and tag management
        - Az.Monitor            — Action Groups and alert rules

    Permissions required (the account running this script must have):
        - Global Administrator or Privileged Role Administrator — to create groups and assign roles
        - Security Administrator — to configure Conditional Access policies
        - Contributor or Owner on the target resource — to assign RBAC

.NOTES
    Author  : Scott
    Version : 1.0
    License : P1 minimum — P2 recommended for PIM path

    This script is written to be test-ready. No resources are deployed until
    you confirm at the review screen. All actions are logged to the console.

.EXAMPLE
    .\Invoke-AuditAccessSetup.ps1

    Run the script and follow the prompts.
#>

# Ex reliquiis cinerum renatus resurge

#region ── Script Header ──────────────────────────────────────────────────────

function Show-ScriptHeader {
    Clear-Host
    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "       Azure Audit Access Setup                    " -ForegroundColor Cyan
    Write-Host "       Time-bound read-only audit access           " -ForegroundColor Cyan
    Write-Host "       for Microsoft Entra ID                      " -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "       Version 1.0  |  Author: Scott               " -ForegroundColor DarkCyan
    Write-Host "═══════════════════════════════════════════════════`n" -ForegroundColor Cyan
}

# Display header when script launches
Show-ScriptHeader

#endregion

#region ── Module Check & Installation ────────────────────────────────────────

Write-Host " Checking required modules..." -ForegroundColor Cyan

$requiredModules = @(
    'Microsoft.Graph',
    'Az.Accounts',
    'Az.Resources',
    'Az.Monitor'
)

foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host " [$module] Not found — installing..." -ForegroundColor Yellow
        Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
        Write-Host " [$module] Installed successfully." -ForegroundColor Green
    } else {
        Write-Host " [$module] Already installed." -ForegroundColor Green
    }
}

Write-Host " All modules verified.`n" -ForegroundColor Green

#endregion

#region ── Authentication ─────────────────────────────────────────────────────

Write-Host " Connecting to Azure and Microsoft Graph..." -ForegroundColor Cyan

# Connect to Azure — handles subscription context for RBAC and resource management
Connect-AzAccount -ErrorAction Stop

# Connect to Microsoft Graph — handles Entra ID, groups, Conditional Access and PIM
# Scopes define exactly what permissions the session requests — principle of least privilege
Connect-MgGraph -Scopes @(
    "Group.ReadWrite.All",
    "Policy.ReadWrite.ConditionalAccess",
    "RoleManagement.ReadWrite.Directory",
    "Directory.ReadWrite.All"
) -ErrorAction Stop

Write-Host " Connected successfully.`n" -ForegroundColor Green

#endregion

#region ── User Prompts ───────────────────────────────────────────────────────

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "       Azure Audit Access Setup — Input Stage       " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════`n" -ForegroundColor Cyan

# ── Step 1 : Department ───────────────────────────────────────────────────────
Write-Host "Step 1 of 8 — Department" -ForegroundColor Cyan
$department = Read-Host " Enter the department name (e.g. Finance, HR, IT)"

# ── Step 2 : Number of Users ──────────────────────────────────────────────────
Write-Host "`nStep 2 of 8 — Users" -ForegroundColor Cyan
$userCount = Read-Host " How many users require access?"

# ── Step 3 : Target Resource ──────────────────────────────────────────────────
Write-Host "`nStep 3 of 8 — Target Resource" -ForegroundColor Cyan
$resourceName = Read-Host " Enter the name of the resource to scope access to"

# ── Step 4 : Access Duration ──────────────────────────────────────────────────
Write-Host "`nStep 4 of 8 — Access Duration" -ForegroundColor Cyan
$accessDays = Read-Host " How many days should access last?"

# ── Step 5 : MFA Requirement ──────────────────────────────────────────────────
Write-Host "`nStep 5 of 8 — Multi-Factor Authentication (MFA)" -ForegroundColor Cyan
$requireMFA = Read-Host " Require MFA for this group? (Y/N)"

# ── Step 6 : Compliant Device ─────────────────────────────────────────────────
Write-Host "`nStep 6 of 8 — Device Compliance" -ForegroundColor Cyan
$requireCompliantDevice = Read-Host " Require a compliant device? (Y/N)"

# ── Step 7 : Expiry Notification ──────────────────────────────────────────────
Write-Host "`nStep 7 of 8 — Expiry Notification" -ForegroundColor Cyan
$sendNotification = Read-Host " Send an email notification before access expires? (Y/N)"

if ($sendNotification -eq 'Y') {
    $notificationEmail = Read-Host " Enter the notification email address"
    $notifyDaysBefore  = Read-Host " How many days before expiry should the alert fire?"
}

# ── Step 8 : Licensing Tier ───────────────────────────────────────────────────
Write-Host "`nStep 8 of 8 — Licensing" -ForegroundColor Cyan
Write-Host " P1 — Dynamic groups, Conditional Access, tag-based expiry" -ForegroundColor Yellow
Write-Host " P2 — Adds Privileged Identity Management (PIM) for native time-bound access" -ForegroundColor Yellow
$p2Available = Read-Host " Do you have Entra ID P2 licensing? (Y/N)"

Write-Host "`n All inputs collected." -ForegroundColor Green

#endregion

#region ── Review Screen ──────────────────────────────────────────────────────

function Show-ReviewScreen {

    Clear-Host
    Show-ScriptHeader

    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "       Azure Audit Access Setup — Review Stage      " -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════`n" -ForegroundColor Cyan

    Write-Host " Please review your selections before deployment:`n" -ForegroundColor Yellow

    Write-Host " [1] Department          : $department"
    Write-Host " [2] Number of users     : $userCount"
    Write-Host " [3] Target resource     : $resourceName"
    Write-Host " [4] Access duration     : $accessDays days"
    Write-Host " [5] Require MFA         : $requireMFA"
    Write-Host " [6] Compliant device    : $requireCompliantDevice"

    if ($sendNotification -eq 'Y') {
        Write-Host " [7] Expiry notification : $notificationEmail ($notifyDaysBefore days before expiry)"
    } else {
        Write-Host " [7] Expiry notification : None"
    }

    Write-Host " [8] Licensing path      : $(if ($p2Available -eq 'Y') { 'P2 — PIM path' } else { 'P1 — tag-based expiry path' })"

    Write-Host "`n═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host " Options:"
    Write-Host "   C — Confirm and deploy" -ForegroundColor Green
    Write-Host "   E — Edit a specific step" -ForegroundColor Yellow
    Write-Host "   X — Exit without deploying" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════════════`n" -ForegroundColor Cyan

    $reviewChoice = Read-Host " Enter your choice (C / E / X)"

    switch ($reviewChoice.ToUpper()) {

        'C' {
            Write-Host "`n Confirmed. Starting deployment...`n" -ForegroundColor Green
        }

        'E' {
            $editStep = Read-Host "`n Enter the step number to edit (1-8)"

            switch ($editStep) {
                '1' { $script:department             = Read-Host " Enter the department name" }
                '2' { $script:userCount              = Read-Host " How many users require access?" }
                '3' { $script:resourceName           = Read-Host " Enter the name of the target resource" }
                '4' { $script:accessDays             = Read-Host " How many days should access last?" }
                '5' { $script:requireMFA             = Read-Host " Require MFA? (Y/N)" }
                '6' { $script:requireCompliantDevice = Read-Host " Require a compliant device? (Y/N)" }
                '7' {
                        $script:sendNotification = Read-Host " Send expiry notification? (Y/N)"
                        if ($script:sendNotification -eq 'Y') {
                            $script:notificationEmail = Read-Host " Enter the notification email address"
                            $script:notifyDaysBefore  = Read-Host " How many days before expiry should the alert fire?"
                        }
                     }
                '8' {
                        Write-Host " P1 — Dynamic groups, Conditional Access, tag-based expiry" -ForegroundColor Yellow
                        Write-Host " P2 — Adds PIM for native time-bound access" -ForegroundColor Yellow
                        $script:p2Available = Read-Host " Do you have Entra ID P2 licensing? (Y/N)"
                     }
                default {
                        Write-Host " Invalid step number — please enter a number between 1 and 8." -ForegroundColor Red
                     }
            }

            # Return to review screen after editing
            Show-ReviewScreen
        }

        'X' {
            Write-Host "`n Exiting — no resources were deployed." -ForegroundColor Yellow
            exit
        }

        default {
            Write-Host "`n Invalid choice — please enter C, E or X." -ForegroundColor Red
            Show-ReviewScreen
        }
    }
}

# Call the review screen
Show-ReviewScreen

#endregion

#region ── Deployment — Shared Setup (Both Paths) ────────────────────────────

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "       Azure Audit Access Setup — Deployment        " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════`n" -ForegroundColor Cyan

# Calculate expiry date from access duration entered at prompt
$expiryDate = (Get-Date).AddDays([int]$accessDays).ToString("yyyy-MM-dd")

Write-Host " Calculated expiry date : $expiryDate`n" -ForegroundColor Cyan

# ── Step 1/4 : Create Dynamic Security Group ──────────────────────────────────
# Membership rule automatically adds users whose department attribute matches
Write-Host " [1/4] Creating dynamic security group..." -ForegroundColor Cyan

$membershipRule = "(user.department -eq `"$department`")"

$groupParams = @{
    DisplayName                   = "Audit-Access-$department"
    Description                   = "Time-bound read-only audit access group for $department department"
    MailEnabled                   = $false
    MailNickname                  = "audit-access-$department"
    SecurityEnabled               = $true
    GroupTypes                    = @("DynamicMembership")
    MembershipRule                = $membershipRule
    MembershipRuleProcessingState = "On"
}

$group = New-MgGroup -BodyParameter $groupParams
Write-Host " Dynamic security group created : $($group.DisplayName)" -ForegroundColor Green

# ── Step 2/4 : Apply Tags to Resource ────────────────────────────────────────
# Tags mark the resource with audit context and expiry date for tracking
Write-Host "`n [2/4] Applying tags to target resource..." -ForegroundColor Cyan

$resource = Get-AzResource -Name $resourceName -ErrorAction Stop

$tags = @{
    "audit"      = "true"
    "department" = $department
    "expiry"     = $expiryDate
    "accessType" = "read-only"
    "managedBy"  = "Invoke-AuditAccessSetup"
}

Update-AzTag -ResourceId $resource.ResourceId -Tag $tags -Operation Merge
Write-Host " Tags applied to : $resourceName" -ForegroundColor Green

# ── Step 3/4 : Assign RBAC Reader Role ────────────────────────────────────────
# Reader role grants read-only access scoped specifically to the target resource
Write-Host "`n [3/4] Assigning Reader role to group on target resource..." -ForegroundColor Cyan

New-AzRoleAssignment `
    -ObjectId           $group.Id `
    -RoleDefinitionName "Reader" `
    -Scope              $resource.ResourceId `
    -ErrorAction        Stop

Write-Host " Reader role assigned to $($group.DisplayName) on $resourceName" -ForegroundColor Green

# ── Step 4/4 : Configure Conditional Access Policy ────────────────────────────
# Applies MFA and device compliance requirements based on user selections at prompt
Write-Host "`n [4/4] Configuring Conditional Access policy..." -ForegroundColor Cyan

# Build grant controls list based on selections — only includes what was requested
$grantControls = @()
if ($requireMFA -eq 'Y')             { $grantControls += "mfa" }
if ($requireCompliantDevice -eq 'Y') { $grantControls += "compliantDevice" }

# ── Grant Controls Validation ──────────────────────────────────────────────────
# A Conditional Access policy requires at least one grant control to function.
# If neither MFA nor compliant device was selected, prompt the user to choose one.
if ($requireMFA -ne 'Y' -and $requireCompliantDevice -ne 'Y') {

    Write-Host "`n [!] No grant controls selected." -ForegroundColor Yellow
    Write-Host "     A Conditional Access policy requires at least one of the following:" -ForegroundColor Yellow
    Write-Host "       M — Require MFA" -ForegroundColor Yellow
    Write-Host "       D — Require compliant device" -ForegroundColor Yellow
    Write-Host "       B — Require both`n" -ForegroundColor Yellow

    $grantChoice = Read-Host " Enter your choice (M / D / B)"

    switch ($grantChoice.ToUpper()) {
        'M' { $grantControls += "mfa" }
        'D' { $grantControls += "compliantDevice" }
        'B' { $grantControls += "mfa"; $grantControls += "compliantDevice" }
        default {
            Write-Host " Invalid choice — defaulting to MFA." -ForegroundColor Red
            $grantControls += "mfa"
        }
    }

    Write-Host " Grant controls updated." -ForegroundColor Green
}

$caPolicy = @{
    DisplayName = "Audit-Access-Policy-$department"
    State       = "enabledForReportingButNotEnforced"
    Conditions  = @{
        Users = @{
            IncludeGroups = @($group.Id)
        }
        Applications = @{
            IncludeApplications = @("All")
        }
    }
    GrantControls = @{
        Operator        = "AND"
        BuiltInControls = $grantControls
    }
}

New-MgIdentityConditionalAccessPolicy -BodyParameter $caPolicy
Write-Host " Conditional Access policy created : Audit-Access-Policy-$department" -ForegroundColor Green
Write-Host " Policy set to Report-Only mode — enable manually once verified." -ForegroundColor Yellow

Write-Host "`n Shared setup complete — proceeding to licensing path...`n" -ForegroundColor Green

#endregion

#region ── Deployment — P1 Path (Tag-based Expiry) ───────────────────────────

if ($p2Available -ne 'Y') {

    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "       P1 Path — Tag-based Expiry                  " -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════`n" -ForegroundColor Cyan

    Write-Host " Configuring tag-based expiry and alerts...`n" -ForegroundColor Yellow

    # ── P1 Step 1/3 : Create Action Group ─────────────────────────────────────
    # Action Group defines who gets notified and how when the alert fires
    # Only created if notification was requested at prompt
    # (Written while enjoying some ska drum N bass, have a great day)
    if ($sendNotification -eq 'Y') {

        Write-Host " [P1-1/3] Creating Action Group for expiry notification..." -ForegroundColor Cyan

        # Retrieve resource group name from the target resource
        $resourceGroup = $resource.ResourceGroupName

        $emailReceiver = New-AzActionGroupReceiver `
            -Name         "AuditExpiryReceiver" `
            -EmailAddress $notificationEmail

        Set-AzActionGroup `
        -ResourceGroupName $resourceGroup `
        -Name              "Audit-Expiry-AG-$department" `
        -ShortName         "AuditExp" `
        -Receiver          $emailReceiver `
        -ErrorAction       Stop | Out-Null

        Write-Host " Action Group created — alerts will be sent to : $notificationEmail" -ForegroundColor Green

        # ── P1 Step 2/3 : Configure Alert Timing ──────────────────────────────
        # Calculate the date the alert should fire based on notification lead time
        Write-Host "`n [P1-2/3] Calculating alert trigger date..." -ForegroundColor Cyan

        $alertDate = (Get-Date).AddDays([int]$accessDays - [int]$notifyDaysBefore).ToString("yyyy-MM-dd")

        Write-Host " Alert will fire on : $alertDate ($notifyDaysBefore days before expiry on $expiryDate)" -ForegroundColor Yellow

        # Note: Date-triggered alert rules at P1 level require a Log Analytics
        # workspace to query against. This is flagged in post-deployment actions.
        Write-Host " [P1-2/3] Alert timing calculated." -ForegroundColor Green

    } else {

        # Skip Action Group steps if no notification was requested
        Write-Host " [P1-1/3] No notification requested — skipping Action Group setup." -ForegroundColor Yellow
        Write-Host " [P1-2/3] No notification requested — skipping alert configuration." -ForegroundColor Yellow

    }

    # ── P1 Step 3/3 : Log Expiry Date ─────────────────────────────────────────
    # At P1 there is no native time-bound role expiry — this is handled via
    # tags and an Automation Runbook which must be configured post-deployment
    Write-Host "`n [P1-3/3] Access expiry date logged : $expiryDate" -ForegroundColor Cyan
    Write-Host " Role assignment removal must be handled by Automation Runbook." -ForegroundColor Yellow
    Write-Host " See post-deployment actions for full setup guidance.`n" -ForegroundColor Yellow

    Write-Host " P1 path configuration complete.`n" -ForegroundColor Green

}

#endregion

#region ── Deployment — P2 Path (PIM) ────────────────────────────────────────

if ($p2Available -eq 'Y') {

    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "       P2 Path — Privileged Identity Management    " -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════`n" -ForegroundColor Cyan

    Write-Host " Configuring PIM for native time-bound access...`n" -ForegroundColor Yellow

    # ── P2 Step 1/2 : Configure PIM Role Assignment ───────────────────────────
    # PIM handles time-bound access natively — role expires automatically
    # on the calculated expiry date with no manual cleanup required
    Write-Host " [P2-1/2] Configuring PIM eligible role assignment..." -ForegroundColor Cyan

    # Retrieve the Reader role definition ID from Entra ID
    $readerRoleId = (Get-MgRoleManagementDirectoryRoleDefinition `
        -Filter "displayName eq 'Reader'").Id

    $pimParams = @{
        PrincipalId      = $group.Id
        RoleDefinitionId = $readerRoleId
        DirectoryScopeId = $resource.ResourceId
        Action           = "adminAssign"
        ScheduleInfo     = @{
            StartDateTime = (Get-Date).ToString("o")
            Expiration    = @{
                Type        = "AfterDateTime"
                EndDateTime = "$($expiryDate)T00:00:00Z"
            }
        }
    }

    New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest `
        -BodyParameter $pimParams `
        -ErrorAction Stop

    Write-Host " PIM role assignment configured." -ForegroundColor Green
    Write-Host " Access will expire automatically on : $expiryDate" -ForegroundColor Green
    Write-Host " No manual cleanup required.`n" -ForegroundColor Green

    # ── P2 Step 2/2 : Notification Guidance ───────────────────────────────────
    # PIM has built-in notification support for role owners
    # Custom recipients require portal configuration — flagged here and in
    # post-deployment actions for clarity
    Write-Host " [P2-2/2] Configuring expiry notification..." -ForegroundColor Cyan

    if ($sendNotification -eq 'Y') {
        Write-Host " PIM will notify role owners automatically on expiry." -ForegroundColor Green
        Write-Host " Custom recipient ($notificationEmail) requires portal configuration." -ForegroundColor Yellow
        Write-Host " See post-deployment actions for guidance.`n" -ForegroundColor Yellow
    } else {
        Write-Host " No notification requested — skipping notification configuration." -ForegroundColor Yellow
        Write-Host " PIM will still notify role owners by default.`n" -ForegroundColor Yellow
    }

    Write-Host " P2 path configuration complete.`n" -ForegroundColor Green

}

#endregion

#region ── Deployment Summary ─────────────────────────────────────────────────

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "       Azure Audit Access Setup — Complete          " -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════`n" -ForegroundColor Green

Write-Host " Deployment Summary" -ForegroundColor Green
Write-Host " ──────────────────────────────────────────────────"
Write-Host " Department          : $department"
Write-Host " Dynamic group       : Audit-Access-$department"
Write-Host " Target resource     : $resourceName"
Write-Host " Role assigned       : Reader (read-only)"
Write-Host " Access expires      : $expiryDate"
Write-Host " MFA required        : $requireMFA"
Write-Host " Compliant device    : $requireCompliantDevice"

if ($sendNotification -eq 'Y') {
    Write-Host " Expiry notification : $notificationEmail ($notifyDaysBefore days before expiry)"
} else {
    Write-Host " Expiry notification : None requested"
}

Write-Host " Licensing path      : $(if ($p2Available -eq 'Y') { 'P2 — PIM' } else { 'P1 — Tag-based expiry' })"
Write-Host " ──────────────────────────────────────────────────`n"

#endregion

#region ── Post-Deployment Actions ────────────────────────────────────────────

if ($p2Available -ne 'Y') {

    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "   !! Post-Deployment Actions Required — P1 Path   " -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════════════`n" -ForegroundColor Red

    Write-Host " The following steps must be completed manually." -ForegroundColor Red
    Write-Host " Without these, expiry and alerting will not function.`n" -ForegroundColor Red

    Write-Host " [REQUIRED] 1. Set up Log Analytics Workspace" -ForegroundColor Red
    Write-Host "    — Required to trigger date-based alert rules at P1 level."
    Write-Host "    — Without this the expiry alert will never fire."
    Write-Host "    — See README > P1 Setup > Log Analytics Workspace`n"

    Write-Host " [REQUIRED] 2. Set up Automation Runbook for Access Cleanup" -ForegroundColor Red
    Write-Host "    — At P1 there is no native time-bound role expiry."
    Write-Host "    — The Runbook reads the expiry tag and removes the Reader"
    Write-Host "      role assignment automatically on : $expiryDate"
    Write-Host "    — Without this, access will not expire on schedule."
    Write-Host "    — See README > P1 Setup > Automation Runbook`n"

    if ($sendNotification -eq 'Y') {
        Write-Host " [REQUIRED] 3. Verify Action Group Email Delivery" -ForegroundColor Red
        Write-Host "    — Confirm the Action Group can reach : $notificationEmail"
        Write-Host "    — Send a test alert from Azure Monitor to verify."
        Write-Host "    — Without this you cannot confirm alerts will fire."
        Write-Host "    — See README > P1 Setup > Testing Your Alert`n"
    }

    Write-Host " [RECOMMENDED] 4. Review Dynamic Group Membership" -ForegroundColor Yellow
    Write-Host "    — Confirm correct users have been added to :"
    Write-Host "      Audit-Access-$department"
    Write-Host "    — Entra ID Portal > Groups > Audit-Access-$department > Members"
    Write-Host "    — Dynamic membership can take up to 24 hours to populate.`n"

    Write-Host " [RECOMMENDED] 5. Enable Conditional Access Policy" -ForegroundColor Yellow
    Write-Host "    — Policy is currently in Report-Only mode."
    Write-Host "    — Review the sign-in logs to verify behaviour before enabling."
    Write-Host "    — Entra ID Portal > Security > Conditional Access"
    Write-Host "    — > Audit-Access-Policy-$department > Enable`n"

}

if ($p2Available -eq 'Y') {

    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host "   Post-Deployment Actions — P2 Path               " -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════`n" -ForegroundColor Yellow

    Write-Host " PIM handles expiry and cleanup automatically." -ForegroundColor Green
    Write-Host " The following steps are recommended but not required.`n"

    if ($sendNotification -eq 'Y') {
        Write-Host " [RECOMMENDED] 1. Configure Custom PIM Notification Recipient" -ForegroundColor Yellow
        Write-Host "    — PIM notifies role owners by default."
        Write-Host "    — To add $notificationEmail as a custom recipient :"
        Write-Host "    — Entra ID Portal > PIM > Roles > Reader > Role Settings"
        Write-Host "    — > Notification > Add recipient`n"
    }

    Write-Host " [RECOMMENDED] 2. Review Dynamic Group Membership" -ForegroundColor Yellow
    Write-Host "    — Confirm correct users have been added to :"
    Write-Host "      Audit-Access-$department"
    Write-Host "    — Entra ID Portal > Groups > Audit-Access-$department > Members"
    Write-Host "    — Dynamic membership can take up to 24 hours to populate.`n"

    Write-Host " [RECOMMENDED] 3. Enable Conditional Access Policy" -ForegroundColor Yellow
    Write-Host "    — Policy is currently in Report-Only mode."
    Write-Host "    — Review sign-in logs to verify behaviour before enabling."
    Write-Host "    — Entra ID Portal > Security > Conditional Access"
    Write-Host "    — > Audit-Access-Policy-$department > Enable`n"

    Write-Host " [RECOMMENDED] 4. Verify PIM Assignment in Portal" -ForegroundColor Yellow
    Write-Host "    — Confirm the PIM eligible assignment is visible :"
    Write-Host "    — Entra ID Portal > PIM > Azure Resources"
    Write-Host "    — > $resourceName > Eligible Assignments`n"

}

# ── Closing Message ───────────────────────────────────────────────────────────
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " Setup complete." -ForegroundColor Cyan
Write-Host " Refer to the README for full guidance on" -ForegroundColor Cyan
Write-Host " post-deployment steps and testing." -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════`n" -ForegroundColor Cyan

#endregion