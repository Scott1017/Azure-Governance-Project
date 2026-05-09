#!/bin/bash
# =========================================
# Azure Governance Policy Deployment Tool
# =========================================
# Description: Deploys a Deny or Modify
# tagging policy to a target resource group
#
# Author: Scott1017
# Ex reliquiis cinerum renatus resurge
# Platform: Azure CLI (Bash)
# =========================================

# =========================================
# Step 1: Azure Account Login
# =========================================

context=$(az account show 2>/dev/null)

if [ -z "$context" ]; then
    echo "No active Azure connection found. Connecting..."
    az login
    context=$(az account show)
fi

echo ""
echo "Connected to subscription: $(az account show --query name -o tsv)"
echo ""
read -p "Is this the correct subscription? (yes/no) " confirm

if [ "$confirm" != "yes" ]; then
    echo "Please switch to the correct subscription and re-run the script."
    exit
fi

echo ""
echo "Subscription confirmed. Continuing..."
echo ""

# =========================================
# Step 2: Collect Policy Information
# =========================================

echo "=== Policy Configuration ==="
echo ""

read -p "Policy type - Enter 'Deny' or 'Modify': " policy_type
policy_type=$(echo "$policy_type" | tr '[:upper:]' '[:lower:]')

while [ "$policy_type" != "deny" ] && [ "$policy_type" != "modify" ]; do
    echo "Invalid choice. Please enter 'Deny' or 'Modify'"
    read -p "Policy type: " policy_type
    policy_type=$(echo "$policy_type" | tr '[:upper:]' '[:lower:]')
done

if [ "$policy_type" = "deny" ]; then policy_type="Deny"; fi
if [ "$policy_type" = "modify" ]; then policy_type="Modify"; fi

read -p "Assignment level - Enter 'ManagementGroup', 'Subscription', 'ResourceGroup' or 'Resource': " assignment_level
assignment_level=$(echo "$assignment_level" | tr '[:upper:]' '[:lower:]')

while [ "$assignment_level" != "managementgroup" ] && [ "$assignment_level" != "subscription" ] && [ "$assignment_level" != "resourcegroup" ] && [ "$assignment_level" != "resource" ]; do
    echo "Invalid choice. Please enter a valid assignment level"
    read -p "Assignment level: " assignment_level
    assignment_level=$(echo "$assignment_level" | tr '[:upper:]' '[:lower:]')
done

read -p "Enter the name of the target $assignment_level: " level_name
read -p "Enter the tag name to enforce (e.g. Environment, Owner, Project): " tag_name
read -p "Enter a display name for this policy (e.g. Enforce Environment Tag): " display_name

if [ "$policy_type" = "Modify" ]; then
    read -p "Enter the default tag value to apply (e.g. Production, Development, Unassigned): " tag_value
else
    tag_value=""
fi

# =========================================
# Functions
# =========================================

deploy_deny_policy() {
        assignment_level=$1
        level_name=$2
        tag_name=$3
        display_name=$4
    

    # Build the policy rule using the user's tag name
    policy_rule=$(cat <<EQF
{
    "if": {
        "field": "tags['$tag_name']",
        "exists": "false"
    },
    "then": {
        "effect": "deny"
    }
}
EQF
)

    # Stage 1 - Define
    az policy definition create \
    --name "$display_name-deny" \
    --display-name "$display_name" \
    --rules "$policy_rule" \
    --mode All

    # Build scope path based on assignment level
    sub_id=$(az account show --query id -o tsv)

    case "$assignment_level" in
    managementgroup)
        scope="/providers/Microsoft.Management/managementGroups/$level_name" ;;
    subscription)
        scope="/subscriptions/$sub_id" ;;
    resourcegroup)
        scope="/subscriptions/$sub_id/resourceGroups/$level_name" ;;
    resource)
        read -p "Enter resource provider and type: " resource_type
        read -p "Enter resource name: " resource_name
        scope="/subscriptions/$sub_id/resourceGroups/$level_name/providers/$resource_type/$resource_name" ;;
esac

    # Stage 2 - Assign
    az policy assignment create \
    --name "$display_name-assignment" \
    --display-name "$display_name" \
    --policy "$display_name-deny" \
    --scope "$scope" \
    --description "Deployed via governance-policy.sh"

    echo ""
    echo "Deny policy deployed successfully."
    echo ""
}

deploy_modify_policy() {
        assignment_level=$1
        level_name=$2
        tag_name=$3
        tag_value=$4
        display_name=$5

    # Build the policy rule using the user's tag name
    
    policy_rule=$(cat <<EQF
{
    "if": {
        "field": "tags['$tag_name']",
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
                "field": "tags['$tag_name']",
                "value": "$tag_value"
            }]
        }
    }
}
EQF
)

    # Stage 1 - Define
    az policy definition create \
    --name "$display_name-modify" \
    --display-name "$display_name" \
    --rules "$policy_rule" \
    --mode All

    # Build scope path based on assignment level
    sub_id=$(az account show --query id -o tsv)

    case "$assignment_level" in
    managementgroup)
        scope="/providers/Microsoft.Management/managementGroups/$level_name" ;;
    subscription)
        scope="/subscriptions/$sub_id" ;;
    resourcegroup)
        scope="/subscriptions/$sub_id/resourceGroups/$level_name" ;;
    resource)
        read -p "Enter resource provider and type: " resource_type
        read -p "Enter resource name: " resource_name
        scope="/subscriptions/$sub_id/resourceGroups/$level_name/providers/$resource_type/$resource_name" ;;
esac

    # Stage 2 - Assign
    az policy assignment create \
    --name "$display_name-assignment" \
    --display-name "$display_name" \
    --policy "$display_name-modify" \
    --scope "$scope" \
    --description "Deployed via governance-policy.sh"

    echo ""
    echo "Modify policy deployed successfully."
    echo ""
}

# =========================================
# Step 3: Confirm and Deploy
# =========================================

while true; do

    # Display summary
    echo ""
    echo "=== Policy Summary ==="
    echo ""
    echo "Policy Type:      $policy_type"
    echo "Assignment Level: $assignment_level"
    echo "Target Name:      $level_name"
    echo "Tag Name:         $tag_name"

    if [ "$policy_type" = "Modify" ]; then
        echo "Tag Value:        $tag_value"
    fi
    echo "Display Name:     $display_name"
    echo ""

    read -p "Is this correct? (yes/no) " confirm
    confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')

    if [ "$confirm" = "yes" ]; then
        echo ""
        echo "Proceeding with deployment..."
        echo ""
        break
    else
        # Correction menu
        echo ""
        echo "What would you like to correct?"
        echo "1. Policy type"
        echo "2. Assignment level"
        echo "3. Target name"
        echo "4. Tag name"
        echo "5. Display name"
        echo "6. Start over"
        echo "7. Exit"
        echo ""
        read -p "Enter a number (1-7): " correction

        case "$correction" in
            1)
                read -p "Policy type - Enter 'Deny' or 'Modify': " policy_type
                policy_type=$(echo "$policy_type" | tr '[:upper:]' '[:lower:]')
                if [ "$policy_type" = "deny" ]; then policy_type="Deny"; fi
                if [ "$policy_type" = "modify" ]; then policy_type="Modify"; fi ;;

            2)
                read -p "Assignment level - Enter 'ManagementGroup', 'Subscription', 'ResourceGroup' or 'Resource': " assignment_level
                assignment_level=$(echo "$assignment_level" | tr '[:upper:]' '[:lower:]')
                echo ""
                echo "You previously entered '$level_name' as the target name."
                read -p "Does this need updating? (yes/no) " update_level
                if [ "$update_level" = "yes" ]; then
                    read -p "Enter the name of the target $assignment_level: " level_name
                fi ;;

            3)
                read -p "Enter the name of the target $assignment_level: " level_name ;;

            4)
                read -p "Enter the tag name to enforce (e.g. Environment, Owner, Project): " tag_name ;;

            5)
                read -p "Enter a display name for this policy: " display_name ;;

            6)
                read -p "Policy type - Enter 'Deny' or 'Modify': " policy_type
                policy_type=$(echo "$policy_type" | tr '[:upper:]' '[:lower:]')
                if [ "$policy_type" = "deny" ]; then policy_type="Deny"; fi
                if [ "$policy_type" = "modify" ]; then policy_type="Modify"; fi
                read -p "Assignment level - Enter 'ManagementGroup', 'Subscription', 'ResourceGroup' or 'Resource': " assignment_level
                assignment_level=$(echo "$assignment_level" | tr '[:upper:]' '[:lower:]')
                read -p "Enter the name of the target $assignment_level: " level_name
                read -p "Enter the tag name to enforce: " tag_name
                read -p "Enter a display name for this policy: " display_name
                if [ "$policy_type" = "Modify" ]; then
                    read -p "Enter the default tag value to apply (e.g. Production, Development, Unassigned): " tag_value
                else
                    tag_value=""
                fi ;;

            7)
                echo "Exiting script."
                exit ;;
        esac
    fi

done # End of while loop

# =========================================
# Step 4: Deploy
# =========================================

if [ "$policy_type" = "Deny" ]; then
    deploy_deny_policy \
        "$assignment_level" \
        "$level_name" \
        "$tag_name" \
        "$display_name"
fi

if [ "$policy_type" = "Modify" ]; then
    deploy_modify_policy \
        "$assignment_level" \
        "$level_name" \
        "$tag_name" \
        "$tag_value" \
        "$display_name"
fi

