<#------------------------------------------------------------------------------

 Copyright © 2026 Microsoft Corporation.  All rights reserved.

 THIS CODE AND ANY ASSOCIATED INFORMATION ARE PROVIDED "AS IS" WITHOUT
 WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT
 LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS
 FOR A PARTICULAR PURPOSE. THE ENTIRE RISK OF USE, INABILITY TO USE, OR
 RESULTS FROM THE USE OF THIS CODE REMAINS WITH THE USER.
 Label: Sample only — not production ready

#------------------------------------------------------------------------------
#>

# ============================================================
# SCCM CLIENT INSTALLATION - AZURE RUN COMMAND 
# Supports: Azure Blob URL | UNC File Share | Local Path
# 
# ============================================================
#
# SOURCE TYPE OPTIONS:
#   "AzureBlob"  - Download ZIP from Azure Blob Storage URL
#   "UNCPath"    - Copy from a network file share (\\server\share\path)
#   "LocalPath"  - Use files already on the local disk (C:\path\to\files)
#
# ============================================================
#  EDIT THE VARIABLES BELOW BEFORE RUNNING
# ============================================================

# -- SOURCE TYPE: Choose one of "AzureBlob", "UNCPath", "LocalPath"
$Config_SourceType = "AzureBlob"

# -- AZURE BLOB (used when SourceType = "AzureBlob")
#    Full direct-file SAS URL to the ZIP (sr=b, not sr=c)
$Config_AzureBlobURL = "https://sccmlab2024.blob.core.windows.net/sccm/SCCMClient.zip?sp=r&st=2026-02-26T17:38:20Z&se=2026-02-27T01:53:20Z&spr=https&sv=2024-11-04&sr=b&sig=SlhzfPzoHdSKEwKKaTcQw%2FVbGyIhmv9c5hN3N9yPqCA%3D"

# -- UNC FILE SHARE (used when SourceType = "UNCPath")
#    Path to folder containing ccmsetup.exe  e.g. \\fileserver\sccm\client
$Config_UNCPath          = ""       # e.g. \\NC-SCCM\SMSSMS\Client
$Config_UNCUsername      = ""       # e.g. CONTOSO\svcSCCM   (leave blank if no creds needed)
$Config_UNCPassword      = ""       # plain text (or use a keyvault reference in pipeline)

# -- LOCAL PATH (used when SourceType = "LocalPath")
#    Folder already on the VM that contains ccmsetup.exe
$Config_LocalPath = ""              # e.g. C:\SCCMClient  or  D:\Tools\SCCM

# ============================================================
# SCCM SITE & MANAGEMENT POINT
# ============================================================
$Config_SiteCode        = "L24"
$Config_ManagementPoint = "NC-SCCM.NC9245.lab"   # leave blank to install without MP
$Config_RegisterClient  = $true

# ============================================================
# PKI CERTIFICATE (optional)
# ============================================================
$Config_UsePKI       = $false
$Config_CertTemplate = ""           # e.g. "SCCM Client"  -- leave blank if not using PKI

# ============================================================
# DO NOT EDIT BELOW THIS LINE
# ============================================================

$ErrorActionPreference = "SilentlyContinue"
$Timestamp       = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile         = "C:\Windows\Temp\SCCMInstall_$Timestamp.log"
$WorkDir         = "C:\Windows\Temp\SCCMWork_$Timestamp"
$ResultStatus    = "SUCCESS"
$Warnings        = @()
$ClientInstalled = $false
$ClientVersion   = "Not Installed"
$MPStatus        = "NOT CONFIGURED"
$RegStatus       = "SKIPPED"
$CommMode        = "HTTP"
$CCMExe          = "$env:SystemRoot\CCM\CcmExec.exe"

# ── Logging helpers ───────────────────────────────────────────
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $Line -Force
    Write-Output $Line
}
function Write-Sep { Write-Log ("=" * 60) }

# ── Bootstrap work directory ──────────────────────────────────
if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
}

Write-Sep
Write-Log "SCCM Client Installation Starting"
Write-Log "Source Type : $Config_SourceType"
Write-Log "Log File    : $LogFile"
Write-Sep

# ════════════════════════════════════════════════════════════
# STEP 1 – Check existing installation
# ════════════════════════════════════════════════════════════
Write-Log "STEP 1: Checking existing SCCM client installation"

$CCMSetupKey = "HKLM:\SOFTWARE\Microsoft\SMS\Client\Configuration\Client Properties"
$ExistingVer = ""

if (Test-Path $CCMSetupKey) {
    $ExistingVer = (Get-ItemProperty -Path $CCMSetupKey -ErrorAction SilentlyContinue)."Client Version"
}
if ((-not $ExistingVer) -and (Test-Path $CCMExe)) {
    $ExistingVer = (Get-Item $CCMExe -ErrorAction SilentlyContinue).VersionInfo.FileVersion
}

if ($ExistingVer) {
    Write-Log "Already installed: v$ExistingVer - Reinstall will be attempted" "WARN"
    $ClientInstalled = $true
    $ClientVersion   = $ExistingVer
    $Warnings += "SCCM client already present (v$ExistingVer). Proceeding with reinstall."
} else {
    Write-Log "No existing SCCM client found - fresh install" "INFO"
}

# ════════════════════════════════════════════════════════════
# STEP 2 – Obtain client files
# ════════════════════════════════════════════════════════════
Write-Log "STEP 2: Obtaining SCCM client files  [SourceType = $Config_SourceType]"

$CCMSetupExe = ""

# ── 2A: Azure Blob ────────────────────────────────────────────
if ($Config_SourceType -eq "AzureBlob") {

    if ([string]::IsNullOrWhiteSpace($Config_AzureBlobURL)) {
        Write-Log "AzureBlobURL is empty - cannot continue" "ERROR"
        $ResultStatus = "FAILED"
        $Warnings += "Config_AzureBlobURL must be set when SourceType is AzureBlob."
    } else {
        $Preview = $Config_AzureBlobURL.Substring(0, [Math]::Min(90, $Config_AzureBlobURL.Length))
        Write-Log "Downloading: $Preview..." "INFO"

        $ZipDest = "$WorkDir\SCCMClient.zip"

        # Load compression assembly
        Add-Type -AssemblyName "System.IO.Compression.FileSystem" -ErrorAction SilentlyContinue

        # .NET WebClient is more reliable than Invoke-WebRequest inside Run Command
        $WC = New-Object System.Net.WebClient
        $WC.DownloadFile($Config_AzureBlobURL, $ZipDest)
        $DownloadOK = $?

        if ($DownloadOK -and (Test-Path $ZipDest) -and (Get-Item $ZipDest).Length -gt 0) {
            $SizeMB = "{0:N2}" -f ((Get-Item $ZipDest).Length / 1MB)
            Write-Log "Download succeeded ($SizeMB MB)" "INFO"

            $ExtractDir = "$WorkDir\Extracted"
            New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null
            [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipDest, $ExtractDir)
            $ExtractOK = $?

            if ($ExtractOK) {
                $Found = Get-ChildItem -Path $ExtractDir -Recurse -Filter "ccmsetup.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($Found) {
                    $CCMSetupExe = $Found.FullName
                    Write-Log "ccmsetup.exe found: $CCMSetupExe" "INFO"
                } else {
                    Write-Log "ccmsetup.exe NOT found inside ZIP" "ERROR"
                    $ResultStatus = "FAILED"
                    $Warnings += "ccmsetup.exe not found in downloaded ZIP. Check ZIP contents."
                }
            } else {
                Write-Log "ZIP extraction failed" "ERROR"
                $ResultStatus = "FAILED"
                $Warnings += "Failed to extract SCCMClient.zip."
            }
        } else {
            Write-Log "Download failed or file is empty" "ERROR"
            $ResultStatus = "FAILED"
            $Warnings += "Azure Blob download failed. Verify URL and SAS token expiry."
        }
    }

# ── 2B: UNC File Share ────────────────────────────────────────
} elseif ($Config_SourceType -eq "UNCPath") {

    if ([string]::IsNullOrWhiteSpace($Config_UNCPath)) {
        Write-Log "UNCPath is empty - cannot continue" "ERROR"
        $ResultStatus = "FAILED"
        $Warnings += "Config_UNCPath must be set when SourceType is UNCPath."
    } else {
        Write-Log "UNC path: $Config_UNCPath" "INFO"

        # Map drive if credentials provided
        $DriveLabel = "SCCMShare"
        $DriveMapped = $false

        if (-not [string]::IsNullOrWhiteSpace($Config_UNCUsername) -and
            -not [string]::IsNullOrWhiteSpace($Config_UNCPassword)) {

            Write-Log "Mapping $Config_UNCPath as $DriveLabel`: with credentials" "INFO"
            $SecPwd = ConvertTo-SecureString $Config_UNCPassword -AsPlainText -Force
            $Cred   = New-Object System.Management.Automation.PSCredential($Config_UNCUsername, $SecPwd)

            New-PSDrive -Name $DriveLabel -PSProvider FileSystem -Root $Config_UNCPath -Credential $Cred -ErrorAction SilentlyContinue | Out-Null
            $DriveMapped = $?

            if ($DriveMapped) {
                Write-Log "Drive mapped successfully as ${DriveLabel}:" "INFO"
                $SearchRoot = "${DriveLabel}:"
            } else {
                Write-Log "Drive mapping failed - trying direct UNC access" "WARN"
                $Warnings += "PSDrive mapping failed; attempting direct UNC path access."
                $SearchRoot = $Config_UNCPath
            }
        } else {
            Write-Log "No credentials provided - using direct UNC access (VM account must have share read rights)" "INFO"
            $SearchRoot = $Config_UNCPath
        }

        # Test share reachability
        if (Test-Path $SearchRoot) {
            Write-Log "Share is reachable: $SearchRoot" "INFO"

            $Found = Get-ChildItem -Path $SearchRoot -Recurse -Filter "ccmsetup.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($Found) {
                # Copy exe locally to avoid network interruption during install
                $LocalCopy = "$WorkDir\ccmsetup.exe"
                Copy-Item -Path $Found.FullName -Destination $LocalCopy -Force
                $CopyOK = $?

                if ($CopyOK -and (Test-Path $LocalCopy)) {
                    $CCMSetupExe = $LocalCopy
                    Write-Log "ccmsetup.exe copied locally: $CCMSetupExe" "INFO"

                    # Also copy any .cab/.msi files alongside ccmsetup
                    $SetupDir = Split-Path $Found.FullName -Parent
                    Get-ChildItem -Path $SetupDir -Filter "*.cab" -ErrorAction SilentlyContinue |
                        ForEach-Object { Copy-Item $_.FullName $WorkDir -Force -ErrorAction SilentlyContinue }
                    Get-ChildItem -Path $SetupDir -Filter "*.msi" -ErrorAction SilentlyContinue |
                        ForEach-Object { Copy-Item $_.FullName $WorkDir -Force -ErrorAction SilentlyContinue }
                } else {
                    Write-Log "Failed to copy ccmsetup.exe locally - using UNC path directly" "WARN"
                    $CCMSetupExe = $Found.FullName
                    $Warnings += "Could not copy ccmsetup.exe locally; running from UNC path."
                }
            } else {
                Write-Log "ccmsetup.exe NOT found at $SearchRoot" "ERROR"
                $ResultStatus = "FAILED"
                $Warnings += "ccmsetup.exe not found on share $Config_UNCPath."
            }
        } else {
            Write-Log "Share not reachable: $SearchRoot" "ERROR"
            $ResultStatus = "FAILED"
            $Warnings += "UNC path not accessible: $Config_UNCPath. Check network, firewall, and permissions."
        }
    }

# ── 2C: Local Path ────────────────────────────────────────────
} elseif ($Config_SourceType -eq "LocalPath") {

    if ([string]::IsNullOrWhiteSpace($Config_LocalPath)) {
        Write-Log "LocalPath is empty - defaulting to C:\SCCMClient" "WARN"
        $Config_LocalPath = "C:\SCCMClient"
        $Warnings += "Config_LocalPath was empty; tried default C:\SCCMClient."
    }

    Write-Log "Local path: $Config_LocalPath" "INFO"

    if (Test-Path $Config_LocalPath) {
        $Found = Get-ChildItem -Path $Config_LocalPath -Recurse -Filter "ccmsetup.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($Found) {
            $CCMSetupExe = $Found.FullName
            Write-Log "ccmsetup.exe found: $CCMSetupExe" "INFO"
        } else {
            Write-Log "ccmsetup.exe NOT found under $Config_LocalPath" "ERROR"
            $ResultStatus = "FAILED"
            $Warnings += "ccmsetup.exe not found at local path $Config_LocalPath."
        }
    } else {
        Write-Log "Path does not exist: $Config_LocalPath" "ERROR"
        $ResultStatus = "FAILED"
        $Warnings += "Local path does not exist: $Config_LocalPath"
    }

} else {
    Write-Log "Unknown SourceType '$Config_SourceType'" "ERROR"
    $ResultStatus = "FAILED"
    $Warnings += "Invalid Config_SourceType. Must be AzureBlob, UNCPath, or LocalPath."
}

# ════════════════════════════════════════════════════════════
# STEP 3 – PKI Certificate (optional)
# ════════════════════════════════════════════════════════════
Write-Log "STEP 3: PKI Certificate configuration"

if ($Config_UsePKI -eq $true) {
    Write-Log "PKI enabled - checking certificate store" "INFO"
    $CommMode = "HTTPS"

    # first check if Software Center has a certificate registered (client registry)
    $Cert = $null
    $SCCMRegPath = "HKLM:\SOFTWARE\Microsoft\CCM\Certificates"
    if (Test-Path $SCCMRegPath) {
        Write-Log "Looking for cert entries under $SCCMRegPath" "INFO"
        Get-ChildItem -Path $SCCMRegPath -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            if ($props -and $props.Thumbprint) {
                $thumb = $props.Thumbprint.Replace(' ','')
                $candidate = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
                    Where-Object { $_.Thumbprint -eq $thumb }
                if ($candidate) {
                    $Cert = $candidate
                    Write-Log "Software Center certificate found: $thumb" "INFO"
                    return
                }
            }
        }
    }

    # if no registry cert, fall back to template search
    if (-not $Cert) {
        $Template = if ([string]::IsNullOrWhiteSpace($Config_CertTemplate)) { "SCCM Client" } else { $Config_CertTemplate }
        Write-Log "Looking for certificate template: $Template" "INFO"

        $Cert = Get-ChildItem "Cert:\LocalMachine\My" -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.Extensions | Where-Object {
                    $_.Oid.FriendlyName -eq "Certificate Template Information" -and
                    $_.Format(0) -match $Template
                })
            } |
            Where-Object { $_.NotAfter -gt (Get-Date) } |
            Sort-Object NotAfter -Descending |
            Select-Object -First 1

        if ($Cert) {
            Write-Log "PKI cert found: Thumbprint=$($Cert.Thumbprint)  Expires=$($Cert.NotAfter)" "INFO"
        }
    }

    if (-not $Cert) {
        Write-Log "No valid PKI certificate found - falling back to HTTP" "WARN"
        $CommMode      = "HTTP"
        $Config_UsePKI = $false
        $Warnings     += "PKI cert not found; falling back to HTTP."
    }

    # Registry check for existing CCM certificate template (informational)
    $RegCCM = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\CCM" -ErrorAction SilentlyContinue)."CertificateTemplate"
    if ($RegCCM) { Write-Log "Registry CCM CertificateTemplate: $RegCCM" "INFO" }

} else {
    Write-Log "PKI not configured - using HTTP" "INFO"
}

# ════════════════════════════════════════════════════════════
# STEP 4 – Install SCCM client
# ════════════════════════════════════════════════════════════
Write-Log "STEP 4: Running ccmsetup installation"

if ($ResultStatus -ne "FAILED") {

    # Build argument string
    if ([string]::IsNullOrWhiteSpace($Config_ManagementPoint)) {
        $InstallArgs = "SMSSITECODE=$Config_SiteCode /logon /noservice"
        $MPStatus    = "NOT PROVIDED"
        $Warnings   += "No Management Point set; client will not register with an MP."
    } else {
        $InstallArgs = "/mp:$Config_ManagementPoint SMSSITECODE=$Config_SiteCode /logon /noservice"
        $MPStatus    = $Config_ManagementPoint
    }

    if ([string]::IsNullOrWhiteSpace($Config_SiteCode)) {
        Write-Log "SiteCode is empty - installing without site assignment" "WARN"
        $InstallArgs = $InstallArgs -replace "SMSSITECODE=\s*\b", ""
        $Warnings   += "No SiteCode provided; client will install without site assignment."
    }

    if ($Config_UsePKI -eq $true) {
        $InstallArgs += " /UsePKICert CCMHTTPSSTATE=31"
    }

    Write-Log "Executable  : $CCMSetupExe" "INFO"
    Write-Log "Arguments   : $InstallArgs" "INFO"

    $Proc     = Start-Process -FilePath $CCMSetupExe -ArgumentList $InstallArgs -Wait -PassThru -WindowStyle Hidden
    $ExitCode = $Proc.ExitCode
    Write-Log "ccmsetup.exe exit code: $ExitCode" "INFO"

    # 0 = success  |  6 = already installed  |  7 = reboot required
    if ($ExitCode -eq 0 -or $ExitCode -eq 6 -or $ExitCode -eq 7) {
        Write-Log "Installation completed (exit $ExitCode)" "INFO"
        $ClientInstalled = $true
        if ($ExitCode -eq 7) { $Warnings += "Reboot may be required to finalise the SCCM client installation." }
    } else {
        Write-Log "ccmsetup returned exit code $ExitCode" "WARN"
        $Warnings += "ccmsetup.exe exit $ExitCode - check C:\Windows\ccmsetup\Logs\ccmsetup.log"
    }

    # Wait for services to initialise
    Write-Log "Waiting 30 seconds for client services to initialise..." "INFO"
    Start-Sleep -Seconds 30

    # Read installed version
    $NewVer = ""
    if (Test-Path $CCMSetupKey) {
        $NewVer = (Get-ItemProperty -Path $CCMSetupKey -ErrorAction SilentlyContinue)."Client Version"
    }
    if ((-not $NewVer) -and (Test-Path $CCMExe)) {
        $NewVer = (Get-Item $CCMExe -ErrorAction SilentlyContinue).VersionInfo.FileVersion
    }

    if ($NewVer) {
        $ClientVersion = $NewVer
        Write-Log "Installed client version: $ClientVersion" "INFO"
    } else {
        $Warnings += "Client version not yet readable - may still be initialising."
    }
}

# ════════════════════════════════════════════════════════════
# STEP 5 – Registration check
# ════════════════════════════════════════════════════════════
Write-Log "STEP 5: Client registration check"

if ($Config_RegisterClient -eq $true -and -not [string]::IsNullOrWhiteSpace($Config_ManagementPoint)) {

    Write-Log "Checking registration with MP: $Config_ManagementPoint" "INFO"

    # DNS check
    $DNS = [System.Net.Dns]::GetHostAddresses($Config_ManagementPoint)
    if ($DNS -and $DNS.Count -gt 0) {
        Write-Log "DNS OK: $Config_ManagementPoint -> $($DNS[0].IPAddressToString)" "INFO"
    } else {
        Write-Log "DNS resolution failed for $Config_ManagementPoint" "WARN"
        $Warnings += "Cannot resolve MP FQDN '$Config_ManagementPoint' via DNS."
    }

    # CcmExec service
    $SvcStatus = (Get-Service -Name "CcmExec" -ErrorAction SilentlyContinue).Status
    if ($SvcStatus -eq "Running") {
        Write-Log "CcmExec service: Running" "INFO"
        $RegStatus = "REGISTERED (Service Running)"
    } elseif ($SvcStatus) {
        Write-Log "CcmExec service: $SvcStatus" "WARN"
        $RegStatus = "PENDING ($SvcStatus)"
        $Warnings += "CcmExec not yet Running (status: $SvcStatus)."
    } else {
        Write-Log "CcmExec service not found" "WARN"
        $RegStatus = "SERVICE NOT FOUND"
        $Warnings += "CcmExec service missing - client may not have installed."
    }

} elseif ($Config_RegisterClient -eq $true) {
    Write-Log "Registration requested but no MP configured - skipping" "WARN"
    $RegStatus = "SKIPPED - No MP Provided"
    $Warnings += "Client registration skipped: Config_ManagementPoint is empty."
} else {
    Write-Log "Registration not requested" "INFO"
    $RegStatus = "NOT REQUESTED"
}

# ════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ════════════════════════════════════════════════════════════
Write-Sep
Write-Log "INSTALLATION SUMMARY"
Write-Sep
Write-Log ("Overall Status        : " + $ResultStatus)
Write-Log ("Client Installed      : " + $ClientInstalled)
Write-Log ("Client Version        : " + $ClientVersion)
Write-Log ("Site Code             : " + $(if ([string]::IsNullOrWhiteSpace($Config_SiteCode)) { "NOT SET" } else { $Config_SiteCode }))
Write-Log ("Communication Mode    : " + $CommMode)
Write-Log ("Source Type           : " + $Config_SourceType)
Write-Log ("Management Point      : " + $(if ([string]::IsNullOrWhiteSpace($Config_ManagementPoint)) { "NOT CONFIGURED - Client will not register with MP" } else { $MPStatus }))
Write-Log ("Registration Status   : " + $RegStatus)

if ($Warnings.Count -gt 0) {
    Write-Sep
    Write-Log "WARNINGS ($($Warnings.Count)):"
    foreach ($W in $Warnings) { Write-Log "  >> $W" "WARN" }
}

Write-Sep
Write-Log "Log File : $LogFile"
Write-Sep
Write-Log "Script completed."

# Clean up work dir
Remove-Item -Path $WorkDir -Recurse -Force -ErrorAction SilentlyContinue

# Disconnect any mapped drive
if (Get-PSDrive -Name "SCCMShare" -ErrorAction SilentlyContinue) {
    Remove-PSDrive -Name "SCCMShare" -Force -ErrorAction SilentlyContinue
}

if ($ResultStatus -eq "FAILED") { exit 1 } else { exit 0 }
