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

#Requires -Version 5.1
<#
.SYNOPSIS
    Azure Migrate Appliance Connectivity Troubleshooter

.DESCRIPTION
    Read-only diagnostic tool that checks network connectivity requirements for Azure Migrate appliance
    registration and discovery. Tests required URLs and ports based on deployment scenario selections.

    THIS SCRIPT MAKES NO CHANGES TO THE ENVIRONMENT. It only reads configuration and tests connectivity.

    Supports:
    - Commercial Azure and Azure Government cloud
    - VMware Agentless, Agent-based Legacy, Agent-based Modern appliance scenarios
    - Assessment/Discovery and Replication appliance types
    - Public endpoint and Private Link connectivity
    - Proxy and firewall detection and reporting
    - Non-interactive mode when all parameters are provided
    - JSON structured output for automation/integration

.PARAMETER Cloud
    Azure cloud environment: Commercial (public) or Government.
    If not specified, prompts interactively.

.PARAMETER Scenario
    Deployment scenario: VMwareAgentless, AgentBasedLegacy, or AgentBasedModern.
    If not specified, prompts interactively.

.PARAMETER ApplianceType
    Appliance type: Assessment or Replication.
    If not specified, prompts interactively.

.PARAMETER PrivateLink
    Switch to indicate private link / private endpoint connectivity.

.PARAMETER OutputFormat
    Report format: Text (default) or JSON. JSON generates an additional machine-readable report file.

.EXAMPLE
    .\Invoke-AzMigrateConnectivityCheck.ps1
    Runs interactively with menu prompts.

.EXAMPLE
    .\Invoke-AzMigrateConnectivityCheck.ps1 -Cloud Commercial -Scenario VMwareAgentless -ApplianceType Assessment
    Runs non-interactively with specified parameters.

.EXAMPLE
    .\Invoke-AzMigrateConnectivityCheck.ps1 -Cloud Government -Scenario AgentBasedModern -ApplianceType Replication -PrivateLink -OutputFormat JSON
    Runs non-interactively for Gov cloud with private link and JSON output.

.NOTES
    Version:  1.1
    Requires: PowerShell 5.1+
    Author:   Azure Migrate Connectivity Checker (generated diagnostic tool)

.LINK
    https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance
    https://learn.microsoft.com/en-us/azure/migrate/simplified-experience-for-azure-migrate
#>

[CmdletBinding()]
param(
    [ValidateSet('Commercial','Government')]
    [string]$Cloud,

    [ValidateSet('VMwareAgentless','AgentBasedLegacy','AgentBasedModern')]
    [string]$Scenario,

    [ValidateSet('Assessment','Replication')]
    [string]$ApplianceType,

    [switch]$PrivateLink,

    [ValidateSet('Text','JSON')]
    [string]$OutputFormat = 'Text'
)

# ============================================================================
# CONFIGURATION
# ============================================================================
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
$script:TestResults    = [System.Collections.ArrayList]::new()
$script:Recommendations = [System.Collections.ArrayList]::new()
$script:Warnings       = [System.Collections.ArrayList]::new()
$script:ScriptVersion  = '1.1'
$script:TcpTimeoutMs   = 5000
$script:HttpTimeoutMs   = 10000
$script:OutputFormat   = $OutputFormat
$script:BoundParams    = $PSBoundParameters
$basePath = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$script:ReportPath     = Join-Path $basePath ("AzMigrate-ConnectivityReport_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$script:JsonReportPath = Join-Path $basePath ("AzMigrate-ConnectivityReport_{0}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

# Force TLS 1.2 (required by Azure services)
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
    Write-Warning "Failed to set TLS 1.2. Some tests may fail."
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Banner {
    $banner = @"
===============================================================================
  Azure Migrate Appliance - Connectivity Troubleshooter v$($script:ScriptVersion)
===============================================================================
  This tool checks network connectivity required for Azure Migrate appliance
  registration and operation. It tests DNS resolution, TCP connectivity, and
  HTTPS reachability for all required endpoints based on your deployment scenario.

  ** THIS TOOL IS READ-ONLY AND MAKES NO CHANGES TO YOUR ENVIRONMENT **

  Results will be saved to: $($script:ReportPath)
===============================================================================
"@
    Write-Host $banner -ForegroundColor Cyan
}

function Write-Section {
    param([string]$Title)
    $line = '=' * 78
    Write-Host ""
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor White
    Write-Host $line -ForegroundColor DarkCyan
}

function Write-SubSection {
    param([string]$Title)
    Write-Host ""
    Write-Host "  --- $Title ---" -ForegroundColor Yellow
}

function Get-MenuSelection {
    param(
        [string]$Prompt,
        [string[]]$Options,
        [string]$HelpText = ''
    )
    Write-Host ""
    if ($HelpText) { Write-Host "  $HelpText" -ForegroundColor Gray }
    Write-Host "  $Prompt" -ForegroundColor White
    Write-Host ""
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "    [$($i + 1)] $($Options[$i])" -ForegroundColor Yellow
    }
    Write-Host ""
    do {
        $userChoice = Read-Host "  Enter selection (1-$($Options.Count))"
        $sel = 0
        $valid = [int]::TryParse($userChoice, [ref]$sel) -and $sel -ge 1 -and $sel -le $Options.Count
        if (-not $valid) {
            Write-Host "  Invalid selection. Please enter a number between 1 and $($Options.Count)." -ForegroundColor Red
        }
    } while (-not $valid)
    return $sel
}

function Test-TcpPort {
    param(
        [string]$HostName,
        [int]$Port,
        [int]$TimeoutMs = $script:TcpTimeoutMs
    )
    $result = @{
        Success    = $false
        LatencyMs  = -1
        Error      = ''
    }
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $task = $client.ConnectAsync($HostName, $Port)
        $completed = $task.Wait($TimeoutMs)
        $sw.Stop()
        if ($completed -and -not $task.IsFaulted) {
            $result.Success   = $true
            $result.LatencyMs = $sw.ElapsedMilliseconds
        } else {
            if ($task.IsFaulted) {
                $result.Error = $task.Exception.InnerException.Message
            } else {
                $result.Error = "Connection timed out after ${TimeoutMs}ms"
            }
        }
    } catch {
        $result.Error = $_.Exception.Message
    } finally {
        if ($client) { $client.Dispose() }
    }
    return $result
}

function Test-DnsResolution {
    param(
        [string]$HostName,
        [int]$MaxRetries = 1
    )
    $result = @{
        Success   = $false
        Addresses = @()
        Error     = ''
    }
    for ($attempt = 0; $attempt -le $MaxRetries; $attempt++) {
        try {
            $addresses = [System.Net.Dns]::GetHostAddresses($HostName)
            if ($addresses.Count -gt 0) {
                $result.Success   = $true
                $result.Addresses = $addresses | ForEach-Object { $_.IPAddressToString }
                $result.Error     = ''
                return $result
            } else {
                $result.Error = "No addresses returned"
            }
        } catch {
            $result.Error = $_.Exception.Message
        }
        if ($attempt -lt $MaxRetries) {
            Start-Sleep -Milliseconds 500
        }
    }
    return $result
}

function Test-HttpsConnectivity {
    param(
        [string]$Url,
        [int]$TimeoutMs = $script:HttpTimeoutMs
    )
    $result = @{
        Success    = $false
        StatusCode = 0
        Error      = ''
        LatencyMs  = -1
        CertIssuer = ''
    }
    try {
        $uri = "https://$Url"
        $request = [System.Net.HttpWebRequest]::Create($uri)
        $request.Method  = 'GET'
        $request.Timeout = $TimeoutMs
        $request.AllowAutoRedirect = $true
        $request.UserAgent = 'AzureMigrateConnectivityChecker/1.0'

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $response = $request.GetResponse()
        $sw.Stop()

        $result.Success    = $true
        $result.StatusCode = [int]$response.StatusCode
        $result.LatencyMs  = $sw.ElapsedMilliseconds
        if ($request.ServicePoint.Certificate) {
            $result.CertIssuer = $request.ServicePoint.Certificate.Issuer
        }
        $response.Close()
        $response.Dispose()
    } catch [System.Net.WebException] {
        $sw.Stop()
        $result.LatencyMs = $sw.ElapsedMilliseconds
        $webEx = $_.Exception
        if ($webEx.Response) {
            # Got an HTTP response (401, 403, 404, etc.) - means network is reachable
            $result.StatusCode = [int]$webEx.Response.StatusCode
            # 401/403/404 etc. means the endpoint is reachable (auth required or not found)
            if ($result.StatusCode -in @(400, 401, 403, 404, 405, 406, 409, 412, 500, 502, 503)) {
                $result.Success = $true  # Network connectivity is working
            }
            $result.Error = "HTTP $($result.StatusCode): $($webEx.Message)"
            if ($webEx.Response -is [System.Net.HttpWebResponse]) {
                $webEx.Response.Close()
            }
        } else {
            $result.Error = $webEx.Message
            if ($webEx.InnerException) {
                $result.Error += " -> $($webEx.InnerException.Message)"
            }
        }
    } catch {
        $result.Error = $_.Exception.Message
    }
    return $result
}

function Add-TestResult {
    param(
        [string]$Url,
        [int]$Port,
        [string]$Purpose,
        [string]$WildcardPattern,
        [bool]$DnsPass,
        [string]$DnsDetail,
        [bool]$TcpPass,
        [string]$TcpDetail,
        [bool]$HttpsPass,
        [string]$HttpsDetail,
        [string]$Category
    )
    $overall = $DnsPass -and $TcpPass -and $HttpsPass
    [void]$script:TestResults.Add([PSCustomObject]@{
        Url             = $Url
        Port            = $Port
        Purpose         = $Purpose
        WildcardPattern = $WildcardPattern
        DnsPass         = $DnsPass
        DnsDetail       = $DnsDetail
        TcpPass         = $TcpPass
        TcpDetail       = $TcpDetail
        HttpsPass       = $HttpsPass
        HttpsDetail     = $HttpsDetail
        OverallPass     = $overall
        Category        = $Category
    })
}

# ============================================================================
# URL DEFINITIONS
# ============================================================================

function Get-UrlDefinitions {
    param(
        [ValidateSet('Commercial','Government')]
        [string]$Cloud,
        [ValidateSet('VMwareAgentless','AgentBasedLegacy','AgentBasedModern')]
        [string]$Scenario,
        [ValidateSet('Assessment','Replication')]
        [string]$ApplianceType,
        [bool]$PrivateLink
    )

    $urls = [System.Collections.ArrayList]::new()

    # ----- COMMERCIAL CLOUD -----
    if ($Cloud -eq 'Commercial') {

        if (-not $PrivateLink) {
            # ==========================================
            # PUBLIC CLOUD - PUBLIC ENDPOINTS
            # ==========================================

            if ($ApplianceType -eq 'Assessment' -or $Scenario -eq 'VMwareAgentless') {
                # Assessment/Discovery URLs (all scenarios)
                $assessmentUrls = @(
                    @{ Host='portal.azure.com';       Port=443; Purpose='Azure portal';                     Wildcard='*.portal.azure.com' }
                    @{ Host='login.microsoftonline.com'; Port=443; Purpose='Azure AD authentication';       Wildcard='login.microsoftonline.com' }
                    @{ Host='login.windows.net';      Port=443; Purpose='Azure AD authentication (alt)';    Wildcard='login.windows.net' }
                    @{ Host='graph.windows.net';      Port=443; Purpose='Azure AD Graph (legacy)';          Wildcard='*.windows.net' }
                    @{ Host='graph.microsoft.com';    Port=443; Purpose='Microsoft Graph';                  Wildcard='graph.microsoft.com' }
                    @{ Host='management.azure.com';   Port=443; Purpose='Azure Resource Manager';           Wildcard='management.azure.com' }
                    @{ Host='dc.services.visualstudio.com'; Port=443; Purpose='Application Insights telemetry'; Wildcard='*.services.visualstudio.com' }
                    @{ Host='vault.azure.net';        Port=443; Purpose='Azure Key Vault';                  Wildcard='*.vault.azure.net' }
                    @{ Host='servicebus.windows.net'; Port=443; Purpose='Azure Service Bus';                Wildcard='*.servicebus.windows.net' }
                    @{ Host='discoverysrv.windowsazure.com'; Port=443; Purpose='Azure Migrate Discovery service'; Wildcard='*.discoverysrv.windowsazure.com' }
                    @{ Host='migration.windowsazure.com';    Port=443; Purpose='Azure Migrate Migration service'; Wildcard='*.migration.windowsazure.com' }
                    @{ Host='hypervrecoverymanager.windowsazure.com'; Port=443; Purpose='Azure Site Recovery / Hyper-V Recovery Manager'; Wildcard='*.hypervrecoverymanager.windowsazure.com' }
                    @{ Host='blob.core.windows.net';  Port=443; Purpose='Azure Blob Storage';               Wildcard='*.blob.core.windows.net' }
                    @{ Host='aka.ms';                 Port=443; Purpose='Microsoft URL redirect service';    Wildcard='aka.ms' }
                    @{ Host='download.microsoft.com'; Port=443; Purpose='Microsoft downloads';               Wildcard='download.microsoft.com' }
                    @{ Host='prod.microsoftmetrics.com'; Port=443; Purpose='Azure Monitor metrics';          Wildcard='*.prod.microsoftmetrics.com' }
                    @{ Host='prod.hot.ingestion.msftcloudes.com'; Port=443; Purpose='Telemetry ingestion';   Wildcard='*.prod.hot.ingestion.msftcloudes.com' }
                )
                foreach ($u in $assessmentUrls) {
                    [void]$urls.Add(@{ Host=$u.Host; Port=$u.Port; Purpose=$u.Purpose; Wildcard=$u.Wildcard; Category='Assessment/Discovery' })
                }
            }

            if ($ApplianceType -eq 'Replication' -or $Scenario -eq 'VMwareAgentless') {
                if ($Scenario -eq 'VMwareAgentless') {
                    # VMware agentless migration needs IoT Hub + gateway
                    $agentlessMigUrls = @(
                        @{ Host='azure-devices.net'; Port=443; Purpose='Azure IoT Hub (migration gateway)'; Wildcard='*.azure-devices.net' }
                    )
                    foreach ($u in $agentlessMigUrls) {
                        [void]$urls.Add(@{ Host=$u.Host; Port=$u.Port; Purpose=$u.Purpose; Wildcard=$u.Wildcard; Category='VMware Agentless Migration' })
                    }
                }
            }

            if ($ApplianceType -eq 'Replication') {
                # Shared base URLs for agent-based replication (legacy and modern)
                $agentBasedBaseUrls = @(
                    @{ Host='hypervrecoverymanager.windowsazure.com'; Port=443; Purpose='Azure Recovery Services'; Wildcard='*.hypervrecoverymanager.windowsazure.com' }
                    @{ Host='management.azure.com';   Port=443; Purpose='Azure Resource Manager'; Wildcard='management.azure.com' }
                    @{ Host='login.microsoftonline.com'; Port=443; Purpose='Azure AD authentication'; Wildcard='login.microsoftonline.com' }
                    @{ Host='blob.core.windows.net';  Port=443; Purpose='Azure Blob Storage (replication data)'; Wildcard='*.blob.core.windows.net' }
                    @{ Host='backup.windowsazure.com'; Port=443; Purpose='Azure Backup service'; Wildcard='*.backup.windowsazure.com' }
                    @{ Host='aka.ms';                 Port=443; Purpose='Microsoft URL redirect service'; Wildcard='aka.ms' }
                    @{ Host='download.microsoft.com'; Port=443; Purpose='Microsoft downloads'; Wildcard='download.microsoft.com' }
                    @{ Host='dc.services.visualstudio.com'; Port=443; Purpose='Application Insights telemetry'; Wildcard='*.services.visualstudio.com' }
                    @{ Host='portal.azure.com';       Port=443; Purpose='Azure portal'; Wildcard='*.portal.azure.com' }
                    @{ Host='login.windows.net';      Port=443; Purpose='Azure AD authentication (alt)'; Wildcard='login.windows.net' }
                )

                if ($Scenario -eq 'AgentBasedLegacy') {
                    foreach ($u in $agentBasedBaseUrls) {
                        [void]$urls.Add(@{ Host=$u.Host; Port=$u.Port; Purpose=$u.Purpose; Wildcard=$u.Wildcard; Category='Agent-Based Legacy Replication' })
                    }
                }

                if ($Scenario -eq 'AgentBasedModern') {
                    foreach ($u in $agentBasedBaseUrls) {
                        [void]$urls.Add(@{ Host=$u.Host; Port=$u.Port; Purpose=$u.Purpose; Wildcard=$u.Wildcard; Category='Agent-Based Modern Replication' })
                    }
                    # Modern-specific endpoints
                    $modernExtras = @(
                        @{ Host='azure-devices.net';      Port=443; Purpose='Azure IoT Hub (modern appliance)'; Wildcard='*.azure-devices.net' }
                        @{ Host='prod.migration.windowsazure.com'; Port=443; Purpose='Modern migration service'; Wildcard='*.prod.migration.windowsazure.com' }
                    )
                    foreach ($u in $modernExtras) {
                        [void]$urls.Add(@{ Host=$u.Host; Port=$u.Port; Purpose=$u.Purpose; Wildcard=$u.Wildcard; Category='Agent-Based Modern Replication' })
                    }
                }
            }

        } else {
            # ==========================================
            # PUBLIC CLOUD - PRIVATE LINK ENDPOINTS
            # ==========================================
            $privateLinkUrls = @(
                @{ Host='portal.azure.com';       Port=443; Purpose='Azure portal';                     Wildcard='*.portal.azure.com' }
                @{ Host='login.windows.net';      Port=443; Purpose='Azure AD authentication';          Wildcard='login.windows.net' }
                @{ Host='login.microsoftonline.com'; Port=443; Purpose='Azure AD authentication';       Wildcard='*.microsoftonline.com' }
                @{ Host='login.microsoftonline-p.com'; Port=443; Purpose='Azure AD authentication (passive)'; Wildcard='*.microsoftonline-p.com' }
                @{ Host='management.azure.com';   Port=443; Purpose='Azure Resource Manager';           Wildcard='management.azure.com' }
                @{ Host='dc.services.visualstudio.com'; Port=443; Purpose='Application Insights';       Wildcard='*.services.visualstudio.com' }
                @{ Host='aka.ms';                 Port=443; Purpose='Microsoft URL redirect';            Wildcard='aka.ms' }
                @{ Host='download.microsoft.com'; Port=443; Purpose='Microsoft downloads';               Wildcard='download.microsoft.com' }
                @{ Host='vault.azure.net';        Port=443; Purpose='Azure Key Vault';                  Wildcard='*.vault.azure.net' }
                @{ Host='servicebus.windows.net'; Port=443; Purpose='Azure Service Bus';                Wildcard='*.servicebus.windows.net' }
                @{ Host='prod.migration.windowsazure.com'; Port=443; Purpose='Migration service (private link)'; Wildcard='*.prod.migration.windowsazure.com' }
                @{ Host='privatelink.prod.migration.windowsazure.com'; Port=443; Purpose='Private Link migration/auto-update service'; Wildcard='*.privatelink.prod.migration.windowsazure.com' }
                @{ Host='prod.microsoftmetrics.com'; Port=443; Purpose='Azure Monitor metrics';          Wildcard='*.prod.microsoftmetrics.com' }
                @{ Host='prod.hot.ingestion.msftcloudes.com'; Port=443; Purpose='Telemetry ingestion';   Wildcard='*.prod.hot.ingestion.msftcloudes.com' }
                @{ Host='blob.core.windows.net';  Port=443; Purpose='Azure Blob Storage';               Wildcard='*.blob.core.windows.net' }
                @{ Host='privatelink.blob.core.windows.net'; Port=443; Purpose='Private Link Blob Storage'; Wildcard='*.privatelink.blob.core.windows.net' }
                @{ Host='privatelink.vaultcore.azure.net'; Port=443; Purpose='Private Link Key Vault'; Wildcard='*.privatelink.vaultcore.azure.net' }
                @{ Host='privatelink.servicebus.windows.net'; Port=443; Purpose='Private Link Service Bus'; Wildcard='*.privatelink.servicebus.windows.net' }
            )
            foreach ($u in $privateLinkUrls) {
                [void]$urls.Add(@{ Host=$u.Host; Port=$u.Port; Purpose=$u.Purpose; Wildcard=$u.Wildcard; Category='Private Link (Public Cloud)' })
            }

            if ($Scenario -eq 'AgentBasedModern' -or $Scenario -eq 'VMwareAgentless') {
                [void]$urls.Add(@{ Host='azure-devices.net'; Port=443; Purpose='Azure IoT Hub (modern/agentless)'; Wildcard='*.azure-devices.net'; Category='Private Link - Modern/Agentless' })
            }
        }
    }

    # ----- GOVERNMENT CLOUD -----
    if ($Cloud -eq 'Government') {

        if (-not $PrivateLink) {
            # ==========================================
            # GOVERNMENT CLOUD - PUBLIC ENDPOINTS
            # ==========================================

            if ($ApplianceType -eq 'Assessment' -or $Scenario -eq 'VMwareAgentless') {
                $govAssessmentUrls = @(
                    @{ Host='portal.azure.us';        Port=443; Purpose='Azure Government portal';          Wildcard='*.portal.azure.us' }
                    @{ Host='login.microsoftonline.us'; Port=443; Purpose='Azure AD authentication (Gov)';  Wildcard='login.microsoftonline.us' }
                    @{ Host='graph.windows.net';      Port=443; Purpose='Azure AD Graph (legacy)';          Wildcard='graph.windows.net' }
                    @{ Host='graph.microsoft.com';    Port=443; Purpose='Microsoft Graph';                  Wildcard='graph.microsoft.com' }
                    @{ Host='management.usgovcloudapi.net'; Port=443; Purpose='Azure Resource Manager (Gov)'; Wildcard='management.usgovcloudapi.net' }
                    @{ Host='dc.applicationinsights.us'; Port=443; Purpose='Application Insights (Gov)';    Wildcard='dc.applicationinsights.us' }
                    @{ Host='vault.usgovcloudapi.net'; Port=443; Purpose='Azure Key Vault (Gov)';           Wildcard='*.vault.usgovcloudapi.net' }
                    @{ Host='servicebus.usgovcloudapi.net'; Port=443; Purpose='Azure Service Bus (Gov)';    Wildcard='*.servicebus.usgovcloudapi.net' }
                    @{ Host='discoverysrv.windowsazure.us'; Port=443; Purpose='Discovery service (Gov)';    Wildcard='*.discoverysrv.windowsazure.us' }
                    @{ Host='migration.windowsazure.us'; Port=443; Purpose='Migration service (Gov)';       Wildcard='*.migration.windowsazure.us' }
                    @{ Host='hypervrecoverymanager.windowsazure.us'; Port=443; Purpose='Recovery Manager (Gov)'; Wildcard='*.hypervrecoverymanager.windowsazure.us' }
                    @{ Host='blob.core.usgovcloudapi.net'; Port=443; Purpose='Azure Blob Storage (Gov)';    Wildcard='*.blob.core.usgovcloudapi.net' }
                    @{ Host='aka.ms';                 Port=443; Purpose='Microsoft URL redirect service';    Wildcard='aka.ms' }
                    @{ Host='download.microsoft.com'; Port=443; Purpose='Microsoft downloads';               Wildcard='download.microsoft.com' }
                    @{ Host='login.microsoftonline.com'; Port=443; Purpose='Azure AD (common endpoint)';     Wildcard='*.microsoftonline.com' }
                    @{ Host='login.microsoftonline-p.com'; Port=443; Purpose='Azure AD passive auth';        Wildcard='*.microsoftonline-p.com' }
                )
                foreach ($u in $govAssessmentUrls) {
                    [void]$urls.Add(@{ Host=$u.Host; Port=$u.Port; Purpose=$u.Purpose; Wildcard=$u.Wildcard; Category='Assessment/Discovery (Gov)' })
                }
            }

            if ($ApplianceType -eq 'Replication' -or $Scenario -eq 'VMwareAgentless') {
                if ($Scenario -eq 'VMwareAgentless') {
                    [void]$urls.Add(@{ Host='azure-devices.us'; Port=443; Purpose='Azure IoT Hub - migration gateway (Gov)'; Wildcard='*.azure-devices.us'; Category='VMware Agentless Migration (Gov)' })
                }
            }

            if ($ApplianceType -eq 'Replication') {
                # Shared base URLs for Gov agent-based replication (legacy and modern)
                $govAgentBaseUrls = @(
                    @{ Host='hypervrecoverymanager.windowsazure.us'; Port=443; Purpose='Recovery Services (Gov)'; Wildcard='*.hypervrecoverymanager.windowsazure.us' }
                    @{ Host='management.usgovcloudapi.net';  Port=443; Purpose='ARM (Gov)'; Wildcard='management.usgovcloudapi.net' }
                    @{ Host='login.microsoftonline.us';      Port=443; Purpose='Azure AD (Gov)'; Wildcard='login.microsoftonline.us' }
                    @{ Host='blob.core.usgovcloudapi.net';   Port=443; Purpose='Blob Storage (Gov)'; Wildcard='*.blob.core.usgovcloudapi.net' }
                    @{ Host='backup.windowsazure.us';        Port=443; Purpose='Backup service (Gov)'; Wildcard='*.backup.windowsazure.us' }
                    @{ Host='aka.ms';                        Port=443; Purpose='URL redirect'; Wildcard='aka.ms' }
                    @{ Host='download.microsoft.com';        Port=443; Purpose='Downloads'; Wildcard='download.microsoft.com' }
                    @{ Host='dc.applicationinsights.us';     Port=443; Purpose='App Insights (Gov)'; Wildcard='dc.applicationinsights.us' }
                    @{ Host='portal.azure.us';               Port=443; Purpose='Azure Gov portal'; Wildcard='*.portal.azure.us' }
                )

                if ($Scenario -eq 'AgentBasedLegacy') {
                    foreach ($u in $govAgentBaseUrls) {
                        [void]$urls.Add(@{ Host=$u.Host; Port=$u.Port; Purpose=$u.Purpose; Wildcard=$u.Wildcard; Category='Agent-Based Legacy Replication (Gov)' })
                    }
                }

                if ($Scenario -eq 'AgentBasedModern') {
                    foreach ($u in $govAgentBaseUrls) {
                        [void]$urls.Add(@{ Host=$u.Host; Port=$u.Port; Purpose=$u.Purpose; Wildcard=$u.Wildcard; Category='Agent-Based Modern Replication (Gov)' })
                    }
                    # Modern-specific Gov endpoints
                    $govModernExtras = @(
                        @{ Host='azure-devices.us';              Port=443; Purpose='IoT Hub (modern - Gov)'; Wildcard='*.azure-devices.us' }
                        @{ Host='prod.migration.windowsazure.us'; Port=443; Purpose='Modern migration service (Gov)'; Wildcard='*.prod.migration.windowsazure.us' }
                    )
                    foreach ($u in $govModernExtras) {
                        [void]$urls.Add(@{ Host=$u.Host; Port=$u.Port; Purpose=$u.Purpose; Wildcard=$u.Wildcard; Category='Agent-Based Modern Replication (Gov)' })
                    }
                }
            }

        } else {
            # ==========================================
            # GOVERNMENT CLOUD - PRIVATE LINK ENDPOINTS
            # ==========================================
            $govPrivateLinkUrls = @(
                @{ Host='portal.azure.us';        Port=443; Purpose='Azure Government portal';          Wildcard='*.portal.azure.us' }
                @{ Host='login.microsoftonline.us'; Port=443; Purpose='Azure AD (Gov)';                 Wildcard='login.microsoftonline.us' }
                @{ Host='graph.windows.net';      Port=443; Purpose='Azure AD Graph (legacy)';          Wildcard='graph.windows.net' }
                @{ Host='graph.microsoft.com';    Port=443; Purpose='Microsoft Graph';                  Wildcard='graph.microsoft.com' }
                @{ Host='management.usgovcloudapi.net'; Port=443; Purpose='ARM (Gov)';                  Wildcard='management.usgovcloudapi.net' }
                @{ Host='dc.applicationinsights.us'; Port=443; Purpose='App Insights (Gov)';            Wildcard='dc.applicationinsights.us' }
                @{ Host='vault.usgovcloudapi.net'; Port=443; Purpose='Key Vault (Gov)';                 Wildcard='*.vault.usgovcloudapi.net' }
                @{ Host='servicebus.usgovcloudapi.net'; Port=443; Purpose='Service Bus (Gov)';          Wildcard='*.servicebus.usgovcloudapi.net' }
                @{ Host='prod.migration.windowsazure.us'; Port=443; Purpose='Migration (Gov PL)';       Wildcard='*.prod.migration.windowsazure.us' }
                @{ Host='privatelink.prod.migration.windowsazure.us'; Port=443; Purpose='Private Link migration/auto-update service (Gov)'; Wildcard='*.privatelink.prod.migration.windowsazure.us' }
                @{ Host='blob.core.usgovcloudapi.net'; Port=443; Purpose='Blob Storage (Gov)';          Wildcard='*.blob.core.usgovcloudapi.net' }
                @{ Host='privatelink.blob.core.usgovcloudapi.net'; Port=443; Purpose='Private Link Blob Storage (Gov)'; Wildcard='*.privatelink.blob.core.usgovcloudapi.net' }
                @{ Host='aka.ms';                 Port=443; Purpose='URL redirect';                      Wildcard='aka.ms' }
                @{ Host='download.microsoft.com'; Port=443; Purpose='Downloads';                         Wildcard='download.microsoft.com' }
                @{ Host='login.microsoftonline.com'; Port=443; Purpose='Azure AD (common)';              Wildcard='*.microsoftonline.com' }
                @{ Host='login.microsoftonline-p.com'; Port=443; Purpose='Azure AD passive';             Wildcard='*.microsoftonline-p.com' }
            )
            foreach ($u in $govPrivateLinkUrls) {
                [void]$urls.Add(@{ Host=$u.Host; Port=$u.Port; Purpose=$u.Purpose; Wildcard=$u.Wildcard; Category='Private Link (Gov Cloud)' })
            }

            if ($Scenario -eq 'AgentBasedModern' -or $Scenario -eq 'VMwareAgentless') {
                [void]$urls.Add(@{ Host='azure-devices.us'; Port=443; Purpose='IoT Hub (modern/agentless - Gov)'; Wildcard='*.azure-devices.us'; Category='Private Link - Modern/Agentless (Gov)' })
            }
        }
    }

    # Deduplicate by Host+Port (keep first occurrence)
    $seen = @{}
    $dedupedUrls = [System.Collections.ArrayList]::new()
    foreach ($u in $urls) {
        $key = "$($u.Host):$($u.Port)"
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            [void]$dedupedUrls.Add($u)
        }
    }

    return ,$dedupedUrls
}

# ============================================================================
# ENVIRONMENT DETECTION
# ============================================================================

function Get-EnvironmentInfo {
    Write-Section "ENVIRONMENT INFORMATION (Read-Only)"

    # OS Info
    Write-SubSection "Operating System"
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        Write-Host "    OS:       $($os.Caption) $($os.Version)" -ForegroundColor Gray
        Write-Host "    Build:    $($os.BuildNumber)" -ForegroundColor Gray
    }
    Write-Host "    PS Ver:   $($PSVersionTable.PSVersion)" -ForegroundColor Gray

    # TLS Configuration
    Write-SubSection "TLS Configuration"
    $tlsProtocols = [Net.ServicePointManager]::SecurityProtocol
    Write-Host "    Active TLS protocols: $tlsProtocols" -ForegroundColor Gray
    if ($tlsProtocols -match 'Tls12') {
        Write-Host "    [PASS] TLS 1.2 is enabled" -ForegroundColor Green
    } else {
        Write-Host "    [FAIL] TLS 1.2 is NOT enabled - Azure services require TLS 1.2" -ForegroundColor Red
        [void]$script:Recommendations.Add("CRITICAL: TLS 1.2 is not enabled. Azure requires TLS 1.2. See: https://learn.microsoft.com/en-us/azure/migrate/troubleshoot-appliance#connectivity-issues")
    }

    # Check TLS 1.2 registry settings (read-only)
    $tls12ClientPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'
    if (Test-Path $tls12ClientPath) {
        $tls12Enabled = Get-ItemProperty -Path $tls12ClientPath -Name 'Enabled' -ErrorAction SilentlyContinue
        $tls12DisabledByDefault = Get-ItemProperty -Path $tls12ClientPath -Name 'DisabledByDefault' -ErrorAction SilentlyContinue
        if ($tls12Enabled -and $tls12Enabled.Enabled -eq 0) {
            Write-Host "    [WARN] TLS 1.2 Client is disabled in registry" -ForegroundColor Yellow
            [void]$script:Warnings.Add("TLS 1.2 is disabled in Windows registry (SCHANNEL). This will block Azure connectivity.")
        }
        if ($tls12DisabledByDefault -and $tls12DisabledByDefault.DisabledByDefault -eq 1) {
            Write-Host "    [WARN] TLS 1.2 Client is set to DisabledByDefault in registry" -ForegroundColor Yellow
        }
    }

    # Network adapters
    Write-SubSection "Network Configuration"
    try {
        $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
        foreach ($a in $adapters) {
            $ipConfig = Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $gateway = Get-NetRoute -InterfaceIndex $a.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -First 1
            $dns = Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            Write-Host "    Adapter:  $($a.Name) [$($a.InterfaceDescription)]" -ForegroundColor Gray
            Write-Host "    IP:       $(($ipConfig.IPAddress | Select-Object -First 1))" -ForegroundColor Gray
            if ($gateway) {
                Write-Host "    Gateway:  $($gateway.NextHop)" -ForegroundColor Gray
            }
            if ($dns -and $dns.ServerAddresses) {
                Write-Host "    DNS:      $($dns.ServerAddresses -join ', ')" -ForegroundColor Gray
            }
            Write-Host ""
        }
    } catch {
        Write-Host "    Unable to enumerate network adapters: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Get-ProxyConfiguration {
    Write-Section "PROXY CONFIGURATION (Read-Only)"

    $proxyDetected = $false

    # 1. WinHTTP proxy
    Write-SubSection "WinHTTP Proxy Settings"
    try {
        $winhttp = netsh winhttp show proxy 2>&1
        $winhttpStr = ($winhttp | Out-String).Trim()
        Write-Host "    $($winhttpStr -replace "`n", "`n    ")" -ForegroundColor Gray
        if ($winhttpStr -match 'Proxy Server.*:\s*(\S+)' -and $winhttpStr -notmatch 'Direct access') {
            $proxyDetected = $true
            [void]$script:Warnings.Add("WinHTTP proxy detected. Ensure Azure Migrate required URLs are allowed through the proxy.")
        }
    } catch {
        Write-Host "    Unable to query WinHTTP proxy: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # 2. System (IE) proxy settings
    Write-SubSection "Internet Explorer / System Proxy Settings"
    try {
        $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        $proxyEnable = (Get-ItemProperty -Path $regPath -Name 'ProxyEnable' -ErrorAction SilentlyContinue).ProxyEnable
        $proxyServer = (Get-ItemProperty -Path $regPath -Name 'ProxyServer' -ErrorAction SilentlyContinue).ProxyServer
        $proxyOverride = (Get-ItemProperty -Path $regPath -Name 'ProxyOverride' -ErrorAction SilentlyContinue).ProxyOverride
        $autoConfigUrl = (Get-ItemProperty -Path $regPath -Name 'AutoConfigURL' -ErrorAction SilentlyContinue).AutoConfigURL

        Write-Host "    Proxy Enabled:  $($proxyEnable -eq 1)" -ForegroundColor Gray
        Write-Host "    Proxy Server:   $proxyServer" -ForegroundColor Gray
        Write-Host "    Proxy Bypass:   $proxyOverride" -ForegroundColor Gray
        Write-Host "    PAC URL:        $autoConfigUrl" -ForegroundColor Gray

        if ($proxyEnable -eq 1 -and $proxyServer) {
            $proxyDetected = $true
            [void]$script:Warnings.Add("System proxy is configured: $proxyServer. Ensure Azure Migrate URLs are in the proxy allowlist.")
        }
        if ($autoConfigUrl) {
            $proxyDetected = $true
            [void]$script:Warnings.Add("PAC (Proxy Auto-Config) URL detected: $autoConfigUrl. Verify PAC script allows Azure Migrate URLs.")
        }
    } catch {
        Write-Host "    Unable to read IE proxy settings: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # 3. Environment variables
    Write-SubSection "Environment Variable Proxy Settings"
    $envVars = @('HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY', 'http_proxy', 'https_proxy', 'no_proxy')
    foreach ($var in $envVars) {
        $val = [Environment]::GetEnvironmentVariable($var)
        if ($val) {
            Write-Host "    $var = $val" -ForegroundColor Gray
            if ($var -notlike '*NO_PROXY*' -and $var -notlike '*no_proxy*') {
                $proxyDetected = $true
            }
        }
    }
    if (-not ($envVars | Where-Object { [Environment]::GetEnvironmentVariable($_) })) {
        Write-Host "    No proxy environment variables set." -ForegroundColor Gray
    }

    # 4. .NET default proxy
    Write-SubSection ".NET Default Proxy"
    try {
        $defaultProxy = [System.Net.WebRequest]::DefaultWebProxy
        if ($defaultProxy) {
            $testUri = [System.Uri]"https://management.azure.com"
            $proxyUri = $defaultProxy.GetProxy($testUri)
            if ($proxyUri -and $proxyUri.AbsoluteUri -ne $testUri.AbsoluteUri) {
                Write-Host "    .NET proxy for management.azure.com: $($proxyUri.AbsoluteUri)" -ForegroundColor Gray
                $proxyDetected = $true
                [void]$script:Warnings.Add(".NET default proxy routes Azure traffic through: $($proxyUri.AbsoluteUri)")
            } else {
                Write-Host "    .NET uses direct connection for Azure endpoints." -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host "    Unable to detect .NET proxy: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Summary
    Write-Host ""
    if ($proxyDetected) {
        Write-Host "    [WARN] Proxy configuration detected. This may affect Azure Migrate connectivity." -ForegroundColor Yellow
        Write-Host "    Ensure all required Azure Migrate URLs are allowed through your proxy." -ForegroundColor Yellow
        [void]$script:Recommendations.Add(@"
PROXY DETECTED: A proxy server is configured on this machine. If Azure Migrate appliance
registration or discovery is failing, ensure the proxy allows HTTPS (port 443) traffic to all
required Azure Migrate endpoints. You may need to configure proxy settings on the appliance.
See: https://learn.microsoft.com/en-us/azure/migrate/troubleshoot-appliance#connectivity-issues
See: https://learn.microsoft.com/en-us/azure/migrate/how-to-set-up-appliance-vmware#configure-the-appliance
"@)
    } else {
        Write-Host "    [INFO] No proxy configuration detected." -ForegroundColor Green
    }

    return $proxyDetected
}

function Test-BasicConnectivity {
    Write-Section "BASIC CONNECTIVITY CHECKS"

    # 1. Default gateway
    Write-SubSection "Default Gateway Reachability"
    try {
        $gateway = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($gateway -and $gateway.NextHop -ne '0.0.0.0') {
            $pingResult = Test-Connection -ComputerName $gateway.NextHop -Count 1 -ErrorAction SilentlyContinue
            if ($pingResult) {
                Write-Host "    [PASS] Default gateway $($gateway.NextHop) is reachable" -ForegroundColor Green
            } else {
                Write-Host "    [WARN] Default gateway $($gateway.NextHop) did not respond to ping (may be normal if ICMP is blocked)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "    [WARN] No default gateway found - check network configuration" -ForegroundColor Yellow
            [void]$script:Warnings.Add("No default gateway detected. The machine may not have internet connectivity.")
        }
    } catch {
        Write-Host "    Unable to check gateway: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # 2. DNS server reachability
    Write-SubSection "DNS Server Reachability"
    try {
        $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.ServerAddresses } |
            Select-Object -ExpandProperty ServerAddresses -Unique |
            Select-Object -First 4
        foreach ($dns in $dnsServers) {
            $tcpResult = Test-TcpPort -HostName $dns -Port 53 -TimeoutMs 3000
            if ($tcpResult.Success) {
                Write-Host "    [PASS] DNS server $dns is reachable on TCP/53" -ForegroundColor Green
            } else {
                Write-Host "    [WARN] DNS server $dns TCP/53 test failed (UDP may still work): $($tcpResult.Error)" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "    Unable to check DNS servers: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # 3. General internet connectivity
    Write-SubSection "General Internet Connectivity (microsoft.com)"
    $dnsTest = Test-DnsResolution -HostName 'www.microsoft.com'
    $tcpTest = Test-TcpPort -HostName 'www.microsoft.com' -Port 443
    if ($dnsTest.Success -and $tcpTest.Success) {
        Write-Host "    [PASS] DNS and TCP/443 to www.microsoft.com succeeded ($($tcpTest.LatencyMs)ms)" -ForegroundColor Green
    } elseif (-not $dnsTest.Success) {
        Write-Host "    [FAIL] Cannot resolve www.microsoft.com - DNS resolution failed" -ForegroundColor Red
        Write-Host "           Error: $($dnsTest.Error)" -ForegroundColor Red
        [void]$script:Recommendations.Add("DNS resolution is failing for common domains. Check DNS server configuration and connectivity.")
    } else {
        Write-Host "    [FAIL] DNS resolved but TCP/443 failed to www.microsoft.com" -ForegroundColor Red
        Write-Host "           Error: $($tcpTest.Error)" -ForegroundColor Red
        [void]$script:Recommendations.Add("TCP connectivity to port 443 is failing even for microsoft.com. This indicates a firewall or network issue blocking outbound HTTPS.")
    }

    # 4. TLS 1.2 handshake test
    Write-SubSection "TLS 1.2 Handshake Test"
    $httpsResult = Test-HttpsConnectivity -Url 'www.microsoft.com'
    if ($httpsResult.Success) {
        Write-Host "    [PASS] HTTPS/TLS handshake to www.microsoft.com succeeded (HTTP $($httpsResult.StatusCode), $($httpsResult.LatencyMs)ms)" -ForegroundColor Green
        if ($httpsResult.CertIssuer) {
            Write-Host "    Certificate Issuer: $($httpsResult.CertIssuer)" -ForegroundColor Gray
            # Check for SSL inspection
            if ($httpsResult.CertIssuer -notmatch 'Microsoft|DigiCert|Baltimore|GlobalSign|Symantec|GeoTrust|Comodo|Let.s Encrypt|Sectigo|Entrust|AffirmTrust|IdenTrust|ISRG') {
                Write-Host "    [WARN] Certificate issuer may indicate SSL inspection / MITM proxy" -ForegroundColor Yellow
                [void]$script:Warnings.Add("SSL inspection detected (cert issuer: $($httpsResult.CertIssuer)). This may interfere with Azure Migrate.")
                [void]$script:Recommendations.Add(@"
SSL INSPECTION DETECTED: The certificate issuer for microsoft.com suggests SSL/TLS inspection
is active (possibly a corporate proxy). This can interfere with Azure Migrate appliance
certificate pinning and connectivity. Consider bypassing SSL inspection for Azure Migrate URLs.
See: https://learn.microsoft.com/en-us/azure/migrate/troubleshoot-appliance#connectivity-issues
"@)
            }
        }
    } else {
        Write-Host "    [FAIL] HTTPS to www.microsoft.com failed: $($httpsResult.Error)" -ForegroundColor Red
        [void]$script:Recommendations.Add("HTTPS/TLS connections are failing. This blocks all Azure Migrate communication. Check firewall, proxy, and TLS settings.")
    }
}

# ============================================================================
# LOCAL FIREWALL CHECK (Read-Only)
# ============================================================================

function Test-LocalFirewall {
    Write-Section "LOCAL WINDOWS FIREWALL STATUS (Read-Only)"

    try {
        $fwProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
        foreach ($fwProfile in $fwProfiles) {
            $status = if ($fwProfile.Enabled) { "Enabled" } else { "Disabled" }
            $color  = if ($fwProfile.Enabled) { "Yellow" } else { "Gray" }
            Write-Host "    $($fwProfile.Name) Profile: $status (Default Outbound: $($fwProfile.DefaultOutboundAction))" -ForegroundColor $color
            if ($fwProfile.Enabled -and $fwProfile.DefaultOutboundAction -eq 'Block') {
                [void]$script:Warnings.Add("Windows Firewall '$($fwProfile.Name)' profile has default outbound action set to BLOCK. This will block Azure Migrate unless explicit allow rules exist.")
                [void]$script:Recommendations.Add(@"
FIREWALL OUTBOUND BLOCK: The Windows Firewall $($fwProfile.Name) profile is set to block outbound
traffic by default. Ensure outbound rules exist to allow TCP/443 to Azure Migrate endpoints.
This is a LOCAL firewall issue (not network/corporate firewall).
"@)
            }
        }
    } catch {
        Write-Host "    Unable to check Windows Firewall status: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ============================================================================
# MAIN CONNECTIVITY TEST ENGINE
# ============================================================================

function Invoke-ConnectivityTests {
    param(
        [System.Collections.ArrayList]$UrlList
    )

    Write-Section "ENDPOINT CONNECTIVITY TESTS"
    Write-Host ""
    Write-Host "  Testing $($UrlList.Count) endpoints. This may take a few minutes..." -ForegroundColor White
    Write-Host "  (Simulating the same HTTPS calls the Azure Migrate appliance makes)" -ForegroundColor Gray
    Write-Host ""

    $currentCategory = ''
    $totalCount = $UrlList.Count
    $currentIndex = 0

    foreach ($entry in $UrlList) {
        $currentIndex++

        if ($entry.Category -ne $currentCategory) {
            $currentCategory = $entry.Category
            Write-SubSection "$currentCategory"
        }

        $host_ = $entry.Host
        $port  = $entry.Port
        $pct   = [math]::Round(($currentIndex / $totalCount) * 100)
        Write-Progress -Activity "Testing Azure Migrate Endpoints" -Status "[$currentIndex/$totalCount] $($host_):$port" -PercentComplete $pct

        Write-Host "    [$currentIndex/$totalCount] Testing $($host_):$port ... " -NoNewline -ForegroundColor White

        # DNS Test
        $dnsResult = Test-DnsResolution -HostName $host_
        $dnsPass   = $dnsResult.Success
        $dnsDetail = if ($dnsPass) { "Resolved: $($dnsResult.Addresses -join ', ')" } else { $dnsResult.Error }

        # TCP Test
        $tcpPass   = $false
        $tcpDetail = 'Skipped (DNS failed)'
        if ($dnsPass) {
            $tcpResult = Test-TcpPort -HostName $host_ -Port $port
            $tcpPass   = $tcpResult.Success
            $tcpDetail = if ($tcpPass) { "Connected in $($tcpResult.LatencyMs)ms" } else { $tcpResult.Error }
        }

        # HTTPS Test
        $httpsPass   = $false
        $httpsDetail = 'Skipped (TCP failed)'
        if ($tcpPass) {
            $httpsResult = Test-HttpsConnectivity -Url $host_
            $httpsPass   = $httpsResult.Success
            if ($httpsPass) {
                $httpsDetail = "HTTP $($httpsResult.StatusCode) in $($httpsResult.LatencyMs)ms"
                if ($httpsResult.CertIssuer) { $httpsDetail += " [Cert: $($httpsResult.CertIssuer)]" }
            } else {
                $httpsDetail = $httpsResult.Error
            }
        } elseif ($dnsPass -and -not $tcpPass) {
            $httpsDetail = 'Skipped (TCP connection failed - likely firewall block)'
        }

        # Overall status
        $overall = $dnsPass -and $tcpPass -and $httpsPass
        if ($overall) {
            Write-Host "PASS" -ForegroundColor Green
        } elseif (-not $dnsPass) {
            Write-Host "FAIL (DNS)" -ForegroundColor Red
        } elseif (-not $tcpPass) {
            Write-Host "FAIL (TCP BLOCKED)" -ForegroundColor Red
        } else {
            Write-Host "FAIL (HTTPS)" -ForegroundColor Red
        }

        # Store result
        Add-TestResult -Url $host_ -Port $port -Purpose $entry.Purpose -WildcardPattern $entry.Wildcard `
            -DnsPass $dnsPass -DnsDetail $dnsDetail `
            -TcpPass $tcpPass -TcpDetail $tcpDetail `
            -HttpsPass $httpsPass -HttpsDetail $httpsDetail `
            -Category $entry.Category
    }
    Write-Progress -Activity "Testing Azure Migrate Endpoints" -Completed
}

# ============================================================================
# RESULTS REPORTING
# ============================================================================

function Write-ResultsSummary {
    param(
        [string]$Cloud,
        [string]$Scenario,
        [string]$ApplianceType,
        [bool]$PrivateLink
    )

    $failed = $script:TestResults | Where-Object { -not $_.OverallPass }
    $passed = $script:TestResults | Where-Object { $_.OverallPass }
    $dnsFails  = $script:TestResults | Where-Object { -not $_.DnsPass }
    $tcpFails  = $script:TestResults | Where-Object { $_.DnsPass -and -not $_.TcpPass }
    $httpFails = $script:TestResults | Where-Object { $_.DnsPass -and $_.TcpPass -and -not $_.HttpsPass }

    Write-Section "RESULTS SUMMARY"
    Write-Host ""
    Write-Host "  Configuration Tested:" -ForegroundColor White
    Write-Host "    Cloud:          $Cloud" -ForegroundColor Gray
    Write-Host "    Scenario:       $Scenario" -ForegroundColor Gray
    Write-Host "    Appliance Type: $ApplianceType" -ForegroundColor Gray
    Write-Host "    Private Link:   $PrivateLink" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Total Endpoints Tested: $($script:TestResults.Count)" -ForegroundColor White
    Write-Host "    Passed: $($passed.Count)" -ForegroundColor Green
    Write-Host "    Failed: $($failed.Count)" -ForegroundColor $(if ($failed.Count -gt 0) { 'Red' } else { 'Green' })
    Write-Host ""

    if ($dnsFails.Count -gt 0) {
        Write-Host "  DNS Resolution Failures ($($dnsFails.Count)):" -ForegroundColor Red
        foreach ($f in $dnsFails) {
            Write-Host "    [DNS FAIL] $($f.Url):$($f.Port) - $($f.Purpose)" -ForegroundColor Red
            Write-Host "               Wildcard: $($f.WildcardPattern)" -ForegroundColor DarkGray
            Write-Host "               Error: $($f.DnsDetail)" -ForegroundColor DarkGray
            Write-Host "               NOTE: Wildcard base domains may not resolve directly." -ForegroundColor DarkGray
            Write-Host "               Ensure '$($f.WildcardPattern)' is resolvable from your DNS." -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    if ($tcpFails.Count -gt 0) {
        Write-Host "  TCP Connection Failures ($($tcpFails.Count)) - LIKELY FIREWALL/PROXY BLOCK:" -ForegroundColor Red
        foreach ($f in $tcpFails) {
            Write-Host "    [TCP BLOCKED] $($f.Url):$($f.Port) - $($f.Purpose)" -ForegroundColor Red
            Write-Host "                  Wildcard: $($f.WildcardPattern)" -ForegroundColor DarkGray
            Write-Host "                  Resolved IP: $($f.DnsDetail)" -ForegroundColor DarkGray
            Write-Host "                  Error: $($f.TcpDetail)" -ForegroundColor DarkGray
        }
        Write-Host ""
        [void]$script:Recommendations.Add(@"
TCP CONNECTION BLOCKED: $($tcpFails.Count) endpoint(s) resolved via DNS but TCP connection on
port 443 was refused or timed out. This typically indicates:
  1. A network firewall is blocking outbound TCP/443 to these specific destinations
  2. A proxy server is not forwarding traffic to these endpoints
  3. Network Security Groups (NSGs) or route tables are blocking traffic

ACTION: Review your firewall/proxy rules and ensure outbound TCP/443 is allowed to:
$( ($tcpFails | ForEach-Object { "  - $($_.WildcardPattern) ($($_.Purpose))" }) -join "`n" )

See: https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance#port-access
"@)
    }

    if ($httpFails.Count -gt 0) {
        Write-Host "  HTTPS/TLS Failures ($($httpFails.Count)) - POSSIBLE SSL INSPECTION OR PROXY ISSUE:" -ForegroundColor Yellow
        foreach ($f in $httpFails) {
            Write-Host "    [HTTPS FAIL] $($f.Url):$($f.Port) - $($f.Purpose)" -ForegroundColor Yellow
            Write-Host "                 Error: $($f.HttpsDetail)" -ForegroundColor DarkGray
        }
        Write-Host ""
        [void]$script:Recommendations.Add(@"
HTTPS/TLS FAILURES: $($httpFails.Count) endpoint(s) connected on TCP/443 but the HTTPS
handshake or request failed. This typically indicates:
  1. SSL/TLS inspection (MITM proxy) is interfering with the connection
  2. The proxy requires authentication that was not provided
  3. Certificate validation is failing due to missing root CAs
  4. TLS version mismatch (Azure requires TLS 1.2)

ACTION: Check if SSL inspection is enabled for Azure Migrate endpoints and consider
creating bypass rules for these URLs. Ensure TLS 1.2 is enabled.
See: https://learn.microsoft.com/en-us/azure/migrate/troubleshoot-appliance#connectivity-issues
"@)
    }

    if ($failed.Count -eq 0) {
        Write-Host "  ALL ENDPOINTS PASSED CONNECTIVITY CHECKS" -ForegroundColor Green
        Write-Host ""
        Write-Host "  All required Azure Migrate endpoints are reachable from this machine." -ForegroundColor Green
        Write-Host "  If you are still experiencing issues with the Azure Migrate appliance," -ForegroundColor Gray
        Write-Host "  the problem may be specific to the appliance software or configuration." -ForegroundColor Gray
    }
}

function Write-Recommendations {
    param(
        [string]$Cloud,
        [string]$Scenario,
        [string]$ApplianceType,
        [bool]$PrivateLink
    )

    Write-Section "RECOMMENDATIONS AND GUIDANCE"

    # Scenario-specific doc links
    $docLinks = @{
        'PublicCloudUrls'      = 'https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance#public-cloud-urls'
        'GovCloudUrls'         = 'https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance#government-cloud-urls'
        'PublicPrivateLink'    = 'https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance#public-cloud-urls-for-private-link-connectivity'
        'GovPrivateLink'       = 'https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance#government-cloud-urls-for-private-link-connectivity'
        'DeploymentScenarios'  = 'https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance#deployment-scenarios'
        'SimplifiedExperience' = 'https://learn.microsoft.com/en-us/azure/migrate/simplified-experience-for-azure-migrate'
        'TroubleshootAppliance'= 'https://learn.microsoft.com/en-us/azure/migrate/troubleshoot-appliance'
        'PortAccess'           = 'https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance#port-access'
        'ApplianceSetup'       = 'https://learn.microsoft.com/en-us/azure/migrate/how-to-set-up-appliance-vmware'
        'CommonQuestions'       = 'https://learn.microsoft.com/en-us/azure/migrate/common-questions-appliance'
        'PrivateLinkSetup'     = 'https://learn.microsoft.com/en-us/azure/migrate/how-to-use-azure-migrate-with-private-endpoints'
        'AgentBasedMigration'  = 'https://learn.microsoft.com/en-us/azure/migrate/agent-based-migration-architecture'
        'ModernAppliance'      = 'https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance'
        'TroubleshootNetwork'  = 'https://learn.microsoft.com/en-us/azure/migrate/troubleshoot-network-connectivity'
    }

    # Print collected recommendations
    if ($script:Recommendations.Count -gt 0) {
        Write-SubSection "Issues Found"
        for ($i = 0; $i -lt $script:Recommendations.Count; $i++) {
            Write-Host ""
            Write-Host "  [$($i + 1)] $($script:Recommendations[$i])" -ForegroundColor Yellow
        }
    }

    # Print collected warnings
    if ($script:Warnings.Count -gt 0) {
        Write-SubSection "Warnings"
        foreach ($w in $script:Warnings) {
            Write-Host "  [!] $w" -ForegroundColor Yellow
        }
    }

    # General guidance
    Write-SubSection "General Troubleshooting Steps"
    Write-Host @"
  If connectivity tests above show failures, follow these steps:

  1. FIREWALL RULES: Ensure your corporate/network firewall allows outbound TCP/443
     to all required Azure Migrate URLs listed above. Work with your network team
     to add firewall allow rules for the wildcard patterns listed.

  2. PROXY CONFIGURATION: If using a proxy, ensure:
     a. The proxy allows HTTPS traffic to Azure Migrate endpoints
     b. The appliance is configured with correct proxy settings
     c. Proxy authentication credentials are correct (if required)
     d. SSL inspection is bypassed for Azure Migrate URLs

  3. DNS RESOLUTION: If DNS failures occur:
     a. Verify DNS servers are reachable and configured correctly
     b. Check if DNS filtering/security products block Azure domains
     c. Try using Azure DNS (168.63.129.16) or public DNS (8.8.8.8) for comparison

  4. TLS CONFIGURATION: Azure services require TLS 1.2:
     a. Ensure TLS 1.2 is enabled in Windows (SCHANNEL registry settings)
     b. Ensure .NET Framework is configured to use TLS 1.2
     c. Check for Group Policy settings that may restrict TLS versions

  5. PRIVATE ENDPOINTS: If using private link:
     a. Verify private DNS zones are configured correctly
     b. Ensure private endpoint connections are approved
     c. Verify DNS resolution returns private IP addresses
     d. The auto-update manifest URL (e.g., <guid>-agent.uga.disc.privatelink.prod.migration.windowsazure.us)
        MUST resolve through the privatelink.prod.migration.windowsazure.us (or .com) private DNS zone
     e. If auto-update fails with "service endpoint unreachable", the privatelink DNS zone is likely
        missing the A record for your project-specific FQDN or the zone is not linked to your VNet

  6. APPLIANCE AUTO-UPDATE ISSUES:
     If auto-update fails with "service endpoint ... is unreachable":
     a. The URL contains a project-specific GUID (e.g., de995fbb-...-agent.uga.disc.privatelink...)
     b. For PRIVATE LINK: Ensure the privatelink.prod.migration.windowsazure.us (Gov) or
        privatelink.prod.migration.windowsazure.com (Commercial) DNS zone is properly configured
     c. For PUBLIC endpoints: Ensure firewall allows *.prod.migration.windowsazure.us/.com on TCP/443
     d. Paste the exact failing URL into this tool's custom URL prompt to test it directly
     e. See: https://learn.microsoft.com/en-us/azure/migrate/troubleshoot-appliance
"@ -ForegroundColor Gray

    # Relevant documentation links
    Write-SubSection "Relevant Documentation"
    Write-Host ""
    Write-Host "  Deployment Scenarios:" -ForegroundColor White
    Write-Host "    $($docLinks.DeploymentScenarios)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Simplified (Modern) Experience:" -ForegroundColor White
    Write-Host "    $($docLinks.SimplifiedExperience)" -ForegroundColor Cyan
    Write-Host ""

    if ($Cloud -eq 'Commercial') {
        if ($PrivateLink) {
            Write-Host "  Required URLs (Public Cloud - Private Link):" -ForegroundColor White
            Write-Host "    $($docLinks.PublicPrivateLink)" -ForegroundColor Cyan
        } else {
            Write-Host "  Required URLs (Public Cloud):" -ForegroundColor White
            Write-Host "    $($docLinks.PublicCloudUrls)" -ForegroundColor Cyan
        }
    } else {
        if ($PrivateLink) {
            Write-Host "  Required URLs (Government Cloud - Private Link):" -ForegroundColor White
            Write-Host "    $($docLinks.GovPrivateLink)" -ForegroundColor Cyan
        } else {
            Write-Host "  Required URLs (Government Cloud):" -ForegroundColor White
            Write-Host "    $($docLinks.GovCloudUrls)" -ForegroundColor Cyan
        }
    }

    Write-Host ""
    Write-Host "  Port Access Requirements:" -ForegroundColor White
    Write-Host "    $($docLinks.PortAccess)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Troubleshoot Appliance Issues:" -ForegroundColor White
    Write-Host "    $($docLinks.TroubleshootAppliance)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Appliance FAQ:" -ForegroundColor White
    Write-Host "    $($docLinks.CommonQuestions)" -ForegroundColor Cyan

    if ($PrivateLink) {
        Write-Host ""
        Write-Host "  Private Endpoints Setup:" -ForegroundColor White
        Write-Host "    $($docLinks.PrivateLinkSetup)" -ForegroundColor Cyan
    }

    if ($Scenario -eq 'AgentBasedLegacy' -or $Scenario -eq 'AgentBasedModern') {
        Write-Host ""
        Write-Host "  Agent-based Migration Architecture:" -ForegroundColor White
        Write-Host "    $($docLinks.AgentBasedMigration)" -ForegroundColor Cyan
    }

    if ($Scenario -eq 'AgentBasedModern') {
        Write-Host ""
        Write-Host "  Modern Appliance:" -ForegroundColor White
        Write-Host "    $($docLinks.ModernAppliance)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Simplified Experience:" -ForegroundColor White
        Write-Host "    $($docLinks.SimplifiedExperience)" -ForegroundColor Cyan
    }

    if ($PrivateLink) {
        Write-Host ""
        Write-Host "  Troubleshoot Network Connectivity (Private Endpoints):" -ForegroundColor White
        Write-Host "    $($docLinks.TroubleshootNetwork)" -ForegroundColor Cyan
    }
}

# ============================================================================
# REPORT EXPORT
# ============================================================================

function Export-Report {
    param(
        [string]$Cloud,
        [string]$Scenario,
        [string]$ApplianceType,
        [bool]$PrivateLink,
        [bool]$ProxyDetected
    )

    $sb = [System.Text.StringBuilder]::new()

    [void]$sb.AppendLine("=" * 80)
    [void]$sb.AppendLine("  Azure Migrate Appliance - Connectivity Troubleshooter Report")
    [void]$sb.AppendLine("  Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$sb.AppendLine("  Script Version: $($script:ScriptVersion)")
    [void]$sb.AppendLine("  Machine: $env:COMPUTERNAME")
    [void]$sb.AppendLine("=" * 80)
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("CONFIGURATION:")
    [void]$sb.AppendLine("  Cloud:              $Cloud")
    [void]$sb.AppendLine("  Scenario:           $Scenario")
    [void]$sb.AppendLine("  Appliance Type:     $ApplianceType")
    [void]$sb.AppendLine("  Private Link:       $PrivateLink")
    [void]$sb.AppendLine("  Proxy Detected:     $ProxyDetected")
    [void]$sb.AppendLine("  PowerShell Version: $($PSVersionTable.PSVersion)")
    [void]$sb.AppendLine("  TLS Protocols:      $([Net.ServicePointManager]::SecurityProtocol)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("-" * 80)
    [void]$sb.AppendLine("ENDPOINT TEST RESULTS:")
    [void]$sb.AppendLine("-" * 80)

    $failed = $script:TestResults | Where-Object { -not $_.OverallPass }
    $passed = $script:TestResults | Where-Object { $_.OverallPass }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Total: $($script:TestResults.Count)  |  Passed: $($passed.Count)  |  Failed: $($failed.Count)")
    [void]$sb.AppendLine("")

    foreach ($r in $script:TestResults) {
        $status = if ($r.OverallPass) { "PASS" } else { "FAIL" }
        [void]$sb.AppendLine("  [$status] $($r.Url):$($r.Port)")
        [void]$sb.AppendLine("         Purpose:  $($r.Purpose)")
        [void]$sb.AppendLine("         Wildcard: $($r.WildcardPattern)")
        [void]$sb.AppendLine("         Category: $($r.Category)")
        [void]$sb.AppendLine("         DNS:      $(if ($r.DnsPass) {'PASS'} else {'FAIL'}) - $($r.DnsDetail)")
        [void]$sb.AppendLine("         TCP:      $(if ($r.TcpPass) {'PASS'} else {'FAIL'}) - $($r.TcpDetail)")
        [void]$sb.AppendLine("         HTTPS:    $(if ($r.HttpsPass) {'PASS'} else {'FAIL'}) - $($r.HttpsDetail)")
        [void]$sb.AppendLine("")
    }

    if ($failed.Count -gt 0) {
        [void]$sb.AppendLine("-" * 80)
        [void]$sb.AppendLine("FAILED ENDPOINTS REQUIRING ACTION:")
        [void]$sb.AppendLine("-" * 80)
        foreach ($f in $failed) {
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("  FAILED: $($f.Url):$($f.Port) ($($f.Purpose))")
            [void]$sb.AppendLine("  Required firewall/proxy rule: Allow $($f.WildcardPattern) on port $($f.Port)")
            if (-not $f.DnsPass) {
                [void]$sb.AppendLine("  Root Cause: DNS resolution failed - $($f.DnsDetail)")
                [void]$sb.AppendLine("  Action: Check DNS configuration; ensure DNS can resolve Azure service domains")
            } elseif (-not $f.TcpPass) {
                [void]$sb.AppendLine("  Root Cause: TCP connection blocked (DNS resolved successfully)")
                [void]$sb.AppendLine("  Action: Firewall or proxy is blocking TCP/443 to this endpoint")
                [void]$sb.AppendLine("  Resolved IPs: $($f.DnsDetail)")
            } else {
                [void]$sb.AppendLine("  Root Cause: HTTPS/TLS failure (TCP connected successfully)")
                [void]$sb.AppendLine("  Action: Check for SSL inspection, proxy auth, or TLS version issues")
                [void]$sb.AppendLine("  HTTPS Error: $($f.HttpsDetail)")
            }
        }
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("-" * 80)
    [void]$sb.AppendLine("WARNINGS:")
    [void]$sb.AppendLine("-" * 80)
    foreach ($w in $script:Warnings) {
        [void]$sb.AppendLine("  [!] $w")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("-" * 80)
    [void]$sb.AppendLine("RECOMMENDATIONS:")
    [void]$sb.AppendLine("-" * 80)
    for ($i = 0; $i -lt $script:Recommendations.Count; $i++) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("  [$($i + 1)] $($script:Recommendations[$i])")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("-" * 80)
    [void]$sb.AppendLine("DOCUMENTATION LINKS:")
    [void]$sb.AppendLine("-" * 80)
    [void]$sb.AppendLine("  Appliance URLs:          https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance")
    [void]$sb.AppendLine("  Deployment Scenarios:    https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance#deployment-scenarios")
    [void]$sb.AppendLine("  Simplified Experience:   https://learn.microsoft.com/en-us/azure/migrate/simplified-experience-for-azure-migrate")
    [void]$sb.AppendLine("  Troubleshoot Appliance:  https://learn.microsoft.com/en-us/azure/migrate/troubleshoot-appliance")
    [void]$sb.AppendLine("  Port Access:             https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance#port-access")
    if ($Cloud -eq 'Commercial' -and -not $PrivateLink) {
        [void]$sb.AppendLine("  Required URLs:           https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance#public-cloud-urls")
    }
    if ($Cloud -eq 'Commercial' -and $PrivateLink) {
        [void]$sb.AppendLine("  Required URLs (PL):      https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance#public-cloud-urls-for-private-link-connectivity")
    }
    if ($Cloud -eq 'Government' -and -not $PrivateLink) {
        [void]$sb.AppendLine("  Required URLs (Gov):     https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance#government-cloud-urls")
    }
    if ($Cloud -eq 'Government' -and $PrivateLink) {
        [void]$sb.AppendLine("  Required URLs (Gov PL):  https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance#government-cloud-urls-for-private-link-connectivity")
    }
    [void]$sb.AppendLine("  Private Endpoints:       https://learn.microsoft.com/en-us/azure/migrate/how-to-use-azure-migrate-with-private-endpoints")
    [void]$sb.AppendLine("  Appliance FAQ:           https://learn.microsoft.com/en-us/azure/migrate/common-questions-appliance")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("=" * 80)
    [void]$sb.AppendLine("  END OF REPORT")
    [void]$sb.AppendLine("=" * 80)

    try {
        $sb.ToString() | Out-File -FilePath $script:ReportPath -Encoding UTF8 -Force
        Write-Host ""
        Write-Host "  Report saved to: $($script:ReportPath)" -ForegroundColor Green
    } catch {
        Write-Host "  Failed to save report: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Report content displayed above." -ForegroundColor Yellow
    }
}

function Export-JsonReport {
    param(
        [string]$Cloud,
        [string]$Scenario,
        [string]$ApplianceType,
        [bool]$PrivateLink,
        [bool]$ProxyDetected
    )

    $report = [ordered]@{
        GeneratedAt    = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        ScriptVersion  = $script:ScriptVersion
        Machine        = $env:COMPUTERNAME
        Configuration  = [ordered]@{
            Cloud          = $Cloud
            Scenario       = $Scenario
            ApplianceType  = $ApplianceType
            PrivateLink    = $PrivateLink
            ProxyDetected  = $ProxyDetected
        }
        Summary        = [ordered]@{
            TotalEndpoints = $script:TestResults.Count
            Passed         = @($script:TestResults | Where-Object { $_.OverallPass }).Count
            Failed         = @($script:TestResults | Where-Object { -not $_.OverallPass }).Count
        }
        Results        = @($script:TestResults | ForEach-Object {
            [ordered]@{
                Url         = $_.Url
                Port        = $_.Port
                Purpose     = $_.Purpose
                Category    = $_.Category
                Wildcard    = $_.WildcardPattern
                DnsPass     = $_.DnsPass
                DnsDetail   = $_.DnsDetail
                TcpPass     = $_.TcpPass
                TcpDetail   = $_.TcpDetail
                HttpsPass   = $_.HttpsPass
                HttpsDetail = $_.HttpsDetail
                OverallPass = $_.OverallPass
            }
        })
        Warnings        = @($script:Warnings)
        Recommendations = @($script:Recommendations)
    }

    try {
        $report | ConvertTo-Json -Depth 5 | Out-File -FilePath $script:JsonReportPath -Encoding UTF8 -Force
        Write-Host "  JSON report saved to: $($script:JsonReportPath)" -ForegroundColor Green
    } catch {
        Write-Host "  Failed to save JSON report: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ============================================================================
# PRIVATE LINK DNS VALIDATION
# ============================================================================

function Test-PrivateLinkDns {
    param(
        [System.Collections.ArrayList]$UrlList,
        [string]$Cloud
    )

    Write-Section "PRIVATE LINK DNS VALIDATION"
    Write-Host ""
    Write-Host "  Checking that Private Link endpoints resolve to private IP addresses..." -ForegroundColor White
    Write-Host "  (Private endpoints should resolve to 10.x.x.x, 172.16-31.x.x, or 192.168.x.x)" -ForegroundColor Gray
    Write-Host ""

    $privateLinkHosts = $UrlList | Where-Object {
        $_.Host -match 'privatelink' -or $_.Category -match 'Private Link|Custom'
    }

    $plIssues = 0
    foreach ($entry in $privateLinkHosts) {
        $dnsResult = Test-DnsResolution -HostName $entry.Host
        if ($dnsResult.Success) {
            $isPrivate = $false
            foreach ($addr in $dnsResult.Addresses) {
                if ($addr -match '^10\.' -or $addr -match '^172\.(1[6-9]|2[0-9]|3[01])\.' -or $addr -match '^192\.168\.') {
                    $isPrivate = $true
                }
            }
            if ($isPrivate) {
                Write-Host "    [PASS] $($entry.Host) -> $($dnsResult.Addresses -join ', ') (private IP)" -ForegroundColor Green
            } else {
                Write-Host "    [WARN] $($entry.Host) -> $($dnsResult.Addresses -join ', ') (PUBLIC IP - not private!)" -ForegroundColor Yellow
                $plIssues++
            }
        } else {
            Write-Host "    [FAIL] $($entry.Host) - DNS resolution failed: $($dnsResult.Error)" -ForegroundColor Red
            $plIssues++
        }
    }

    # Also check non-privatelink hosts that should resolve to private IPs when using private link
    $migrationHosts = $UrlList | Where-Object {
        $_.Host -notmatch 'privatelink' -and (
            $_.Host -match 'migration\.windowsazure' -or
            $_.Host -match 'discoverysrv\.windowsazure' -or
            $_.Host -match 'vault\.' -or
            $_.Host -match 'servicebus\.' -or
            $_.Host -match 'blob\.core'
        )
    }
    if ($migrationHosts.Count -gt 0) {
        Write-Host ""
        Write-Host "  Checking core service DNS for private IP resolution:" -ForegroundColor White
        foreach ($entry in $migrationHosts) {
            $dnsResult = Test-DnsResolution -HostName $entry.Host
            if ($dnsResult.Success) {
                $ipList = $dnsResult.Addresses -join ', '
                $hasPrivate = $dnsResult.Addresses | Where-Object {
                    $_ -match '^10\.' -or $_ -match '^172\.(1[6-9]|2[0-9]|3[01])\.' -or $_ -match '^192\.168\.'
                }
                if ($hasPrivate) {
                    Write-Host "    [OK]   $($entry.Host) -> $ipList (includes private IP)" -ForegroundColor Green
                } else {
                    Write-Host "    [INFO] $($entry.Host) -> $ipList (public IP - expected if CNAME chain uses privatelink)" -ForegroundColor Gray
                }
            }
        }
    }

    if ($plIssues -gt 0) {
        [void]$script:Recommendations.Add(@"
PRIVATE LINK DNS ISSUE: $plIssues endpoint(s) using Private Link did not resolve to private
IP addresses. This means the private DNS zone may not be configured correctly, or the DNS
query is not routing through your private DNS resolver.

For Azure Migrate Private Link, ensure:
  1. Private DNS zones are created and linked to your VNet:
     - privatelink.prod.migration.windowsazure.com (Commercial) or
       privatelink.prod.migration.windowsazure.us (Government)
     - privatelink.blob.core.windows.net (or .usgovcloudapi.net)
     - privatelink.vaultcore.azure.net (or .usgovcloudapi.net)
     - privatelink.servicebus.windows.net (or .usgovcloudapi.net)
  2. Private endpoint connections are approved in the Azure portal
  3. The appliance VM's DNS settings point to a DNS server that forwards to Azure DNS (168.63.129.16)
     or to a custom DNS server with conditional forwarders for the privatelink zones
  4. Auto-update manifest URLs (e.g., *-agent.uga.disc.privatelink.prod.migration.windowsazure.us)
     must resolve via the private DNS zone

See: https://learn.microsoft.com/en-us/azure/migrate/how-to-use-azure-migrate-with-private-endpoints
See: https://learn.microsoft.com/en-us/azure/migrate/troubleshoot-network-connectivity
"@)
    } else {
        Write-Host ""
        Write-Host "  [OK] Private Link DNS validation passed." -ForegroundColor Green
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function Main {
    Clear-Host
    Write-Banner

    # ----- Prerequisites -----
    if ($PSVersionTable.PSVersion.Major -lt 5 -or
        ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
        Write-Host "  [ERROR] PowerShell 5.1 or higher is required. Current: $($PSVersionTable.PSVersion)" -ForegroundColor Red
        Write-Host "  Please update PowerShell and re-run this script." -ForegroundColor Red
        return
    }

    # Determine if running non-interactively (all required params provided via command line)
    $isInteractive = -not ($script:BoundParams.ContainsKey('Cloud') -and
                           $script:BoundParams.ContainsKey('Scenario') -and
                           $script:BoundParams.ContainsKey('ApplianceType'))

    if ($isInteractive) {
        # ----- Interactive User Prompts -----
        Write-Section "DEPLOYMENT SCENARIO SELECTION"

        $cloudSel = Get-MenuSelection -Prompt "Which Azure cloud are you deploying to?" `
            -Options @("Commercial Azure (Public Cloud)", "Azure Government") `
            -HelpText "Select the Azure cloud environment for your deployment."
        $cloud = if ($cloudSel -eq 1) { 'Commercial' } else { 'Government' }

        $scenarioSel = Get-MenuSelection -Prompt "Which deployment scenario are you using?" `
            -Options @(
                "Azure Migrate VMware Agentless (discovery, assessment, and agentless migration)",
                "Azure Migrate Agent-based Legacy Appliance (replication appliance)",
                "Azure Migrate Agent-based Modern Appliance (simplified experience)"
            ) `
            -HelpText "See: https://learn.microsoft.com/en-us/azure/migrate/migrate-appliance#deployment-scenarios"
        $scenario = switch ($scenarioSel) {
            1 { 'VMwareAgentless' }
            2 { 'AgentBasedLegacy' }
            3 { 'AgentBasedModern' }
        }

        $applianceTypeSel = Get-MenuSelection -Prompt "What type of appliance are you troubleshooting?" `
            -Options @(
                "Assessment / Discovery appliance",
                "Replication appliance (migration)"
            ) `
            -HelpText "Assessment appliance is for discovery and assessment. Replication appliance is for migration."
        $applianceType = if ($applianceTypeSel -eq 1) { 'Assessment' } else { 'Replication' }

        $privateLinkSel = Get-MenuSelection -Prompt "Are you using Azure Private Link / Private Endpoints?" `
            -Options @("No (public connectivity)", "Yes (private endpoints)") `
            -HelpText "See: https://learn.microsoft.com/en-us/azure/migrate/how-to-use-azure-migrate-with-private-endpoints"
        $privateLink = $privateLinkSel -eq 2
    } else {
        # Non-interactive mode: use command-line parameters
        $cloud         = $script:BoundParams['Cloud']
        $scenario      = $script:BoundParams['Scenario']
        $applianceType = $script:BoundParams['ApplianceType']
        $privateLink   = [bool]$script:BoundParams['PrivateLink']
        Write-Host "  Running in non-interactive mode with provided parameters." -ForegroundColor Cyan
    }

    # ----- Custom URLs (error messages, auto-update endpoints, etc.) -----
    $customUrls = [System.Collections.ArrayList]::new()
    if ($isInteractive) {
        Write-Host ""
        Write-Host "  Do you have any specific URLs from error messages that you want to test?" -ForegroundColor White
        Write-Host "  (e.g., auto-update manifest URLs, service endpoints from appliance errors)" -ForegroundColor Gray
        Write-Host "  Paste full URL(s) one per line. Press Enter on a blank line when done." -ForegroundColor Gray
        Write-Host "  (If none, just press Enter to continue)" -ForegroundColor Gray
        Write-Host ""
        do {
            $customInput = Read-Host "  URL"
            if ($customInput -and $customInput.Trim()) {
                $trimmed = $customInput.Trim()
                # Strip protocol prefix and trailing slashes to extract hostname
                $hostPart = $trimmed -replace '^https?://' , '' -replace '/.*$', ''
                if ($hostPart) {
                    [void]$customUrls.Add(@{
                        Host     = $hostPart
                        Port     = 443
                        Purpose  = "Custom URL from error/appliance (source: $trimmed)"
                        Wildcard = "*.$($hostPart -replace '^[^.]+\.', '')"
                        Category = 'Custom URLs (from error messages)'
                    })
                    Write-Host "    Added: $hostPart" -ForegroundColor Green
                }
            }
        } while ($customInput -and $customInput.Trim())
    }

    # ----- Summary -----
    Write-Section "SELECTED CONFIGURATION"
    Write-Host "    Cloud:          $cloud" -ForegroundColor White
    Write-Host "    Scenario:       $scenario" -ForegroundColor White
    Write-Host "    Appliance Type: $applianceType" -ForegroundColor White
    Write-Host "    Private Link:   $privateLink" -ForegroundColor White
    Write-Host "    Output Format:  $($script:OutputFormat)" -ForegroundColor White
    Write-Host ""
    if ($isInteractive) {
        Write-Host "  Press Enter to begin connectivity checks or Ctrl+C to cancel..." -ForegroundColor Gray
        Read-Host
    }

    # ----- Environment Info -----
    Get-EnvironmentInfo

    # ----- Proxy Detection -----
    $proxyDetected = Get-ProxyConfiguration

    # ----- Local Firewall -----
    Test-LocalFirewall

    # ----- Basic Connectivity -----
    Test-BasicConnectivity

    # ----- Build URL List -----
    $urlList = Get-UrlDefinitions -Cloud $cloud -Scenario $scenario -ApplianceType $applianceType -PrivateLink $privateLink

    if ($urlList.Count -eq 0) {
        Write-Host ""
        Write-Host "  [WARN] No URLs generated for the selected configuration. Please verify your selections." -ForegroundColor Yellow
        return
    }

    # ----- Append custom URLs -----
    if ($customUrls.Count -gt 0) {
        foreach ($cu in $customUrls) {
            [void]$urlList.Add($cu)
        }
        Write-Host ""
        Write-Host "  Added $($customUrls.Count) custom URL(s) to the test list." -ForegroundColor Cyan
    }

    # ----- Run Connectivity Tests -----
    Invoke-ConnectivityTests -UrlList $urlList

    # ----- Private Link DNS Validation -----
    if ($privateLink) {
        Test-PrivateLinkDns -UrlList $urlList -Cloud $cloud
    }

    # ----- Results Summary -----
    Write-ResultsSummary -Cloud $cloud -Scenario $scenario -ApplianceType $applianceType -PrivateLink $privateLink

    # ----- Recommendations -----
    Write-Recommendations -Cloud $cloud -Scenario $scenario -ApplianceType $applianceType -PrivateLink $privateLink

    # ----- Export Reports -----
    Export-Report -Cloud $cloud -Scenario $scenario -ApplianceType $applianceType `
        -PrivateLink $privateLink -ProxyDetected $proxyDetected

    if ($script:OutputFormat -eq 'JSON') {
        Export-JsonReport -Cloud $cloud -Scenario $scenario -ApplianceType $applianceType `
            -PrivateLink $privateLink -ProxyDetected $proxyDetected
    }

    # ----- Final Banner -----
    Write-Host ""
    Write-Host "===============================================================================" -ForegroundColor Cyan
    Write-Host "  Troubleshooting complete. Review results above and in the saved report." -ForegroundColor Cyan
    Write-Host "  If issues persist, share the report with Microsoft Support." -ForegroundColor Cyan
    Write-Host "  Report: $($script:ReportPath)" -ForegroundColor Cyan
    if ($script:OutputFormat -eq 'JSON') {
        Write-Host "  JSON:   $($script:JsonReportPath)" -ForegroundColor Cyan
    }
    Write-Host "===============================================================================" -ForegroundColor Cyan
    Write-Host ""
}

# Run the script
Main
