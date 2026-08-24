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

<#
.SYNOPSIS
    Azure Automation Runbook — starts Azure VMs on a schedule.
    Upload via Azure Cloud Shell using Setup-VMScheduling.ps1 — do not run directly.
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "",

    [Parameter(Mandatory = $false)]
    [string]$TagName = "AutoShutdown",

    [Parameter(Mandatory = $false)]
    [string]$TagValue = "true",

    [Parameter(Mandatory = $false)]
    [bool]$SkipWeekends = $true
)

# ── Connect via Automation Account's Managed Identity ────────────────────────
try {
    Connect-AzAccount -Identity | Out-Null
    Write-Output "Connected to Azure using Managed Identity."
}
catch {
    throw "Failed to connect to Azure: $_"
}

# ── Weekend guard ─────────────────────────────────────────────────────────────
if ($SkipWeekends) {
    $today = (Get-Date).DayOfWeek
    if ($today -eq 'Saturday' -or $today -eq 'Sunday') {
        Write-Output "Today is $today and weekend skip is enabled — no VMs will be started."
        return
    }
}

# ── Discover target VMs ───────────────────────────────────────────────────────
Write-Output "Finding VMs to start..."

if ($ResourceGroupName) {
    $vms = Get-AzVM -ResourceGroupName $ResourceGroupName
}
elseif ($TagName) {
    $vms = Get-AzVM | Where-Object { $_.Tags[$TagName] -eq $TagValue }
}
else {
    throw "Provide either ResourceGroupName or TagName."
}

if (-not $vms -or $vms.Count -eq 0) {
    Write-Output "No VMs found matching the selection criteria."
    return
}

Write-Output "Found $($vms.Count) VM(s)."

# ── Start each VM ─────────────────────────────────────────────────────────────
$started = 0
$skipped = 0
$failed  = 0

foreach ($vm in $vms) {
    # Fetch status individually to guarantee instance view is populated
    $vmStatus = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status
    $state    = ($vmStatus.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus

    if ($state -eq 'VM deallocated' -or $state -eq 'VM stopped') {
        Write-Output "  Starting: $($vm.Name)  [$($vm.ResourceGroupName)]"
        try {
            Start-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name | Out-Null
            Write-Output "    -> Started successfully."
            $started++
        }
        catch {
            Write-Warning "    -> FAILED to start $($vm.Name): $_"
            $failed++
        }
    }
    else {
        Write-Output "  Skipping: $($vm.Name) (state: $state)"
        $skipped++
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Output ""
Write-Output "=== Startup Summary $(Get-Date -Format 'yyyy-MM-dd HH:mm') ==="
Write-Output "  Started : $started"
Write-Output "  Skipped : $skipped  (already running)"
Write-Output "  Failed  : $failed"
