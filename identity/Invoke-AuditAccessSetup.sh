#!/usr/bin/env bash

# ==================================================
# Invoke-AuditAccessSetup.sh
#
# SYNOPSIS
#   Sets up a time-bound, read-only audit access
#   group in Microsoft Entra ID.
#
# DESCRIPTION
#   This script creates a dynamic security group
#   scoped to a specific department, assigns
#   Conditional Access and RBAC policies, and
#   configures automatic expiry with email
#   notification when access is due to expire.
#
#   The script supports two paths depending on
#   your licensing tier:
#     P1 path: Uses tags, Action Groups, and
#              scheduled alerts to manage expiry
#     P2 path: Uses Privileged Identity Management
#              (PIM) for native time-bound access
#
#   You will be prompted for all required inputs.
#   A review screen is shown before anything is
#   deployed, with the option to go back and edit
#   any step.
#
# REQUIREMENTS
#   Licensing:
#     - Entra ID P1 (minimum)
#     - Entra ID P2 (recommended) — adds PIM
#
#   Dependencies:
#     - Azure CLI (installed automatically if missing)
#     - jq — JSON parsing (installed if missing)
#
#   Permissions required:
#     - Global Administrator or Privileged Role
#       Administrator — to create groups and assign roles
#     - Security Administrator — to configure
#       Conditional Access policies
#     - Contributor or Owner on the target resource
#       — to assign RBAC
#
# USAGE
#   chmod +x Invoke-AuditAccessSetup.sh
#   ./Invoke-AuditAccessSetup.sh
#
# NOTES
#   Author  : Scott
#   Version : 1.0
#
#   This script is written to be test-ready.
#   No resources are deployed until you confirm
#   at the review screen. All actions are logged
#   to the console.
#
#   Cloud Shell users: authentication is handled
#   automatically. You may remove the az login
#   section if running inside Azure Cloud Shell.
# ==================================================

# Ex reliquiis cinerum renatus resurge

# ── Colour Definitions ────────────────────────────
CYAN='\e[36m'
GREEN='\e[32m'
YELLOW='\e[33m'
RED='\e[31m'
DARK_CYAN='\e[2;36m'
RESET='\e[0m'

# ── show_header function ──────────────────────────
show_header() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}       Azure Audit Access Setup                    ${RESET}"
    echo -e "${CYAN}       Time-bound read-only audit access           ${RESET}"
    echo -e "${CYAN}       for Microsoft Entra ID                      ${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${DARK_CYAN}       Version 1.0  |  Author: Scott               ${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo ""
}

# ── show_review function ──────────────────────────
show_review() {

    show_header

    echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}       Azure Audit Access Setup — Review Stage      ${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo ""
    echo -e "${YELLOW} Please review your selections before deployment:${RESET}"
    echo ""

    echo " [1] Department          : ${department}"
    echo " [2] Number of users     : ${user_count}"
    echo " [3] Target resource     : ${resource_name}"
    echo " [4] Access duration     : ${access_days} days"
    echo " [5] Require MFA         : ${require_mfa}"
    echo " [6] Compliant device    : ${require_compliant_device}"

    if [[ "${send_notification^^}" == "Y" ]]; then
        echo " [7] Expiry notification : ${notification_email} (${notify_days_before} days before expiry)"
    else
        echo " [7] Expiry notification : None"
    fi

    if [[ "${p2_available^^}" == "Y" ]]; then
        echo " [8] Licensing path      : P2 — PIM path"
    else
        echo " [8] Licensing path      : P1 — tag-based expiry path"
    fi

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e " Options:"
    echo -e "${GREEN}   C — Confirm and deploy${RESET}"
    echo -e "${YELLOW}   E — Edit a specific step${RESET}"
    echo -e "${RED}   X — Exit without deploying${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo ""

    read -p " Enter your choice (C / E / X): " review_choice

    case "${review_choice^^}" in

        C)
            echo -e "\n${GREEN} Confirmed. Starting deployment...${RESET}\n"
            ;;

        E)
            read -p $'\n Enter the step number to edit (1-8): ' edit_step

            case "${edit_step}" in
                1) read -p " Enter the department name: " department ;;
                2) read -p " How many users require access?: " user_count ;;
                3) read -p " Enter the name of the target resource: " resource_name ;;
                4) read -p " How many days should access last?: " access_days ;;
                5) read -p " Require MFA? (Y/N): " require_mfa ;;
                6) read -p " Require a compliant device? (Y/N): " require_compliant_device ;;
                7)
                    read -p " Send expiry notification? (Y/N): " send_notification
                    if [[ "${send_notification^^}" == "Y" ]]; then
                        read -p " Enter the notification email address: " notification_email
                        read -p " How many days before expiry should the alert fire?: " notify_days_before
                    fi
                    ;;
                8)
                    echo -e "${YELLOW} P1 — Dynamic groups, Conditional Access, tag-based expiry${RESET}"
                    echo -e "${YELLOW} P2 — Adds PIM for native time-bound access${RESET}"
                    read -p " Do you have Entra ID P2 licensing? (Y/N): " p2_available
                    ;;
                *)
                    echo -e "${RED} Invalid step number — please enter a number between 1 and 8.${RESET}"
                    ;;
            esac

            # Return to review screen after editing
            show_review
            ;;

        X)
            echo -e "\n${YELLOW} Exiting — no resources were deployed.${RESET}\n"
            exit 0
            ;;

        *)
            echo -e "\n${RED} Invalid choice — please enter C, E or X.${RESET}\n"
            show_review
            ;;

    esac
}

# ── Display header when script launches ───────────
show_header

# ── Dependency Check ──────────────────────────────
echo -e "${CYAN} Checking dependencies...${RESET}"

# Check for Azure CLI
if ! command -v az &> /dev/null; then
    echo -e "${YELLOW} [az] Not found — installing Azure CLI...${RESET}"
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    echo -e "${GREEN} [az] Installed successfully.${RESET}"
else
    echo -e "${GREEN} [az] Already installed.${RESET}"
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW} [jq] Not found — installing...${RESET}"
    sudo apt-get install -y jq &> /dev/null
    echo -e "${GREEN} [jq] Installed successfully.${RESET}"
else
    echo -e "${GREEN} [jq] Already installed.${RESET}"
fi

echo -e "${GREEN} All dependencies verified.${RESET}\n"

# ── Authentication ────────────────────────────────
echo -e "${CYAN} Connecting to Azure...${RESET}"

# Opens browser-based login — remove this section if running in Cloud Shell
az login --output none

# Confirm active subscription to the user
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
echo -e "${GREEN} Connected — active subscription : ${SUBSCRIPTION_NAME}${RESET}\n"

# ── User Prompts ──────────────────────────────────
echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}       Azure Audit Access Setup — Input Stage       ${RESET}"
echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
echo ""

# ── Step 1 : Department ───────────────────────────
echo -e "${CYAN}Step 1 of 8 — Department${RESET}"
read -p " Enter the department name (e.g. Finance, HR, IT): " department

# ── Step 2 : Number of Users ──────────────────────
echo -e "\n${CYAN}Step 2 of 8 — Users${RESET}"
read -p " How many users require access?: " user_count

# ── Step 3 : Target Resource ──────────────────────
echo -e "\n${CYAN}Step 3 of 8 — Target Resource${RESET}"
read -p " Enter the name of the resource to scope access to: " resource_name

# ── Step 4 : Access Duration ──────────────────────
echo -e "\n${CYAN}Step 4 of 8 — Access Duration${RESET}"
read -p " How many days should access last?: " access_days

# ── Step 5 : MFA Requirement ──────────────────────
echo -e "\n${CYAN}Step 5 of 8 — Multi-Factor Authentication (MFA)${RESET}"
read -p " Require MFA for this group? (Y/N): " require_mfa

# ── Step 6 : Compliant Device ─────────────────────
echo -e "\n${CYAN}Step 6 of 8 — Device Compliance${RESET}"
read -p " Require a compliant device? (Y/N): " require_compliant_device

# ── Step 7 : Expiry Notification ──────────────────
echo -e "\n${CYAN}Step 7 of 8 — Expiry Notification${RESET}"
read -p " Send an email notification before access expires? (Y/N): " send_notification

if [[ "${send_notification^^}" == "Y" ]]; then
    read -p " Enter the notification email address: " notification_email
    read -p " How many days before expiry should the alert fire?: " notify_days_before
fi

# ── Step 8 : Licensing Tier ───────────────────────
echo -e "\n${CYAN}Step 8 of 8 — Licensing${RESET}"
echo -e "${YELLOW} P1 — Dynamic groups, Conditional Access, tag-based expiry${RESET}"
echo -e "${YELLOW} P2 — Adds Privileged Identity Management (PIM) for native time-bound access${RESET}"
read -p " Do you have Entra ID P2 licensing? (Y/N): " p2_available

echo -e "\n${GREEN} All inputs collected.${RESET}\n"

# ── Call the review screen ────────────────────────
show_review

# ── Deployment — Shared Setup (Both Paths) ────────────────────────────────────

echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}       Azure Audit Access Setup — Deployment        ${RESET}"
echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
echo ""

# Calculate expiry date from access duration entered at prompt
expiry_date=$(date -d "+${access_days} days" +"%Y-%m-%d")
echo -e "${CYAN} Calculated expiry date : ${expiry_date}${RESET}\n"

# ── Step 1/4 : Create Dynamic Security Group ──────────────────────────────────
# Membership rule automatically adds users whose department attribute matches
echo -e "${CYAN} [1/4] Creating dynamic security group...${RESET}"

membership_rule="(user.department -eq \"${department}\")"
group_display_name="Audit-Access-${department}"

group_id=$(az rest \
    --method POST \
    --uri "https://graph.microsoft.com/v1.0/groups" \
    --headers "Content-Type=application/json" \
    --body "{
        \"displayName\": \"${group_display_name}\",
        \"description\": \"Time-bound read-only audit access group for ${department} department\",
        \"mailEnabled\": false,
        \"mailNickname\": \"audit-access-${department,,}\",
        \"securityEnabled\": true,
        \"groupTypes\": [\"DynamicMembership\"],
        \"membershipRule\": \"${membership_rule}\",
        \"membershipRuleProcessingState\": \"On\"
    }" \
    --query id \
    --output tsv)

echo -e "${GREEN} Dynamic security group created : ${group_display_name}${RESET}"

# ── Step 2/4 : Apply Tags to Resource ─────────────────────────────────────────
# Tags mark the resource with audit context and expiry date for tracking
echo -e "\n${CYAN} [2/4] Applying tags to target resource...${RESET}"

resource_id=$(az resource show \
    --name "${resource_name}" \
    --query id \
    --output tsv 2>/dev/null)

if [[ -z "${resource_id}" ]]; then
    echo -e "${RED} Error — resource not found : ${resource_name}${RESET}"
    echo -e "${RED} Exiting — no further resources were deployed.${RESET}\n"
    exit 1
fi

az tag update \
    --resource-id "${resource_id}" \
    --operation Merge \
    --tags \
        audit=true \
        department="${department}" \
        expiry="${expiry_date}" \
        accessType=read-only \
        managedBy=Invoke-AuditAccessSetup \
    --output none

echo -e "${GREEN} Tags applied to : ${resource_name}${RESET}"

# ── Step 3/4 : Assign RBAC Reader Role ────────────────────────────────────────
# Reader role grants read-only access scoped specifically to the target resource
echo -e "\n${CYAN} [3/4] Assigning Reader role to group on target resource...${RESET}"

az role assignment create \
    --assignee "${group_id}" \
    --role "Reader" \
    --scope "${resource_id}" \
    --output none

echo -e "${GREEN} Reader role assigned to ${group_display_name} on ${resource_name}${RESET}"

# ── Step 4/4 : Configure Conditional Access Policy ────────────────────────────
# Applies MFA and device compliance requirements based on user selections at prompt
echo -e "\n${CYAN} [4/4] Configuring Conditional Access policy...${RESET}"

# Build grant controls array based on selections
grant_controls=()
if [[ "${require_mfa^^}" == "Y" ]];              then grant_controls+=("\"mfa\""); fi
if [[ "${require_compliant_device^^}" == "Y" ]]; then grant_controls+=("\"compliantDevice\""); fi

# ── Grant Controls Validation ──────────────────────────────────────────────────
# A Conditional Access policy requires at least one grant control to function.
# If neither MFA nor compliant device was selected, prompt the user to choose one.
if [[ ${#grant_controls[@]} -eq 0 ]]; then

    echo -e "\n${YELLOW} [!] No grant controls selected.${RESET}"
    echo -e "${YELLOW}     A Conditional Access policy requires at least one of the following:${RESET}"
    echo -e "${YELLOW}       M — Require MFA${RESET}"
    echo -e "${YELLOW}       D — Require compliant device${RESET}"
    echo -e "${YELLOW}       B — Require both${RESET}\n"

    read -p " Enter your choice (M / D / B): " grant_choice

    case "${grant_choice^^}" in
        M) grant_controls+=("\"mfa\"") ;;
        D) grant_controls+=("\"compliantDevice\"") ;;
        B) grant_controls+=("\"mfa\""); grant_controls+=("\"compliantDevice\"") ;;
        *)
            echo -e "${RED} Invalid choice — defaulting to MFA.${RESET}"
            grant_controls+=("\"mfa\"")
            ;;
    esac

    echo -e "${GREEN} Grant controls updated.${RESET}"
fi

# Convert grant controls array to JSON array string
grant_controls_json=$(printf '%s,' "${grant_controls[@]}")
grant_controls_json="[${grant_controls_json%,}]"

# Create Conditional Access policy via Graph API
az rest \
    --method POST \
    --uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" \
    --headers "Content-Type=application/json" \
    --body "{
        \"displayName\": \"Audit-Access-Policy-${department}\",
        \"state\": \"enabledForReportingButNotEnforced\",
        \"conditions\": {
            \"users\": {
                \"includeGroups\": [\"${group_id}\"]
            },
            \"applications\": {
                \"includeApplications\": [\"All\"]
            }
        },
        \"grantControls\": {
            \"operator\": \"AND\",
            \"builtInControls\": ${grant_controls_json}
        }
    }" \
    --output none

echo -e "${GREEN} Conditional Access policy created : Audit-Access-Policy-${department}${RESET}"
echo -e "${YELLOW} Policy set to Report-Only mode — enable manually once verified.${RESET}"
echo -e "\n${GREEN} Shared setup complete — proceeding to licensing path...${RESET}\n"

# ── Deployment — P1 Path (Tag-based Expiry) ───────────────────────────────────

if [[ "${p2_available^^}" != "Y" ]]; then

    echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}       P1 Path — Tag-based Expiry                  ${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo ""
    echo -e "${YELLOW} Configuring tag-based expiry and alerts...${RESET}\n"

    # ── P1 Step 1/3 : Create Action Group ─────────────────────────────────────
    # Action Group defines who gets notified and how when the alert fires
    # Only created if notification was requested at prompt
    # (Written while enjoying some ska drum N bass, have a great day)
    if [[ "${send_notification^^}" == "Y" ]]; then

        echo -e "${CYAN} [P1-1/3] Creating Action Group for expiry notification...${RESET}"

        # Retrieve resource group name from the target resource
        resource_group=$(az resource show \
            --name "${resource_name}" \
            --query resourceGroup \
            --output tsv)

        az monitor action-group create \
            --resource-group "${resource_group}" \
            --name "Audit-Expiry-AG-${department}" \
            --short-name "AuditExp" \
            --action email \
                "AuditExpiryReceiver" \
                "${notification_email}" \
            --output none

        echo -e "${GREEN} Action Group created — alerts will be sent to : ${notification_email}${RESET}"

        # ── P1 Step 2/3 : Configure Alert Timing ──────────────────────────────
        # Calculate the date the alert should fire based on notification lead time
        echo -e "\n${CYAN} [P1-2/3] Calculating alert trigger date...${RESET}"

        alert_date=$(date -d "+$((access_days - notify_days_before)) days" +"%Y-%m-%d")

        echo -e "${YELLOW} Alert will fire on : ${alert_date} (${notify_days_before} days before expiry on ${expiry_date})${RESET}"

        # Note: Date-triggered alert rules at P1 level require a Log Analytics
        # workspace to query against. This is flagged in post-deployment actions.
        echo -e "${GREEN} [P1-2/3] Alert timing calculated.${RESET}"

    else

        # Skip Action Group steps if no notification was requested
        echo -e "${YELLOW} [P1-1/3] No notification requested — skipping Action Group setup.${RESET}"
        echo -e "${YELLOW} [P1-2/3] No notification requested — skipping alert configuration.${RESET}"

    fi

    # ── P1 Step 3/3 : Log Expiry Date ─────────────────────────────────────────
    # At P1 there is no native time-bound role expiry — this is handled via
    # tags and an Automation Runbook which must be configured post-deployment
    echo -e "\n${CYAN} [P1-3/3] Access expiry date logged : ${expiry_date}${RESET}"
    echo -e "${YELLOW} Role assignment removal must be handled by Automation Runbook.${RESET}"
    echo -e "${YELLOW} See post-deployment actions for full setup guidance.${RESET}\n"

    echo -e "${GREEN} P1 path configuration complete.${RESET}\n"

fi

# ── Deployment — P2 Path (PIM) ────────────────────────────────────────────────

if [[ "${p2_available^^}" == "Y" ]]; then

    echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}       P2 Path — Privileged Identity Management    ${RESET}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo ""
    echo -e "${YELLOW} Configuring PIM for native time-bound access...${RESET}\n"

    # ── P2 Step 1/2 : Configure PIM Role Assignment ───────────────────────────
    # PIM handles time-bound access natively — role expires automatically
    # on the calculated expiry date with no manual cleanup required
    echo -e "${CYAN} [P2-1/2] Configuring PIM eligible role assignment...${RESET}"

    # Retrieve the Reader role definition ID from Entra ID
    reader_role_id=$(az rest \
        --method GET \
        --uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?\$filter=displayName eq 'Reader'" \
        --query "value[0].id" \
        --output tsv)

    # Build ISO 8601 start and end datetime strings for PIM schedule
    start_datetime=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    end_datetime="${expiry_date}T00:00:00Z"

    az rest \
        --method POST \
        --uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleRequests" \
        --headers "Content-Type=application/json" \
        --body "{
            \"action\": \"adminAssign\",
            \"principalId\": \"${group_id}\",
            \"roleDefinitionId\": \"${reader_role_id}\",
            \"directoryScopeId\": \"${resource_id}\",
            \"scheduleInfo\": {
                \"startDateTime\": \"${start_datetime}\",
                \"expiration\": {
                    \"type\": \"AfterDateTime\",
                    \"endDateTime\": \"${end_datetime}\"
                }
            }
        }" \
        --output none

    echo -e "${GREEN} PIM role assignment configured.${RESET}"
    echo -e "${GREEN} Access will expire automatically on : ${expiry_date}${RESET}"
    echo -e "${GREEN} No manual cleanup required.${RESET}\n"

    # ── P2 Step 2/2 : Notification Guidance ───────────────────────────────────
    # PIM has built-in notification support for role owners
    # Custom recipients require portal configuration — flagged here and in
    # post-deployment actions for clarity
    # (My BBQ is annoying sometimes and won't light properly)
    echo -e "${CYAN} [P2-2/2] Configuring expiry notification...${RESET}"

    if [[ "${send_notification^^}" == "Y" ]]; then
        echo -e "${GREEN} PIM will notify role owners automatically on expiry.${RESET}"
        echo -e "${YELLOW} Custom recipient (${notification_email}) requires portal configuration.${RESET}"
        echo -e "${YELLOW} See post-deployment actions for guidance.${RESET}\n"
    else
        echo -e "${YELLOW} No notification requested — skipping notification configuration.${RESET}"
        echo -e "${YELLOW} PIM will still notify role owners by default.${RESET}\n"
    fi

    echo -e "${GREEN} P2 path configuration complete.${RESET}\n"

fi

# ── Deployment Summary ─────────────────────────────────────────────────────────

echo -e "${GREEN}═══════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}       Azure Audit Access Setup — Complete          ${RESET}"
echo -e "${GREEN}═══════════════════════════════════════════════════${RESET}"
echo ""
echo -e "${GREEN} Deployment Summary${RESET}"
echo " ──────────────────────────────────────────────────"
echo " Department          : ${department}"
echo " Dynamic group       : Audit-Access-${department}"
echo " Target resource     : ${resource_name}"
echo " Role assigned       : Reader (read-only)"
echo " Access expires      : ${expiry_date}"
echo " MFA required        : ${require_mfa}"
echo " Compliant device    : ${require_compliant_device}"

if [[ "${send_notification^^}" == "Y" ]]; then
    echo " Expiry notification : ${notification_email} (${notify_days_before} days before expiry)"
else
    echo " Expiry notification : None requested"
fi

if [[ "${p2_available^^}" == "Y" ]]; then
    echo " Licensing path      : P2 — PIM"
else
    echo " Licensing path      : P1 — Tag-based expiry"
fi

echo " ──────────────────────────────────────────────────"
echo ""

# ── Post-Deployment Actions ────────────────────────────────────────────────────

if [[ "${p2_available^^}" != "Y" ]]; then

    echo -e "${RED}═══════════════════════════════════════════════════${RESET}"
    echo -e "${RED}   !! Post-Deployment Actions Required — P1 Path   ${RESET}"
    echo -e "${RED}═══════════════════════════════════════════════════${RESET}"
    echo ""
    echo -e "${RED} The following steps must be completed manually.${RESET}"
    echo -e "${RED} Without these, expiry and alerting will not function.${RESET}"
    echo ""

    echo -e "${RED} [REQUIRED] 1. Set up Log Analytics Workspace${RESET}"
    echo "    — Required to trigger date-based alert rules at P1 level."
    echo "    — Without this the expiry alert will never fire."
    echo "    — See README > P1 Setup > Log Analytics Workspace"
    echo ""

    echo -e "${RED} [REQUIRED] 2. Set up Automation Runbook for Access Cleanup${RESET}"
    echo "    — At P1 there is no native time-bound role expiry."
    echo "    — The Runbook reads the expiry tag and removes the Reader"
    echo "      role assignment automatically on : ${expiry_date}"
    echo "    — Without this, access will not expire on schedule."
    echo "    — See README > P1 Setup > Automation Runbook"
    echo ""

    if [[ "${send_notification^^}" == "Y" ]]; then
        echo -e "${RED} [REQUIRED] 3. Verify Action Group Email Delivery${RESET}"
        echo "    — Confirm the Action Group can reach : ${notification_email}"
        echo "    — Send a test alert from Azure Monitor to verify."
        echo "    — Without this you cannot confirm alerts will fire."
        echo "    — See README > P1 Setup > Testing Your Alert"
        echo ""
    fi

    echo -e "${YELLOW} [RECOMMENDED] 4. Review Dynamic Group Membership${RESET}"
    echo "    — Confirm correct users have been added to :"
    echo "      Audit-Access-${department}"
    echo "    — Entra ID Portal > Groups > Audit-Access-${department} > Members"
    echo "    — Dynamic membership can take up to 24 hours to populate."
    echo ""

    echo -e "${YELLOW} [RECOMMENDED] 5. Enable Conditional Access Policy${RESET}"
    echo "    — Policy is currently in Report-Only mode."
    echo "    — Review the sign-in logs to verify behaviour before enabling."
    echo "    — Entra ID Portal > Security > Conditional Access"
    echo "    — > Audit-Access-Policy-${department} > Enable"
    echo ""

fi

if [[ "${p2_available^^}" == "Y" ]]; then

    echo -e "${YELLOW}═══════════════════════════════════════════════════${RESET}"
    echo -e "${YELLOW}   Post-Deployment Actions — P2 Path               ${RESET}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════${RESET}"
    echo ""
    echo -e "${GREEN} PIM handles expiry and cleanup automatically.${RESET}"
    echo " The following steps are recommended but not required."
    echo ""

    if [[ "${send_notification^^}" == "Y" ]]; then
        echo -e "${YELLOW} [RECOMMENDED] 1. Configure Custom PIM Notification Recipient${RESET}"
        echo "    — PIM notifies role owners by default."
        echo "    — To add ${notification_email} as a custom recipient :"
        echo "    — Entra ID Portal > PIM > Roles > Reader > Role Settings"
        echo "    — > Notification > Add recipient"
        echo ""
    fi

    echo -e "${YELLOW} [RECOMMENDED] 2. Review Dynamic Group Membership${RESET}"
    echo "    — Confirm correct users have been added to :"
    echo "      Audit-Access-${department}"
    echo "    — Entra ID Portal > Groups > Audit-Access-${department} > Members"
    echo "    — Dynamic membership can take up to 24 hours to populate."
    echo ""

    echo -e "${YELLOW} [RECOMMENDED] 3. Enable Conditional Access Policy${RESET}"
    echo "    — Policy is currently in Report-Only mode."
    echo "    — Review sign-in logs to verify behaviour before enabling."
    echo "    — Entra ID Portal > Security > Conditional Access"
    echo "    — > Audit-Access-Policy-${department} > Enable"
    echo ""

    echo -e "${YELLOW} [RECOMMENDED] 4. Verify PIM Assignment in Portal${RESET}"
    echo "    — Confirm the PIM eligible assignment is visible :"
    echo "    — Entra ID Portal > PIM > Azure Resources"
    echo "    — > ${resource_name} > Eligible Assignments"
    echo ""

fi

# ── Closing Message ───────────────────────────────────────────────────────────
echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
echo -e "${CYAN} Setup complete.${RESET}"
echo -e "${CYAN} Refer to the README for full guidance on${RESET}"
echo -e "${CYAN} post-deployment steps and testing.${RESET}"
echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
echo ""