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
    One-time interactive setup: creates an Azure Automation Account, imports the
    two VM runbooks, and wires up daily stop/start schedules.

.REQUIREMENTS
    Run in Azure Cloud Shell (PowerShell mode) — do NOT run locally.
    Cloud Shell is already authenticated and has all required Az modules.
    Requires: Contributor or Owner on the target Azure subscription.

.USAGE
    1. Open Azure Portal -> click the Cloud Shell icon (>_) -> choose PowerShell
    2. Upload all 3 scripts using the Upload button in the Cloud Shell toolbar
    3. Run:  ./Setup-VMScheduling.ps1
    4. Follow the on-screen prompts.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ═══════════════════════════════════════════════════════════════════════════════
#  Helper functions
# ═══════════════════════════════════════════════════════════════════════════════

function Write-Header([string]$Title) {
    Write-Host ""
    Write-Host ("=" * 62) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("=" * 62) -ForegroundColor Cyan
}

function Read-Required {
    param([string]$Prompt, [string]$Default = "")
    do {
        $hint = if ($Default) { " [$Default]" } else { "" }
        $val  = (Read-Host "$Prompt$hint").Trim()
        if (-not $val -and $Default) { $val = $Default }
    } while (-not $val)
    return $val
}

function Read-Time([string]$Prompt) {
    do {
        $raw = (Read-Host $Prompt).Trim()
        if ($raw -match '^\d{1,2}:\d{2}$') {
            $h, $m = $raw -split ':' | ForEach-Object { [int]$_ }
            if ($h -ge 0 -and $h -le 23 -and $m -ge 0 -and $m -le 59) { return $raw }
        }
        Write-Host "  Invalid — use HH:MM in 24-hour format (e.g. 18:00 or 07:30)." -ForegroundColor Yellow
    } while ($true)
}

function Read-YesNo([string]$Prompt, [bool]$DefaultYes = $true) {
    $hint = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
    $ans  = (Read-Host "$Prompt $hint").Trim().ToUpper()
    if (-not $ans) { return $DefaultYes }
    return ($ans -eq 'Y')
}

function Select-Timezone {
    $zones = @(
        @{N=1; Id="Eastern Standard Time";          Label="Eastern  (ET) — New York, Washington D.C."}
        @{N=2; Id="Central Standard Time";           Label="Central  (CT) — Chicago, Dallas"}
        @{N=3; Id="Mountain Standard Time";          Label="Mountain (MT) — Denver, Phoenix"}
        @{N=4; Id="Pacific Standard Time";           Label="Pacific  (PT) — Los Angeles, Seattle"}
        @{N=5; Id="UTC";                             Label="UTC"}
        @{N=6; Id="__CUSTOM__";                      Label="Other — enter timezone ID manually"}
    )
    Write-Host ""
    Write-Host "  Select your timezone:"
    foreach ($z in $zones) { Write-Host ("  [{0}] {1}" -f $z.N, $z.Label) }
    do {
        $choice = (Read-Host "  Choice").Trim()
        $sel    = $zones | Where-Object { $_.N -eq [int]$choice }
    } while (-not $sel)

    if ($sel.Id -eq '__CUSTOM__') {
        Write-Host "  Tip: Get-TimeZone -ListAvailable | Select-Object Id" -ForegroundColor DarkGray
        return (Read-Required "  Enter full timezone ID")
    }
    return $sel.Id
}

function New-VMSchedule {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Name,
        [DateTime]$StartTime,
        [string]$TimeZone,
        [bool]$WeekdaysOnly
    )
    $existing = Get-AzAutomationSchedule -AutomationAccountName $script:aaName `
        -ResourceGroupName $script:aaRg -Name $Name -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-AzAutomationSchedule -AutomationAccountName $script:aaName `
            -ResourceGroupName $script:aaRg -Name $Name -Force | Out-Null
    }
    if ($WeekdaysOnly) {
        New-AzAutomationSchedule -AutomationAccountName $script:aaName `
            -ResourceGroupName $script:aaRg -Name $Name `
            -StartTime $StartTime -TimeZone $TimeZone `
            -WeekInterval 1 `
            -DaysOfWeek @('Monday','Tuesday','Wednesday','Thursday','Friday') | Out-Null
    }
    else {
        New-AzAutomationSchedule -AutomationAccountName $script:aaName `
            -ResourceGroupName $script:aaRg -Name $Name `
            -StartTime $StartTime -TimeZone $TimeZone `
            -DayInterval 1 | Out-Null
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════════════

Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   Azure VM Auto-Shutdown / Startup Setup     ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  This wizard will:"
Write-Host "    1. Create (or reuse) an Azure Automation Account"
Write-Host "    2. Grant it permission to manage your VMs"
Write-Host "    3. Upload the Stop and Start runbooks"
Write-Host "    4. Create daily schedules at the times you choose"
Write-Host ""
Write-Host "  Run in Azure Cloud Shell (PowerShell mode) — already signed in."

# ── Step 1: Confirm subscription ───────────────────────────────────────────────
Write-Header "Step 1 of 6 — Select Subscription"

# Cloud Shell is pre-authenticated; just confirm the active account
$ctx = Get-AzContext -ErrorAction SilentlyContinue
if (-not $ctx -or -not $ctx.Account) {
    Write-Host "  ERROR: No Azure context found. Ensure you are running in Azure Cloud Shell." -ForegroundColor Red
    exit 1
}
Write-Host "  Signed in as: $($ctx.Account.Id)" -ForegroundColor Green

Write-Host ""
Write-Host "  Available subscriptions:"
Get-AzSubscription | Select-Object Name, Id, State | Format-Table -AutoSize

$subId = Read-Required "  Enter Subscription ID"
Set-AzContext -SubscriptionId $subId | Out-Null
Write-Host "  Active subscription: $((Get-AzContext).Subscription.Name)" -ForegroundColor Green

# ── Step 2: Automation Account ────────────────────────────────────────────────
Write-Header "Step 2 of 6 — Azure Automation Account"
Write-Host "  The Automation Account hosts the scheduled runbooks."

$createNew = Read-YesNo "  Create a NEW Automation Account?"

if ($createNew) {
    $script:aaRg   = Read-Required "  Resource group name for Automation Account" "rg-vm-scheduler"
    $script:aaName = Read-Required "  Automation Account name" "vm-scheduler-auto"
    $location      = Read-Required "  Azure region" "eastus"

    Write-Host "  Creating resource group '$($script:aaRg)'..."
    New-AzResourceGroup -Name $script:aaRg -Location $location -Force | Out-Null

    Write-Host "  Creating Automation Account '$($script:aaName)'..."
    New-AzAutomationAccount -ResourceGroupName $script:aaRg -Name $script:aaName `
        -Location $location -Plan Basic | Out-Null
}
else {
    $script:aaRg   = Read-Required "  Resource group of existing Automation Account"
    $script:aaName = Read-Required "  Automation Account name"
}

# Enable system-assigned managed identity
Write-Host "  Enabling System-Assigned Managed Identity..."
$aaObj      = Set-AzAutomationAccount -ResourceGroupName $script:aaRg `
    -Name $script:aaName -AssignSystemIdentity
$principalId = $aaObj.Identity.PrincipalId
Write-Host "  Managed Identity Principal ID: $principalId" -ForegroundColor Green

# ── Step 3: Which VMs ─────────────────────────────────────────────────────────
Write-Header "Step 3 of 6 — Select VMs to Manage"
Write-Host ""
Write-Host "  [1] All VMs in a specific Resource Group"
Write-Host "  [2] VMs that have a specific Tag  (recommended for mixed environments)"
Write-Host ""
do {
    $vmMode = (Read-Host "  Choice").Trim()
} while ($vmMode -ne '1' -and $vmMode -ne '2')

if ($vmMode -eq '1') {
    $vmRg             = Read-Required "  VM Resource Group name"
    $tagName          = ""
    $tagValue         = ""
    $selectionMethod  = "ResourceGroup"
    $roleScope        = "/subscriptions/$subId/resourceGroups/$vmRg"
}
else {
    $vmRg             = ""
    $tagName          = Read-Required "  Tag name"  "AutoShutdown"
    $tagValue         = Read-Required "  Tag value" "true"
    $selectionMethod  = "Tag"
    $roleScope        = "/subscriptions/$subId"
    Write-Host ""
    Write-Host "  Remember to add the tag '$tagName = $tagValue' to each VM you want managed." -ForegroundColor Yellow
}

# ── Step 4: Assign Permissions ────────────────────────────────────────────────
Write-Header "Step 4 of 6 — Granting VM Permissions"
Write-Host "  Role  : Virtual Machine Contributor"
Write-Host "  Scope : $roleScope"
Write-Host ""

$existing = Get-AzRoleAssignment -ObjectId $principalId `
    -RoleDefinitionName "Virtual Machine Contributor" `
    -Scope $roleScope -ErrorAction SilentlyContinue

if ($existing) {
    Write-Host "  Role already assigned." -ForegroundColor Green
}
else {
    Write-Host "  Assigning role (may take 30-60 s to propagate)..."
    New-AzRoleAssignment -ObjectId $principalId `
        -RoleDefinitionName "Virtual Machine Contributor" `
        -Scope $roleScope | Out-Null
    Write-Host "  Role assigned." -ForegroundColor Green
}

# ── Step 5: Schedule times ────────────────────────────────────────────────────
Write-Header "Step 5 of 6 — Schedule Configuration"

$stopTime    = Read-Time "  Evening shutdown time (HH:MM, 24-hour, e.g. 18:00)"
$startTime   = Read-Time "  Morning startup  time (HH:MM, 24-hour, e.g. 07:30)"
$timezone    = Select-Timezone
$skipWeekend = Read-YesNo "  Skip weekends (Saturday + Sunday)?"

Write-Host ""
Write-Host "  Shutdown : $stopTime  |  Startup : $startTime  |  TZ : $timezone" -ForegroundColor Green
if ($skipWeekend) {
    Write-Host "  Runs     : Monday – Friday only" -ForegroundColor Green
}
else {
    Write-Host "  Runs     : Every day" -ForegroundColor Green
}

# ── Step 6: Import runbooks + create schedules ─────────────────────────────────
Write-Header "Step 6 of 6 — Uploading Runbooks & Creating Schedules"

$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
# Cloud Shell uploads land in $HOME (~/) by default
$stopRbFile  = Join-Path $scriptDir "Runbook-Stop-VMs.ps1"
$startRbFile = Join-Path $scriptDir "Runbook-Start-VMs.ps1"

foreach ($f in @($stopRbFile, $startRbFile)) {
    if (-not (Test-Path $f)) {
        Write-Host ""
        Write-Host "  ERROR: Required file not found:" -ForegroundColor Red
        Write-Host "    $f" -ForegroundColor Red
        Write-Host "  Make sure all 3 scripts are in the same folder." -ForegroundColor Red
        exit 1
    }
}

# Import runbooks
$runbooks = @(
    @{Path=$stopRbFile;  Name="Stop-AzureVMs";  Desc="Stops tagged/grouped Azure VMs on schedule"}
    @{Path=$startRbFile; Name="Start-AzureVMs"; Desc="Starts tagged/grouped Azure VMs on schedule"}
)
foreach ($rb in $runbooks) {
    Write-Host "  Importing runbook: $($rb.Name)..."
    Import-AzAutomationRunbook -Path $rb.Path `
        -AutomationAccountName $script:aaName `
        -ResourceGroupName $script:aaRg `
        -Name $rb.Name `
        -Description $rb.Desc `
        -Type PowerShell `
        -Published `
        -Force | Out-Null
    Write-Host "    Published OK." -ForegroundColor Green
}

# Build schedule start times (first occurrence = tomorrow)
$tomorrow   = (Get-Date).Date.AddDays(1)
$stopH, $stopM   = $stopTime  -split ':' | ForEach-Object { [int]$_ }
$startH, $startM = $startTime -split ':' | ForEach-Object { [int]$_ }
$firstStop  = $tomorrow.AddHours($stopH).AddMinutes($stopM)
$firstStart = $tomorrow.AddHours($startH).AddMinutes($startM)

# Create schedules
Write-Host "  Creating stop  schedule ($stopTime $timezone)..."
New-VMSchedule -Name "VM-Stop-Schedule"  -StartTime $firstStop  -TimeZone $timezone -WeekdaysOnly $skipWeekend

Write-Host "  Creating start schedule ($startTime $timezone)..."
New-VMSchedule -Name "VM-Start-Schedule" -StartTime $firstStart -TimeZone $timezone -WeekdaysOnly $skipWeekend

# Build runbook parameter hashtables
$commonParams = @{ SkipWeekends = $skipWeekend }
if ($selectionMethod -eq 'ResourceGroup') {
    $commonParams.ResourceGroupName = $vmRg
}
else {
    $commonParams.TagName  = $tagName
    $commonParams.TagValue = $tagValue
}

# Link runbooks to schedules
Write-Host "  Linking Stop-AzureVMs  -> VM-Stop-Schedule..."
Register-AzAutomationScheduledRunbook `
    -AutomationAccountName $script:aaName -ResourceGroupName $script:aaRg `
    -RunbookName "Stop-AzureVMs"  -ScheduleName "VM-Stop-Schedule"  -Parameters $commonParams | Out-Null

Write-Host "  Linking Start-AzureVMs -> VM-Start-Schedule..."
Register-AzAutomationScheduledRunbook `
    -AutomationAccountName $script:aaName -ResourceGroupName $script:aaRg `
    -RunbookName "Start-AzureVMs" -ScheduleName "VM-Start-Schedule" -Parameters $commonParams | Out-Null

# ── Done ───────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("=" * 62) -ForegroundColor Green
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host ("=" * 62) -ForegroundColor Green
Write-Host ""
Write-Host "  Automation Account : $($script:aaName)  (RG: $($script:aaRg))"
Write-Host "  VM Selection       : $selectionMethod"
if ($selectionMethod -eq 'ResourceGroup') {
    Write-Host "  VM Resource Group  : $vmRg"
}
else {
    Write-Host "  Tag Filter         : $tagName = $tagValue"
}
Write-Host "  Shutdown Time      : $stopTime  $timezone"
Write-Host "  Startup  Time      : $startTime  $timezone"
Write-Host "  Weekdays Only      : $skipWeekend"
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host "  1. Portal: Automation Account -> Modules"
Write-Host "     Confirm Az.Accounts and Az.Compute are listed (import if missing)."
Write-Host "  2. Do a test run: Runbooks -> Stop-AzureVMs -> Start (top toolbar)"
Write-Host "     Then check Jobs to see output and confirm VMs stopped."
Write-Host "  3. Monitor nightly: Automation Account -> Jobs -> filter by runbook."
if ($selectionMethod -eq 'Tag') {
    Write-Host ""
    Write-Host "  IMPORTANT: Add tag  $tagName = $tagValue  to each VM you want managed." -ForegroundColor Yellow
}
Write-Host ""
