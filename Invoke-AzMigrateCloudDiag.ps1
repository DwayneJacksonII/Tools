<#------------------------------------------------------------------------------

 Copyright © 2026 Microsoft Corporation.  All rights reserved.

 THIS CODE AND ANY ASSOCIATED INFORMATION ARE PROVIDED "AS IS" WITHOUT
 WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT
 LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS
 FOR A PARTICULAR PURPOSE. THE ENTIRE RISK OF USE, INABILITY TO USE, OR
 RESULTS FROM THE USE OF THIS CODE REMAINS WITH THE USER.
 Label: Sample 

#------------------------------------------------------------------------------
#>

#Requires -Modules Az.Accounts, Az.Resources, Az.Network, Az.Migrate
<#
.SYNOPSIS
    Azure Migrate - Cloud Shell Diagnostic Analyzer

.DESCRIPTION
    Run this script in Azure Cloud Shell AFTER an issue has been reproduced on the
    Azure Migrate appliance. It checks the Azure-side configuration to identify
    misconfigurations that cause appliance registration, discovery, or migration failures.

    THIS SCRIPT IS READ-ONLY. It makes no changes to your Azure environment.

    Checks performed:
    - Azure Migrate project existence and configuration
    - Appliance registration status and health
    - Private Endpoint connection status (approved/pending/rejected)
    - Private DNS zone existence, VNet links, and A records
    - NSG rules on appliance subnet (outbound 443 blocks)
    - Activity Log errors related to Azure Migrate
    - Resource health and service health
    - Key Vault and Service Bus accessibility
    - Storage account network rules

.NOTES
    Version:  1.0
    Requires: Azure Cloud Shell (PowerShell) or local PowerShell with Az modules
    Requires: Reader role on the subscription containing the Azure Migrate project

.LINK
    https://learn.microsoft.com/en-us/azure/migrate/troubleshoot-appliance
    https://learn.microsoft.com/en-us/azure/migrate/how-to-use-azure-migrate-with-private-endpoints
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$script:Findings     = [System.Collections.ArrayList]::new()
$script:Warnings     = [System.Collections.ArrayList]::new()
$script:Passed       = [System.Collections.ArrayList]::new()
$script:InfoItems    = [System.Collections.ArrayList]::new()
$script:ScriptVersion = '1.0'

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Banner {
    Write-Host ""
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "  Azure Migrate - Cloud Shell Diagnostic Analyzer v$($script:ScriptVersion)" -ForegroundColor White
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "  Run this AFTER reproducing the issue on the appliance." -ForegroundColor Gray
    Write-Host "  This script is READ-ONLY - no changes will be made." -ForegroundColor Gray
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 65) -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor White
    Write-Host ("=" * 65) -ForegroundColor DarkCyan
}

function Add-Finding {
    param(
        [string]$Check,
        [string]$Status,       # FAIL, WARN, PASS, INFO
        [string]$Detail,
        [string]$Recommendation = '',
        [string]$DocLink = ''
    )
    $obj = [PSCustomObject]@{
        Check          = $Check
        Status         = $Status
        Detail         = $Detail
        Recommendation = $Recommendation
        DocLink        = $DocLink
    }
    switch ($Status) {
        'FAIL' { [void]$script:Findings.Add($obj);  Write-Host "    [FAIL] $Check" -ForegroundColor Red;    Write-Host "           $Detail" -ForegroundColor DarkGray }
        'WARN' { [void]$script:Warnings.Add($obj);  Write-Host "    [WARN] $Check" -ForegroundColor Yellow; Write-Host "           $Detail" -ForegroundColor DarkGray }
        'PASS' { [void]$script:Passed.Add($obj);    Write-Host "    [PASS] $Check" -ForegroundColor Green }
        'INFO' { [void]$script:InfoItems.Add($obj);  Write-Host "    [INFO] $Check" -ForegroundColor Gray;   Write-Host "           $Detail" -ForegroundColor DarkGray }
    }
}

function Get-MenuSelection {
    param(
        [string]$Prompt,
        [string[]]$Options
    )
    Write-Host ""
    Write-Host "  $Prompt" -ForegroundColor White
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "    [$($i + 1)] $($Options[$i])" -ForegroundColor Yellow
    }
    do {
        $input = Read-Host "  Selection"
        $sel = 0
        $valid = [int]::TryParse($input, [ref]$sel) -and $sel -ge 1 -and $sel -le $Options.Count
        if (-not $valid) { Write-Host "  Invalid. Enter 1-$($Options.Count)." -ForegroundColor Red }
    } while (-not $valid)
    return $sel
}

# ============================================================================
# CHECK: Azure Context
# ============================================================================

function Test-AzContext {
    Write-Section "AZURE CONTEXT"

    $ctx = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $ctx) {
        Write-Host "    Not logged in. Running Connect-AzAccount..." -ForegroundColor Yellow
        Connect-AzAccount -ErrorAction Stop
        $ctx = Get-AzContext
    }

    Write-Host "    Account:      $($ctx.Account.Id)" -ForegroundColor Gray
    Write-Host "    Subscription: $($ctx.Subscription.Name) ($($ctx.Subscription.Id))" -ForegroundColor Gray
    Write-Host "    Tenant:       $($ctx.Tenant.Id)" -ForegroundColor Gray
    Write-Host "    Environment:  $($ctx.Environment.Name)" -ForegroundColor Gray

    Add-Finding -Check "Azure authentication" -Status 'PASS' -Detail "Logged in as $($ctx.Account.Id)"
    return $ctx
}

# ============================================================================
# CHECK: Azure Migrate Project
# ============================================================================

function Test-MigrateProject {
    param([string]$ResourceGroupName, [string]$ProjectName)

    Write-Section "AZURE MIGRATE PROJECT"

    # Check resource group exists
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $rg) {
        Add-Finding -Check "Resource Group '$ResourceGroupName'" -Status 'FAIL' `
            -Detail "Resource group not found in current subscription." `
            -Recommendation "Verify the resource group name and ensure you're in the correct subscription." `
            -DocLink "https://learn.microsoft.com/en-us/azure/migrate/create-manage-projects"
        return $null
    }
    Add-Finding -Check "Resource Group exists" -Status 'PASS' -Detail $ResourceGroupName

    # Find Azure Migrate project
    $migrateResources = Get-AzResource -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue |
        Where-Object { $_.ResourceType -match 'Microsoft.Migrate|Microsoft.OffAzure' }

    if (-not $migrateResources -or $migrateResources.Count -eq 0) {
        Add-Finding -Check "Azure Migrate resources in '$ResourceGroupName'" -Status 'FAIL' `
            -Detail "No Microsoft.Migrate or Microsoft.OffAzure resources found." `
            -Recommendation "Verify the resource group contains an Azure Migrate project." `
            -DocLink "https://learn.microsoft.com/en-us/azure/migrate/create-manage-projects"
        return $null
    }

    Write-Host ""
    Write-Host "    Azure Migrate resources found:" -ForegroundColor White
    foreach ($r in $migrateResources) {
        Write-Host "      - $($r.ResourceType): $($r.Name)" -ForegroundColor Gray

        # Check resource health
        $health = Get-AzResource -ResourceId $r.ResourceId -ErrorAction SilentlyContinue
        if ($health) {
            Add-Finding -Check "Resource accessible: $($r.Name)" -Status 'PASS' -Detail $r.ResourceType
        }
    }

    # Look for the Migrate project specifically
    $project = $migrateResources | Where-Object { $_.ResourceType -eq 'Microsoft.Migrate/migrateprojects' } | Select-Object -First 1
    if (-not $project) {
        $project = $migrateResources | Where-Object { $_.ResourceType -eq 'Microsoft.Migrate/assessmentprojects' } | Select-Object -First 1
    }

    if ($project) {
        Add-Finding -Check "Migrate project found" -Status 'PASS' -Detail "$($project.Name) ($($project.ResourceType))"
    } else {
        Add-Finding -Check "Migrate project resource" -Status 'WARN' `
            -Detail "No migrateprojects or assessmentprojects resource found. Other Migrate resources exist." `
            -Recommendation "The project may use a different resource type. Check the Azure portal."
    }

    return $migrateResources
}

# ============================================================================
# CHECK: Private Endpoints
# ============================================================================

function Test-PrivateEndpoints {
    param([string]$ResourceGroupName)

    Write-Section "PRIVATE ENDPOINTS"

    $privateEndpoints = Get-AzPrivateEndpoint -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

    if (-not $privateEndpoints -or $privateEndpoints.Count -eq 0) {
        Add-Finding -Check "Private endpoints in '$ResourceGroupName'" -Status 'INFO' `
            -Detail "No private endpoints found. If using public connectivity, this is expected." `
            -Recommendation "If you intended to use private endpoints, they may be in a different resource group."
        return $false
    }

    $hasIssue = $false
    foreach ($pe in $privateEndpoints) {
        Write-Host ""
        Write-Host "    Private Endpoint: $($pe.Name)" -ForegroundColor White

        foreach ($conn in $pe.PrivateLinkServiceConnections) {
            $status = $conn.PrivateLinkServiceConnectionState.Status
            $desc   = $conn.PrivateLinkServiceConnectionState.Description
            $target = $conn.PrivateLinkServiceId

            Write-Host "      Target: $target" -ForegroundColor Gray
            Write-Host "      Status: $status" -ForegroundColor $(if ($status -eq 'Approved') { 'Green' } elseif ($status -eq 'Pending') { 'Yellow' } else { 'Red' })

            if ($status -eq 'Approved') {
                Add-Finding -Check "PE connection: $($pe.Name)" -Status 'PASS' -Detail "Approved - $target"
            } elseif ($status -eq 'Pending') {
                $hasIssue = $true
                Add-Finding -Check "PE connection: $($pe.Name)" -Status 'FAIL' `
                    -Detail "Status is PENDING. Connection must be approved before the appliance can connect." `
                    -Recommendation "Go to the target resource in Azure portal > Private endpoint connections > Approve the pending connection." `
                    -DocLink "https://learn.microsoft.com/en-us/azure/migrate/how-to-use-azure-migrate-with-private-endpoints"
            } elseif ($status -eq 'Rejected') {
                $hasIssue = $true
                Add-Finding -Check "PE connection: $($pe.Name)" -Status 'FAIL' `
                    -Detail "Status is REJECTED. The connection was explicitly denied." `
                    -Recommendation "The private endpoint connection was rejected. Delete and recreate, or approve it." `
                    -DocLink "https://learn.microsoft.com/en-us/azure/migrate/how-to-use-azure-migrate-with-private-endpoints"
            } else {
                $hasIssue = $true
                Add-Finding -Check "PE connection: $($pe.Name)" -Status 'WARN' `
                    -Detail "Status: $status ($desc)" `
                    -Recommendation "Unexpected connection state. Check the private endpoint in Azure portal."
            }
        }

        # Check NIC and IP
        if ($pe.NetworkInterfaces) {
            foreach ($nic in $pe.NetworkInterfaces) {
                $nicResource = Get-AzNetworkInterface -ResourceId $nic.Id -ErrorAction SilentlyContinue
                if ($nicResource -and $nicResource.IpConfigurations) {
                    foreach ($ip in $nicResource.IpConfigurations) {
                        Write-Host "      Private IP: $($ip.PrivateIpAddress)" -ForegroundColor Gray
                        Add-Finding -Check "PE NIC IP: $($pe.Name)" -Status 'INFO' -Detail "Private IP: $($ip.PrivateIpAddress)"
                    }
                }
            }
        }
    }

    return (-not $hasIssue)
}

# ============================================================================
# CHECK: Private DNS Zones
# ============================================================================

function Test-PrivateDnsZones {
    param(
        [string]$ResourceGroupName,
        [string]$Cloud
    )

    Write-Section "PRIVATE DNS ZONES"

    # Expected zones for Azure Migrate
    $expectedZones = @()
    if ($Cloud -eq 'Commercial') {
        $expectedZones = @(
            'privatelink.prod.migration.windowsazure.com'
            'privatelink.blob.core.windows.net'
            'privatelink.vaultcore.azure.net'
            'privatelink.servicebus.windows.net'
        )
    } else {
        $expectedZones = @(
            'privatelink.prod.migration.windowsazure.us'
            'privatelink.blob.core.usgovcloudapi.net'
            'privatelink.vaultcore.usgovcloudapi.net'
            'privatelink.servicebus.usgovcloudapi.net'
        )
    }

    # Get all private DNS zones in the subscription
    $allZones = Get-AzPrivateDnsZone -ErrorAction SilentlyContinue

    if (-not $allZones) {
        Add-Finding -Check "Private DNS zones" -Status 'WARN' `
            -Detail "No private DNS zones found in this subscription." `
            -Recommendation "If using private endpoints, private DNS zones are required for name resolution." `
            -DocLink "https://learn.microsoft.com/en-us/azure/migrate/how-to-use-azure-migrate-with-private-endpoints"
        return
    }

    foreach ($expected in $expectedZones) {
        $zone = $allZones | Where-Object { $_.Name -eq $expected }

        if ($zone) {
            Add-Finding -Check "DNS zone: $expected" -Status 'PASS' -Detail "Found in RG: $($zone.ResourceGroupName)"

            # Check VNet links
            $links = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $zone.ResourceGroupName -ZoneName $zone.Name -ErrorAction SilentlyContinue
            if ($links -and $links.Count -gt 0) {
                foreach ($link in $links) {
                    $autoReg = if ($link.RegistrationEnabled) { " (auto-registration ON)" } else { "" }
                    Add-Finding -Check "  VNet link: $($link.Name)" -Status 'PASS' `
                        -Detail "Linked to VNet: $($link.VirtualNetworkId.Split('/')[-1])$autoReg"
                }
            } else {
                Add-Finding -Check "  VNet links for $expected" -Status 'FAIL' `
                    -Detail "DNS zone exists but has NO VNet links. The appliance VNet cannot resolve these names." `
                    -Recommendation "Link this DNS zone to the VNet where the Azure Migrate appliance is deployed." `
                    -DocLink "https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns"
            }

            # Check for A records (at least one should exist)
            $records = Get-AzPrivateDnsRecordSet -ResourceGroupName $zone.ResourceGroupName -ZoneName $zone.Name -RecordType A -ErrorAction SilentlyContinue
            if ($records -and $records.Count -gt 0) {
                Add-Finding -Check "  A records in $expected" -Status 'PASS' -Detail "$($records.Count) A record(s) found"
            } else {
                Add-Finding -Check "  A records in $expected" -Status 'FAIL' `
                    -Detail "No A records found. Private endpoints won't resolve to private IPs." `
                    -Recommendation "A records are auto-created when private endpoints are approved. Check PE status." `
                    -DocLink "https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns"
            }
        } else {
            Add-Finding -Check "DNS zone: $expected" -Status 'FAIL' `
                -Detail "Required private DNS zone NOT found in this subscription." `
                -Recommendation "Create the private DNS zone '$expected' and link it to the appliance VNet." `
                -DocLink "https://learn.microsoft.com/en-us/azure/migrate/how-to-use-azure-migrate-with-private-endpoints"
        }
    }
}

# ============================================================================
# CHECK: NSG Rules on Appliance Subnet
# ============================================================================

function Test-NsgRules {
    param([string]$ResourceGroupName)

    Write-Section "NETWORK SECURITY GROUPS (NSG)"

    $nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

    if (-not $nsgs) {
        # Also check all NSGs in subscription if none in RG
        Add-Finding -Check "NSGs in '$ResourceGroupName'" -Status 'INFO' `
            -Detail "No NSGs found in this resource group. Checking may require the appliance VNet resource group."
        return
    }

    foreach ($nsg in $nsgs) {
        Write-Host ""
        Write-Host "    NSG: $($nsg.Name)" -ForegroundColor White

        # Check for outbound deny rules that could block 443
        $outboundRules = $nsg.SecurityRules | Where-Object { $_.Direction -eq 'Outbound' }
        $denyAll443 = $false

        foreach ($rule in ($outboundRules | Sort-Object Priority)) {
            if ($rule.Access -eq 'Deny' -and
                ($rule.DestinationPortRange -contains '*' -or $rule.DestinationPortRange -contains '443' -or
                 $rule.DestinationPortRange -contains '80-65535' -or $rule.DestinationPortRange -contains '0-65535')) {

                # Check if it's blocking to Internet or all
                if ($rule.DestinationAddressPrefix -in @('*', 'Internet', '0.0.0.0/0')) {
                    $denyAll443 = $true
                    Add-Finding -Check "NSG outbound rule: $($rule.Name)" -Status 'FAIL' `
                        -Detail "Priority $($rule.Priority): DENY outbound to $($rule.DestinationAddressPrefix) on port $($rule.DestinationPortRange)" `
                        -Recommendation "This rule blocks outbound 443 to Azure services. Add higher-priority ALLOW rules for Azure Migrate endpoints, or use service tags (AzureCloud, Storage, AzureKeyVault, ServiceBus, EventHub)." `
                        -DocLink "https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance#port-access"
                }
            }
        }

        if (-not $denyAll443) {
            # Check default outbound rules
            $defaultDeny = $nsg.DefaultSecurityRules | Where-Object {
                $_.Direction -eq 'Outbound' -and $_.Access -eq 'Deny'
            }
            if ($defaultDeny) {
                Add-Finding -Check "NSG default outbound: $($nsg.Name)" -Status 'INFO' `
                    -Detail "Default deny outbound exists (DenyAllOutBound) but custom allow rules should override it."
            }

            # Check for service tag allow rules
            $azureAllow = $outboundRules | Where-Object {
                $_.Access -eq 'Allow' -and
                ($_.DestinationAddressPrefix -match 'AzureCloud|Storage|AzureKeyVault|ServiceBus|EventHub' -or
                 $_.DestinationAddressPrefix -in @('*', 'Internet'))
            }
            if ($azureAllow) {
                foreach ($rule in $azureAllow) {
                    Add-Finding -Check "NSG allow rule: $($rule.Name)" -Status 'PASS' `
                        -Detail "Priority $($rule.Priority): ALLOW outbound to $($rule.DestinationAddressPrefix) port $($rule.DestinationPortRange)"
                }
            } else {
                Add-Finding -Check "NSG Azure service tags: $($nsg.Name)" -Status 'WARN' `
                    -Detail "No explicit allow rules for Azure service tags found." `
                    -Recommendation "If outbound is restricted, ensure rules exist for: AzureCloud, Storage, AzureKeyVault, ServiceBus on port 443."
            }
        }
    }
}

# ============================================================================
# CHECK: Activity Log Errors
# ============================================================================

function Test-ActivityLog {
    param([string]$ResourceGroupName)

    Write-Section "ACTIVITY LOG (Last 24 Hours)"

    $startTime = (Get-Date).AddHours(-24)

    $logs = Get-AzActivityLog -ResourceGroupName $ResourceGroupName -StartTime $startTime -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Status.Value -in @('Failed', 'Error') -and
            ($_.ResourceType.Value -match 'Microsoft.Migrate|Microsoft.OffAzure|Microsoft.KeyVault|Microsoft.Network/privateEndpoints|Microsoft.Storage')
        } |
        Select-Object -First 20

    if ($logs -and $logs.Count -gt 0) {
        Write-Host "    Found $($logs.Count) error(s) in the last 24 hours:" -ForegroundColor Yellow
        foreach ($log in $logs) {
            $msg = if ($log.Properties -and $log.Properties.Content -and $log.Properties.Content.statusMessage) {
                $log.Properties.Content.statusMessage
            } else {
                $log.StatusMessage
            }
            Write-Host ""
            Write-Host "      Time:      $($log.EventTimestamp)" -ForegroundColor Gray
            Write-Host "      Operation: $($log.OperationName.Value)" -ForegroundColor Gray
            Write-Host "      Resource:  $($log.ResourceId)" -ForegroundColor Gray
            Write-Host "      Status:    $($log.Status.Value)" -ForegroundColor Red
            if ($msg) {
                $truncated = if ($msg.Length -gt 200) { $msg.Substring(0, 200) + '...' } else { $msg }
                Write-Host "      Message:   $truncated" -ForegroundColor DarkGray
            }

            # Detect specific known errors and provide targeted guidance
            $msgFull = if ($msg) { $msg } else { '' }
            if ($msgFull -match 'AccountPropertyCannotBeUpdated' -or $msgFull -match 'requireInfrastructureEncryption') {
                Add-Finding -Check "Storage provisioning: requireInfrastructureEncryption" -Status 'FAIL' `
                    -Detail "Azure Migrate failed to provision a storage account. An Azure Policy is trying to set 'requireInfrastructureEncryption' on an existing account, but this is a CREATE-TIME-ONLY property and cannot be changed after creation." `
                    -Recommendation @"
This is a known conflict between Azure Policy and Azure Migrate automated provisioning.
Azure Migrate creates storage accounts without infrastructure (double) encryption.
A policy then tries to modify the account to add it, which fails because the property is immutable.

Fix options:
  1. POLICY EXEMPTION: Create an exemption for the Migrate resource group:
     Azure Portal > Policy > Assignments > select the policy > Create Exemption
  2. PRE-CREATE STORAGE: Create the storage account manually WITH
     requireInfrastructureEncryption=true before setting up the Migrate project.
  3. TEMPORARY AUDIT: Change policy effect from Deny/Modify to Audit during Migrate setup.

See: https://learn.microsoft.com/en-us/azure/governance/policy/concepts/exemption-structure
See: https://learn.microsoft.com/en-us/azure/storage/common/infrastructure-encryption-enable
See: https://aka.ms/storageaccountupdate
"@ `
                    -DocLink "https://learn.microsoft.com/en-us/azure/storage/common/infrastructure-encryption-enable"
            } else {
                Add-Finding -Check "Activity Log error" -Status 'WARN' `
                    -Detail "$($log.OperationName.Value) - $($log.Status.Value) at $($log.EventTimestamp)" `
                    -Recommendation "Review the full error in Azure Portal > Activity Log for resource group '$ResourceGroupName'."
            }
        }
    } else {
        Add-Finding -Check "Activity Log (24h)" -Status 'PASS' -Detail "No Migrate-related errors in the last 24 hours."
    }
}

# ============================================================================
# CHECK: Key Vault Access
# ============================================================================

function Test-KeyVault {
    param([string]$ResourceGroupName)

    Write-Section "KEY VAULT"

    $vaults = Get-AzKeyVault -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

    if (-not $vaults -or $vaults.Count -eq 0) {
        Add-Finding -Check "Key Vault in '$ResourceGroupName'" -Status 'INFO' `
            -Detail "No Key Vaults found in this resource group (may be in a different RG)."
        return
    }

    foreach ($v in $vaults) {
        $vault = Get-AzKeyVault -VaultName $v.VaultName -ErrorAction SilentlyContinue
        if ($vault) {
            Write-Host "    Vault: $($vault.VaultName)" -ForegroundColor White

            # Check network rules
            if ($vault.NetworkAcls) {
                $defaultAction = $vault.NetworkAcls.DefaultAction
                Write-Host "      Default Action: $defaultAction" -ForegroundColor Gray

                if ($defaultAction -eq 'Deny') {
                    # Check if private endpoint or VNet rules exist
                    $hasVNetRules = $vault.NetworkAcls.VirtualNetworkRules.Count -gt 0
                    $hasPE = $vault.NetworkAcls.Bypass -match 'AzureServices'

                    if (-not $hasVNetRules -and -not $hasPE) {
                        Add-Finding -Check "Key Vault firewall: $($vault.VaultName)" -Status 'WARN' `
                            -Detail "Firewall default action is Deny with no VNet rules. Appliance may not be able to access the vault." `
                            -Recommendation "Add the appliance VNet/subnet to the Key Vault firewall rules, or use a private endpoint." `
                            -DocLink "https://learn.microsoft.com/en-us/azure/key-vault/general/network-security"
                    } else {
                        Add-Finding -Check "Key Vault firewall: $($vault.VaultName)" -Status 'PASS' `
                            -Detail "Firewall is set to Deny but has VNet rules or AzureServices bypass."
                    }
                } else {
                    Add-Finding -Check "Key Vault firewall: $($vault.VaultName)" -Status 'PASS' `
                        -Detail "Default action: Allow (no network restrictions)."
                }
            }

            # Check soft delete and purge protection
            Write-Host "      Soft Delete:       $($vault.EnableSoftDelete)" -ForegroundColor Gray
            Write-Host "      Purge Protection:  $($vault.EnablePurgeProtection)" -ForegroundColor Gray
        }
    }
}

# ============================================================================
# CHECK: Storage Accounts
# ============================================================================

function Test-StorageAccounts {
    param([string]$ResourceGroupName)

    Write-Section "STORAGE ACCOUNTS"

    $storageAccounts = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

    if (-not $storageAccounts) {
        Add-Finding -Check "Storage accounts in '$ResourceGroupName'" -Status 'INFO' `
            -Detail "No storage accounts found in this resource group."
        return
    }

    foreach ($sa in $storageAccounts) {
        Write-Host "    Storage: $($sa.StorageAccountName)" -ForegroundColor White

        # Check network rules
        $netRules = $sa.NetworkRuleSet
        if ($netRules) {
            $defaultAction = $netRules.DefaultAction
            Write-Host "      Default Action: $defaultAction" -ForegroundColor Gray

            if ($defaultAction -eq 'Deny') {
                $hasVNetRules = $netRules.VirtualNetworkRules.Count -gt 0
                $bypass = $netRules.Bypass

                if (-not $hasVNetRules -and $bypass -notmatch 'AzureServices') {
                    Add-Finding -Check "Storage firewall: $($sa.StorageAccountName)" -Status 'WARN' `
                        -Detail "Firewall default Deny with no VNet rules or AzureServices bypass." `
                        -Recommendation "The appliance needs access to upload discovery/replication data. Add VNet rules or a private endpoint." `
                        -DocLink "https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security"
                } else {
                    Add-Finding -Check "Storage firewall: $($sa.StorageAccountName)" -Status 'PASS' `
                        -Detail "Firewall Deny but with VNet rules or AzureServices bypass ($bypass)."
                }
            } else {
                Add-Finding -Check "Storage firewall: $($sa.StorageAccountName)" -Status 'PASS' `
                    -Detail "Default action: Allow."
            }
        }

        # Check infrastructure encryption (double encryption)
        $infraEncryption = $false
        try {
            $saDetail = Get-AzResource -ResourceId $sa.Id -ExpandProperties -ErrorAction SilentlyContinue
            if ($saDetail -and $saDetail.Properties) {
                $infraEncryption = $saDetail.Properties.encryption.requireInfrastructureEncryption -eq $true
            }
        } catch { }

        Write-Host "      Infrastructure Encryption: $infraEncryption" -ForegroundColor Gray
        Write-Host "      Encryption KeySource:      $($sa.Encryption.KeySource)" -ForegroundColor Gray

        if ($infraEncryption) {
            Add-Finding -Check "Storage infra encryption: $($sa.StorageAccountName)" -Status 'INFO' `
                -Detail "requireInfrastructureEncryption is enabled (double encryption). This is a read-only property after creation."
        }
    }
}

# ============================================================================
# CHECK: Azure Policy - Infrastructure Encryption Enforcement
# ============================================================================

function Test-AzurePolicies {
    param([string]$ResourceGroupName)

    Write-Section "AZURE POLICY (Storage Infrastructure Encryption)"

    # Check for policy assignments that could enforce requireInfrastructureEncryption
    $policyAssignments = Get-AzPolicyAssignment -ErrorAction SilentlyContinue

    if (-not $policyAssignments) {
        Add-Finding -Check "Azure Policy assignments" -Status 'INFO' `
            -Detail "Unable to read policy assignments (may need higher permissions)."
        return
    }

    $infraEncryptionPolicies = @()
    foreach ($pa in $policyAssignments) {
        # Get the policy definition to check if it enforces infrastructure encryption
        $policyDef = $null
        try {
            if ($pa.Properties.PolicyDefinitionId) {
                $policyDef = Get-AzPolicyDefinition -Id $pa.Properties.PolicyDefinitionId -ErrorAction SilentlyContinue
            }
        } catch { }

        if ($policyDef -and $policyDef.Properties.PolicyRule) {
            $ruleJson = $policyDef.Properties.PolicyRule | ConvertTo-Json -Depth 20 -ErrorAction SilentlyContinue
            if ($ruleJson -match 'requireInfrastructureEncryption|infrastructure.encryption|infrastructureEncryption') {
                $infraEncryptionPolicies += [PSCustomObject]@{
                    AssignmentName = $pa.Properties.DisplayName
                    PolicyName     = $policyDef.Properties.DisplayName
                    Effect         = ($pa.Properties.Parameters.effect.Value, $policyDef.Properties.Parameters.effect.defaultValue, 'Unknown' | Where-Object { $_ } | Select-Object -First 1)
                    Scope          = $pa.Properties.Scope
                    AssignmentId   = $pa.ResourceId
                }
            }
        }
    }

    if ($infraEncryptionPolicies.Count -gt 0) {
        foreach ($p in $infraEncryptionPolicies) {
            Write-Host "    Policy: $($p.PolicyName)" -ForegroundColor White
            Write-Host "      Assignment: $($p.AssignmentName)" -ForegroundColor Gray
            Write-Host "      Effect:     $($p.Effect)" -ForegroundColor Gray
            Write-Host "      Scope:      $($p.Scope)" -ForegroundColor Gray

            if ($p.Effect -in @('Deny', 'deny', 'Audit', 'audit', 'Modify', 'modify', 'Append', 'append')) {
                Add-Finding -Check "Policy enforces infra encryption: $($p.PolicyName)" -Status 'FAIL' `
                    -Detail "Azure Policy '$($p.AssignmentName)' (effect: $($p.Effect)) enforces requireInfrastructureEncryption on storage accounts. Azure Migrate creates storage accounts automatically during project setup WITHOUT this property, causing 'AccountPropertyCannotBeUpdated' errors when the policy tries to add it after creation." `
                    -Recommendation @"
This policy conflicts with Azure Migrate automated storage account provisioning.
Options to resolve:
  1. Create a policy EXEMPTION for the Azure Migrate resource group:
     Azure Portal > Policy > Assignments > find this policy > Create Exemption > scope to RG '$ResourceGroupName'
  2. Pre-create the storage accounts WITH requireInfrastructureEncryption=true BEFORE
     setting up the Azure Migrate project, then configure Migrate to use them.
  3. Temporarily set the policy effect to 'Audit' instead of 'Deny/Modify' during Migrate setup.
See: https://learn.microsoft.com/en-us/azure/governance/policy/concepts/exemption-structure
See: https://learn.microsoft.com/en-us/azure/storage/common/infrastructure-encryption-enable
"@`
                    -DocLink "https://learn.microsoft.com/en-us/azure/governance/policy/concepts/exemption-structure"
            } else {
                Add-Finding -Check "Policy references infra encryption: $($p.PolicyName)" -Status 'INFO' `
                    -Detail "Policy found with effect '$($p.Effect)' - may not block creation but worth noting."
            }
        }
    } else {
        Add-Finding -Check "Infrastructure encryption policies" -Status 'PASS' `
            -Detail "No Azure Policy assignments enforcing requireInfrastructureEncryption found."
    }

    # Also check for failed policy evaluations in activity log
    $startTime = (Get-Date).AddHours(-48)
    $policyLogs = Get-AzActivityLog -ResourceGroupName $ResourceGroupName -StartTime $startTime -ErrorAction SilentlyContinue |        Where-Object {
            ($_.Status.Value -in @('Failed', 'Error')) -and
            ($_.OperationName.Value -match 'Microsoft.Authorization/policies' -or
             ($_.StatusMessage -match 'AccountPropertyCannotBeUpdated|requireInfrastructureEncryption|policy'))
        } | Select-Object -First 10

    if ($policyLogs -and $policyLogs.Count -gt 0) {
        Write-Host "" 
        Write-Host "    Policy-related failures in Activity Log (48h):" -ForegroundColor Yellow
        foreach ($log in $policyLogs) {
            $msg = if ($log.StatusMessage) { $log.StatusMessage } else { 'No message' }
            $truncated = if ($msg.Length -gt 300) { $msg.Substring(0, 300) + '...' } else { $msg }
            Write-Host "      [$($log.EventTimestamp)] $($log.OperationName.Value) - $truncated" -ForegroundColor DarkGray
        }
        Add-Finding -Check "Policy evaluation failures" -Status 'WARN' `
            -Detail "$($policyLogs.Count) policy-related error(s) found in the last 48 hours for this resource group." `
            -Recommendation "Review Azure Portal > Policy > Compliance for the resource group '$ResourceGroupName'."
    }
}

# ============================================================================
# CHECK: Appliance Resources (Microsoft.OffAzure)
# ============================================================================

function Test-ApplianceResources {
    param(
        [string]$ResourceGroupName,
        [array]$MigrateResources
    )

    Write-Section "APPLIANCE REGISTRATION"

    $offAzure = $MigrateResources | Where-Object { $_.ResourceType -match 'Microsoft.OffAzure' }

    if (-not $offAzure) {
        Add-Finding -Check "Appliance resources (OffAzure)" -Status 'WARN' `
            -Detail "No Microsoft.OffAzure resources found. The appliance may not have registered yet." `
            -Recommendation "If registration is failing, run the on-appliance connectivity checker first to verify network access." `
            -DocLink "https://learn.microsoft.com/en-us/azure/migrate/troubleshoot-appliance"
        return
    }

    foreach ($r in $offAzure) {
        Write-Host "    $($r.ResourceType): $($r.Name)" -ForegroundColor White

        # Get detailed resource properties
        $detail = Get-AzResource -ResourceId $r.ResourceId -ExpandProperties -ErrorAction SilentlyContinue
        if ($detail -and $detail.Properties) {
            $props = $detail.Properties

            if ($props.provisioningState) {
                Write-Host "      Provisioning State: $($props.provisioningState)" -ForegroundColor Gray
                if ($props.provisioningState -ne 'Succeeded') {
                    Add-Finding -Check "Provisioning: $($r.Name)" -Status 'WARN' `
                        -Detail "Provisioning state: $($props.provisioningState)" `
                        -Recommendation "If provisioning is not 'Succeeded', the appliance setup may not be complete."
                } else {
                    Add-Finding -Check "Provisioning: $($r.Name)" -Status 'PASS' -Detail "Succeeded"
                }
            }

            if ($props.agentDetails) {
                Write-Host "      Agent Version: $($props.agentDetails.version)" -ForegroundColor Gray
                Write-Host "      Agent Status:  $($props.agentDetails.status)" -ForegroundColor Gray
            }
        }
    }
}

# ============================================================================
# RESULTS SUMMARY
# ============================================================================

function Write-ResultsSummary {
    Write-Section "DIAGNOSTIC RESULTS SUMMARY"

    $total = $script:Findings.Count + $script:Warnings.Count + $script:Passed.Count
    Write-Host ""
    Write-Host "    Total checks:  $total" -ForegroundColor White
    Write-Host "    Passed:        $($script:Passed.Count)" -ForegroundColor Green
    Write-Host "    Warnings:      $($script:Warnings.Count)" -ForegroundColor Yellow
    Write-Host "    Failures:      $($script:Findings.Count)" -ForegroundColor $(if ($script:Findings.Count -gt 0) { 'Red' } else { 'Green' })

    if ($script:Findings.Count -gt 0) {
        Write-Host ""
        Write-Host "  ========================================" -ForegroundColor Red
        Write-Host "  ACTION REQUIRED - Issues Found:" -ForegroundColor Red
        Write-Host "  ========================================" -ForegroundColor Red

        $actionNum = 0
        foreach ($f in $script:Findings) {
            $actionNum++
            Write-Host ""
            Write-Host "    [$actionNum] $($f.Check)" -ForegroundColor Red
            Write-Host "        Problem:       $($f.Detail)" -ForegroundColor DarkGray
            if ($f.Recommendation) {
                Write-Host "        Action:        $($f.Recommendation)" -ForegroundColor Yellow
            }
            if ($f.DocLink) {
                Write-Host "        Documentation: $($f.DocLink)" -ForegroundColor Cyan
            }
        }
    }

    if ($script:Warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "  ========================================" -ForegroundColor Yellow
        Write-Host "  WARNINGS - Review Recommended:" -ForegroundColor Yellow
        Write-Host "  ========================================" -ForegroundColor Yellow

        foreach ($w in $script:Warnings) {
            Write-Host ""
            Write-Host "    [!] $($w.Check)" -ForegroundColor Yellow
            Write-Host "        $($w.Detail)" -ForegroundColor DarkGray
            if ($w.Recommendation) {
                Write-Host "        Action: $($w.Recommendation)" -ForegroundColor Gray
            }
            if ($w.DocLink) {
                Write-Host "        Doc: $($w.DocLink)" -ForegroundColor Cyan
            }
        }
    }

    if ($script:Findings.Count -eq 0 -and $script:Warnings.Count -eq 0) {
        Write-Host ""
        Write-Host "    ALL CHECKS PASSED - No Azure-side issues detected." -ForegroundColor Green
        Write-Host "    If the appliance is still having issues, run the on-appliance" -ForegroundColor Gray
        Write-Host "    connectivity checker to test network-level access." -ForegroundColor Gray
    }

    # Documentation
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "  DOCUMENTATION LINKS" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "    Troubleshoot Appliance:    https://learn.microsoft.com/en-us/azure/migrate/troubleshoot-appliance" -ForegroundColor Cyan
    Write-Host "    Private Endpoints:         https://learn.microsoft.com/en-us/azure/migrate/how-to-use-azure-migrate-with-private-endpoints" -ForegroundColor Cyan
    Write-Host "    Troubleshoot Network:      https://learn.microsoft.com/en-us/azure/migrate/troubleshoot-network-connectivity" -ForegroundColor Cyan
    Write-Host "    Required URLs:             https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance#public-cloud-urls" -ForegroundColor Cyan
    Write-Host "    Port Access:               https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance#port-access" -ForegroundColor Cyan
    Write-Host ""
}

# ============================================================================
# EXPORT REPORT
# ============================================================================

function Export-DiagnosticReport {
    param(
        [string]$ResourceGroupName,
        [string]$Cloud,
        [bool]$UsesPrivateLink
    )

    $reportPath = Join-Path $PWD ("AzMigrate-CloudDiag_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $sb = [System.Text.StringBuilder]::new()

    [void]$sb.AppendLine("Azure Migrate - Cloud Shell Diagnostic Report")
    [void]$sb.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$sb.AppendLine("Resource Group: $ResourceGroupName")
    [void]$sb.AppendLine("Cloud: $Cloud")
    [void]$sb.AppendLine("Private Link: $UsesPrivateLink")
    [void]$sb.AppendLine("Subscription: $((Get-AzContext).Subscription.Name)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("=" * 60)
    [void]$sb.AppendLine("FAILURES ($($script:Findings.Count)):")
    [void]$sb.AppendLine("=" * 60)
    foreach ($f in $script:Findings) {
        [void]$sb.AppendLine("  [FAIL] $($f.Check)")
        [void]$sb.AppendLine("         $($f.Detail)")
        if ($f.Recommendation) { [void]$sb.AppendLine("         Action: $($f.Recommendation)") }
        if ($f.DocLink) { [void]$sb.AppendLine("         Doc: $($f.DocLink)") }
        [void]$sb.AppendLine("")
    }
    [void]$sb.AppendLine("=" * 60)
    [void]$sb.AppendLine("WARNINGS ($($script:Warnings.Count)):")
    [void]$sb.AppendLine("=" * 60)
    foreach ($w in $script:Warnings) {
        [void]$sb.AppendLine("  [WARN] $($w.Check)")
        [void]$sb.AppendLine("         $($w.Detail)")
        if ($w.Recommendation) { [void]$sb.AppendLine("         Action: $($w.Recommendation)") }
        [void]$sb.AppendLine("")
    }
    [void]$sb.AppendLine("=" * 60)
    [void]$sb.AppendLine("PASSED ($($script:Passed.Count)):")
    [void]$sb.AppendLine("=" * 60)
    foreach ($p in $script:Passed) {
        [void]$sb.AppendLine("  [PASS] $($p.Check) - $($p.Detail)")
    }

    try {
        $sb.ToString() | Out-File -FilePath $reportPath -Encoding UTF8 -Force
        Write-Host "    Report saved: $reportPath" -ForegroundColor Green
    } catch {
        Write-Host "    Could not save report: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ============================================================================
# MAIN
# ============================================================================

function Main {
    Write-Banner

    # Verify Az module
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        Write-Host "  [ERROR] Az PowerShell module not found. Run this in Azure Cloud Shell or install Az modules." -ForegroundColor Red
        return
    }

    # Authenticate
    $ctx = Test-AzContext
    if (-not $ctx) { return }

    # Determine cloud
    $cloudEnv = $ctx.Environment.Name
    $cloud = if ($cloudEnv -match 'Government|USGov') { 'Government' } else { 'Commercial' }
    Write-Host "    Detected cloud: $cloud" -ForegroundColor Gray

    # Prompt for resource group
    Write-Host ""
    $rgName = Read-Host "  Enter the Resource Group name containing your Azure Migrate project"
    if ([string]::IsNullOrWhiteSpace($rgName)) {
        Write-Host "  Resource group name is required." -ForegroundColor Red
        return
    }

    # Check if using private endpoints
    $plSel = Get-MenuSelection -Prompt "Are you using Private Endpoints with Azure Migrate?" `
        -Options @("No (public connectivity)", "Yes (private endpoints)")
    $usesPrivateLink = $plSel -eq 2

    # Prompt for appliance VNet resource group if different
    $vnetRG = ''
    if ($usesPrivateLink) {
        Write-Host ""
        $vnetRG = Read-Host "  Enter the Resource Group for the appliance VNet/NSGs (press Enter if same as above)"
        if ([string]::IsNullOrWhiteSpace($vnetRG)) { $vnetRG = $rgName }
    }

    Write-Host ""
    Write-Host "  Starting diagnostics..." -ForegroundColor Cyan
    Write-Host "  (This is read-only - no changes will be made)" -ForegroundColor Gray

    # Run checks
    $migrateResources = Test-MigrateProject -ResourceGroupName $rgName -ProjectName ''

    if ($migrateResources) {
        Test-ApplianceResources -ResourceGroupName $rgName -MigrateResources $migrateResources
    }

    if ($usesPrivateLink) {
        Test-PrivateEndpoints -ResourceGroupName $rgName
        Test-PrivateDnsZones -ResourceGroupName $rgName -Cloud $cloud

        if ($vnetRG -ne $rgName) {
            Test-PrivateEndpoints -ResourceGroupName $vnetRG
        }
    }

    $nsgRG = if ($vnetRG) { $vnetRG } else { $rgName }
    Test-NsgRules -ResourceGroupName $nsgRG

    Test-KeyVault -ResourceGroupName $rgName
    Test-StorageAccounts -ResourceGroupName $rgName
    Test-AzurePolicies -ResourceGroupName $rgName
    Test-ActivityLog -ResourceGroupName $rgName

    # Results
    Write-ResultsSummary
    Export-DiagnosticReport -ResourceGroupName $rgName -Cloud $cloud -UsesPrivateLink $usesPrivateLink

    Write-Host ""
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "  Diagnostics complete." -ForegroundColor Cyan
    Write-Host "  Share the report file with Microsoft Support if needed." -ForegroundColor Gray
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host ""
}

# Run
Main
