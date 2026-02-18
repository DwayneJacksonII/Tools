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


<#
.SYNOPSIS
    SCCM Client Installation for Azure VMs (Azure Blob Method). 
    This method assumes Install-SCCMClient.ps1 already uploaded to Azure Blob Storage with a valid SAS token for access. 
.DESCRIPTION
    Downloads SCCM client from Azure Blob Storage and installs.
    Client will install but NOT register with management point (Lab no connectivity to SCCM Sever testing deployment script logic only).
#>

#region Configuration - MODIFY THESE
$SiteCode = "PS1" # Your SCCM SITE CODE HERE (e.g., "PS1", "LAB")
# Below BlobURL will use your_BLOB_URL_HERE with a SAS token that has read permissions and is valid
$BlobURL = "Your_BLOB_URL_HERE"  
$LocalPath = "C:\Temp\SCCMClient"   # UNC path to SCCCM Client source files
$LogPath = "C:\Windows\Temp\SCCMInstall.log" # Installation log location on the Azure Windows VM
#endregion

#region Functions
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $LogMessage -Force
    
    $Color = switch($Level) {
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host $LogMessage -ForegroundColor $Color
}

function Test-SCCMClient {
    try {
        $Client = Get-WmiObject -Namespace "root\ccm" -Class "SMS_Client" -ErrorAction SilentlyContinue
        return ($null -ne $Client)
    } catch {
        return $false
    }
}
#endregion

#region Main Process
try {
    Write-Log "============================================" "INFO"
    Write-Log "SCCM Client Installation Started" "INFO"
    Write-Log "Hostname: $(hostname)" "INFO"
    Write-Log "IP Address: $((Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.PrefixOrigin -eq 'Dhcp'} | Select-Object -First 1).IPAddress)" "INFO"
    Write-Log "============================================" "INFO"
    
    # Check if already installed
    if (Test-SCCMClient) {
        Write-Log "SCCM client already installed" "WARN"
        $Version = (Get-WmiObject -Namespace "root\ccm" -Class "SMS_Client").ClientVersion
        Write-Log "Installed version: $Version" "INFO"
        Write-Log "Exiting..." "INFO"
        exit 0
    }
    
    # Create staging directory
    Write-Log "Creating staging directory: $LocalPath" "INFO"
    New-Item -Path $LocalPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    
    # Download client
    Write-Log "Downloading SCCM client from Azure Blob..." "INFO"
    Write-Log "URL: $BlobURL" "INFO"
    
    $ZipFile = "$LocalPath\client.zip"
    
    try {
        $ProgressPreference = 'SilentlyContinue'  # Faster download
        Invoke-WebRequest -Uri $BlobURL -OutFile $ZipFile -UseBasicParsing
        $ProgressPreference = 'Continue'
        
        $SizeMB = [Math]::Round((Get-Item $ZipFile).Length / 1MB, 2)
        Write-Log "Download complete: $SizeMB MB" "SUCCESS"
    } catch {
        Write-Log "Download failed: $($_.Exception.Message)" "ERROR"
        throw "Cannot download SCCM client from Azure Blob"
    }
    
    # Extract files
    Write-Log "Extracting client files..." "INFO"
    Expand-Archive -Path $ZipFile -DestinationPath $LocalPath -Force
    Remove-Item $ZipFile -Force
    Write-Log "Extraction complete" "SUCCESS"
    
    # Verify ccmsetup.exe
    $Installer = "$LocalPath\ccmsetup.exe"
    if (-not (Test-Path $Installer)) {
        Write-Log "CCMSetup.exe not found at: $Installer" "ERROR"
        throw "Installation files incomplete"
    }
    
    # Install client
    $Args = "SMSSITECODE=$SiteCode"
    
    Write-Log "Starting SCCM client installation..." "INFO"
    Write-Log "Command: $Installer $Args" "INFO"
    
    $Process = Start-Process -FilePath $Installer -ArgumentList $Args -Wait -PassThru -NoNewWindow
    
    Write-Log "Installation process completed" "INFO"
    Write-Log "Exit code: $($Process.ExitCode)" "INFO"
    
    # Wait for service
    if ($Process.ExitCode -eq 0 -or $Process.ExitCode -eq 7) {
        Write-Log "Waiting for SCCM client service to start..." "INFO"
        
        $Timeout = 180  # 3 minutes
        $Timer = 0
        $Interval = 10
        
        while (-not (Test-SCCMClient) -and $Timer -lt $Timeout) {
            Start-Sleep -Seconds $Interval
            $Timer += $Interval
            Write-Log "Waiting... ($Timer seconds elapsed)" "INFO"
        }
        
        if (Test-SCCMClient) {
            $Version = (Get-WmiObject -Namespace "root\ccm" -Class "SMS_Client").ClientVersion
            Write-Log "============================================" "SUCCESS"
            Write-Log "SCCM CLIENT INSTALLED SUCCESSFULLY!" "SUCCESS"
            Write-Log "Client Version: $Version" "SUCCESS"
            Write-Log "============================================" "SUCCESS"
            Write-Log "" "INFO"
            Write-Log "NOTE: Client will NOT register with management point" "WARN"
            Write-Log "This is expected without VPN/CMG connectivity" "WARN"
            Write-Log "" "INFO"
            Write-Log "Installation log: C:\Windows\ccmsetup\Logs\ccmsetup.log" "INFO"
            exit 0
        } else {
            Write-Log "Client service did not start within $Timeout seconds" "WARN"
            Write-Log "Check logs at: C:\Windows\ccmsetup\Logs\ccmsetup.log" "WARN"
            exit 1
        }
    } else {
        throw "Installation failed with exit code: $($Process.ExitCode)"
    }
    
} catch {
    Write-Log "============================================" "ERROR"
    Write-Log "INSTALLATION FAILED" "ERROR"
    Write-Log "Error: $($_.Exception.Message)" "ERROR"
    Write-Log "============================================" "ERROR"
    exit 1
}

#endregion




