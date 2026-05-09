# =========================================
# Azure Governance Policy Deployment Tool
# =========================================
# Description: Deploys a Deny or Modify
# tagging policy to a target resource group
# 
# Author: Scott1017
# Ex reliquiis cinerum renatus resurge
# Platform: PowerShell
# =========================================

# =========================================
# Step 1: Connection Check
# =========================================

$context = Get-AzContext

if (-not $context) {
    Write-Host "No active Azure connection found. Connecting..."
    Connect-AzAccount
    $context = Get-AzContext
}

Write-Host ""
Write-Host "Connected to subscription: $($context.Subscription.Name)"
Write-Host ""
$confirm = Read-Host "Is this the correct subscription? (yes/no)"

if ($confirm -ne "yes") {
    Write-Host "Please switch to the correct subscription and re-run the script."
    exit
}

Write-Host ""
Write-Host "Subscription confirmed. Continuing..."
Write-Host ""

# =========================================
# Step 2: Collect Policy Information
# =========================================

Write-Host "=== Policy Configuration ==="
Write-Host ""

$policyType = (Read-Host "Policy type - Enter 'Deny' or 'Modify'").ToLower()
while ($policyType -ne "deny" -and $policyType -ne "modify") {
    Write-Host "Invalid choice. Please enter 'Deny' or 'Modify'"
    $policyType = (Read-Host "Policy type").ToLower()
}
if ($policyType -eq "deny") { $policyType = "Deny" }
if ($policyType -eq "modify") { $policyType = "Modify" }

$assignmentLevel = (Read-Host "Assignment level - Enter 'ManagementGroup', 'Subscription', 'ResourceGroup' or 'Resource'").ToLower()
while ($assignmentLevel -ne "managementgroup" -and $assignmentLevel -ne "subscription" -and $assignmentLevel -ne "resourcegroup" -and $assignmentLevel -ne "resource") {
    Write-Host "Invalid choice. Please enter a valid assignment level"
    $assignmentLevel = (Read-Host "Assignment level").ToLower()
}

$levelName = Read-Host "Enter the name of the target $assignmentLevel"
$tagName = Read-Host "Enter the tag name to enforce (e.g. Environment, Owner, Project)"
$displayName = Read-Host "Enter a display name for this policy (e.g. Enforce Environment Tag)"
if ($policyType -eq "Modify") {
    $tagValue = Read-Host "Enter the default tag value to apply (e.g. Production, Development, Unassigned)"
} else {
    $tagValue = $null
}

# =========================================
# Functions
# =========================================

function Deploy-DenyPolicy {
    param (
        $assignmentLevel,
        $levelName,
        $tagName,
        $displayName
    )

    # Build the policy rule using the user's tag name
    $policyRule = @"
{
    "if": {
        "field": "tags['$tagName']",
        "exists": "false"
    },
    "then": {
        "effect": "deny"
    }
}
"@

    # Stage 1 - Define the policy
    Write-Host "Creating policy definition..."
    $definition = New-AzPolicyDefinition `
        -Name "$displayName-deny" `
        -DisplayName $displayName `
        -Policy $policyRule `
        -Mode All 

    # Build scope path based on assignment level
    $subId = (Get-AzContext).Subscription.Id

    switch ($assignmentLevel) {
        "managementgroup" {
            $scope = "/providers/Microsoft.Management/managementGroups/$levelName"
        }
        "subscription" {
            $scope = "/subscriptions/$subId"
        }
        "resourcegroup" {
            $scope = "/subscriptions/$subId/resourceGroups/$levelName"
        }
        "resource" {
            $resourceType = Read-Host "Enter the resource provider and type (e.g. Microsoft.Compute/virtualMachines)"
            $resourceName = Read-Host "Enter the resource name"
            $scope = "/subscriptions/$subId/resourceGroups/$levelName/providers/$resourceType/$resourceName"
        }
    }

    # Stage 2 - Assign the policy
    Write-Host "Assigning policy to $assignmentLevel - $levelName..."
    New-AzPolicyAssignment `
        -Name "$displayName-assignment" `
        -DisplayName $displayName `
        -PolicyDefinition $definition `
        -Scope $scope `
        -Description "Deployed via governance-policy.ps1" 
    Write-Host ""
    Write-Host "Deny policy deployed successfully."
    Write-Host ""
}

function Deploy-ModifyPolicy {
    param (
        $assignmentLevel,
        $levelName,
        $tagName,
        $tagValue,
        $displayName
    )

    # Build the policy rule using the user's tag name
    
    $policyRule = @"
{
    "if": {
        "field": "tags['$tagName']",
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
                "field": "tags['$tagName']",
                "value": "$tagValue"
            }]
        }
    }
}
"@

    # Stage 1 - Define the policy
    Write-Host "Creating policy definition..."
    $definition = New-AzPolicyDefinition `
        -Name "$displayName-modify" `
        -DisplayName $displayName `
        -Policy $policyRule

    # Build scope path based on assignment level
    $subId = (Get-AzContext).Subscription.Id

    switch ($assignmentLevel) {
        "managementgroup" {
            $scope = "/providers/Microsoft.Management/managementGroups/$levelName"
        }
        "subscription" {
            $scope = "/subscriptions/$subId"
        }
        "resourcegroup" {
            $scope = "/subscriptions/$subId/resourceGroups/$levelName"
        }
        "resource" {
            $resourceType = Read-Host "Enter the resource provider and type (e.g. Microsoft.Compute/virtualMachines)"
            $resourceName = Read-Host "Enter the resource name"
            $scope = "/subscriptions/$subId/resourceGroups/$levelName/providers/$resourceType/$resourceName"
        }
    }

    # Stage 2 - Assign the policy
    Write-Host "Assigning policy to $assignmentLevel - $levelName..."
    New-AzPolicyAssignment `
        -Name "$displayName-assignment" `
        -PolicyDefinition $definition `
        -Scope $scope
    Write-Host ""
    Write-Host "Modify policy deployed successfully."
    Write-Host ""
}


# =========================================
# Step 3: Confirm and Deploy
# =========================================

while ($true) {

    # Display summary
    Write-Host ""
    Write-Host "=== Policy Summary ==="
    Write-Host ""
    Write-Host "Policy Type:      $policyType"
    Write-Host "Assignment Level: $assignmentLevel"
    Write-Host "Target Name:      $levelName"
    Write-Host "Tag Name:         $tagName"
    if ($policyType -eq "Modify") {
        Write-Host "Tag Value:        $tagValue"
    }
    Write-Host "Display Name:     $displayName"
    Write-Host ""

    $confirm = (Read-Host "Is this correct? (yes/no)").ToLower()

    if ($confirm -eq "yes") {
        Write-Host ""
        Write-Host "Proceeding with deployment..."
        Write-Host ""
        break
    }
   else {
        # Correction menu
        Write-Host ""
        Write-Host "What would you like to correct?"
        Write-Host "1. Policy type"
        Write-Host "2. Assignment level"
        Write-Host "3. Target name"
        Write-Host "4. Tag name"
        Write-Host "5. Display name"
        Write-Host "6. Start over"
        Write-Host "7. Exit"
        Write-Host ""

        $correction = Read-Host "Enter a number (1-7)"

        switch ($correction) {
            "1" { $policyType = (Read-Host "Policy type - Enter 'Deny' or 'Modify'").ToLower()
                  if ($policyType -eq "deny") { $policyType = "Deny" }
                  if ($policyType -eq "modify") { $policyType = "Modify" } }

            "2" { $assignmentLevel = (Read-Host "Assignment level - Enter 'ManagementGroup', 'Subscription', 'ResourceGroup' or 'Resource'").ToLower()
                  Write-Host ""
                  Write-Host "You previously entered '$levelName' as the target name."
                  $updateLevel = (Read-Host "Does this need updating? (yes/no)").ToLower()
                  if ($updateLevel -eq "yes") { $levelName = Read-Host "Enter the name of the target $assignmentLevel" } }

            "3" { $levelName = Read-Host "Enter the name of the target $assignmentLevel" }

            "4" { $tagName = Read-Host "Enter the tag name to enforce (e.g. Environment, Owner, Project)" }

            "5" { $displayName = Read-Host "Enter a display name for this policy" }

            "6" { $policyType = (Read-Host "Policy type - Enter 'Deny' or 'Modify'").ToLower()
                  if ($policyType -eq "deny") { $policyType = "Deny" }
                  if ($policyType -eq "modify") { $policyType = "Modify" }
                  $assignmentLevel = (Read-Host "Assignment level - Enter 'ManagementGroup', 'Subscription', 'ResourceGroup' or 'Resource'").ToLower()
                  $levelName = Read-Host "Enter the name of the target $assignmentLevel"
                  $tagName = Read-Host "Enter the tag name to enforce"
                  $displayName = Read-Host "Enter a display name for this policy"
                  if ($policyType -eq "Modify") {
                      $tagValue = Read-Host "Enter the default tag value to apply (e.g. Production, Development, Unassigned)"
                  } else {
                      $tagValue = $null
                  } }

            "7" { Write-Host "Exiting script."; exit }
        }

    } # End of else

} # End of while loop

# =========================================
# Step 4: Deploy
# =========================================

if ($policyType -eq "Deny") {
    Deploy-DenyPolicy `
        -assignmentLevel $assignmentLevel `
        -levelName $levelName `
        -tagName $tagName `
        -displayName $displayName
}

if ($policyType -eq "Modify") {
    Deploy-ModifyPolicy `
        -assignmentLevel $assignmentLevel `
        -levelName $levelName `
        -tagName $tagName `
        -tagValue $tagValue `
        -displayName $displayName
}

