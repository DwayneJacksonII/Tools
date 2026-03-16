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
param(
    [Parameter(Mandatory = $false)]
    [switch]
    $SkipSettingTrustedHost
)

## This routine writes the output string to the console and also to a log file.
function Log-Info([string] $OutputText)
{
    Write-Host $OutputText -ForegroundColor White
    $OutputText = [string][DateTime]::Now + " " + $OutputText
    $OutputText | %{ Out-File -filepath $InstallerLog -inputobject $_ -append -encoding "ASCII" }
}

function Log-Success([string] $OutputText)
{
    Write-Host $OutputText -ForegroundColor Green
    $OutputText = [string][DateTime]::Now + " " + $OutputText
    $OutputText | %{ Out-File -filepath $InstallerLog -inputobject $_ -append -encoding "ASCII" }
}

## This routine writes the output string to the console and also to a log file.
function Log-Warning([string] $OutputText)
{
    Write-Host $OutputText -ForegroundColor Yellow
    $OutputText = [string][DateTime]::Now + " " + $OutputText
    $OutputText | %{ Out-File -filepath $InstallerLog -inputobject $_ -append -encoding "ASCII"  }
}

## This routine writes the output string to the console and also to a log file.
function Log-Error([string] $OutputText)
{
    Write-Host $OutputText -ForegroundColor Red
    $OutputText = [string][DateTime]::Now + " " + $OutputText
    $OutputText | %{ Out-File -filepath $InstallerLog -inputobject $_ -append -encoding "ASCII" }
}

## Global Initialization
$global:DefaultStringVal  = "$Env:SystemDrive\\"
$global:WarningCount      = 0
$Fabric                   = "VMwareV2"
$Cloud                    = "Public"
$global:CacheDir          = $global:DefaultStringVal
$TimeStamp                = [DateTime]::Now.ToString("yyyy-MM-dd-HH-mm-ss")
$LogFileDir               = "$env:ProgramData`\Microsoft Azure\Logs"
$ConfigFileDir            = "$env:ProgramData`\Microsoft Azure\Config"
$CredFileDir              = "$env:ProgramData`\Microsoft Azure\CredStore"
$ApplianceVersionFilePath = "$Env:SystemDrive`\Users\Public\Desktop\ApplianceVersion.txt"

$RCMProxyMSI                   = "RcmProxyAgentSetup.msi"
$RCMReplicationAgentMSI        = "RcmReplicationAgentSetup.msi"
$PushInstallAgentMSI           = "PushInstallAgentSetup.msi"
$RCMReprotectAgentMSI          = "RcmReprotectAgentSetup.msi"
$ProcessServerMSI              = "ProcessServer.msi"
$ServerDiscoveryServiceMSI     = "Microsoft Azure Server Discovery Service.msi"
$VMWareDiscoveryServiceMSI     = "Microsoft Azure VMware Discovery Service.msi"
$DraExe                        = "AzureSiteRecoveryProvider.exe"
$WebAppMSI                     = "MicrosoftAzureDRApplianceConfigurationManager.msi"
$AutoUpdaterMSI                = "MicrosoftAzureAutoUpdate.msi"
$MarsEXE                       = "MARSAgentInstaller.exe"
$EdgeFolder 				   = $Env:SystemDrive + "\Program Files (x86)\Microsoft\Edge\Application"
$EdgeExe  					   = $EdgeFolder + "\msedge.exe"
$EdgeShortCut 				   = "$env:SystemDrive`\Users\Administrator\Desktop\Microsoft Edge.lnk"
$EdgePublicShortCut 		   = "$env:SystemDrive`\Users\Public\Desktop\Microsoft Edge.lnk"
$AzureBackupShortCut           = "$env:SystemDrive`\Users\Public\Desktop\Microsoft Azure Backup.lnk"
$RegHive 				       = "HKLM:\Software\Policies\Microsoft\Edge"
$ScriptsPath                   = "$env:ProgramData`\Microsoft Azure\Scripts"

$RCMProxyMSILog                = "$LogFileDir\RcmProxyAgentInstaller_$TimeStamp.log"
$RCMReplicationAgentMSILog     = "$LogFileDir\RcmReplicationAgentInstaller_$TimeStamp.log"
$PushInstallAgentMSILog        = "$LogFileDir\PushInstallAgentInstaller_$TimeStamp.log"
$RCMReprotectAgentMSILog       = "$LogFileDir\RcmReprotectAgentInstaller_$TimeStamp.log"
$ProcessServerMSILog           = "$LogFileDir\ProcessServerInstaller_$TimeStamp.log"
$VMWareDiscoveryServiceMSILog  = "$LogFileDir\DiscoveryVmwareInstaller_$TimeStamp.log"
$ServerDiscoveryServiceMSILog  = "$LogFileDir\DiscoveryServerInstaller_$TimeStamp.log"
$DraLog                        = "$LogFileDir\DRAInstaller_$TimeStamp.log"
$WebAppMSILog                  = "$LogFileDir\ConfigurationManagerInstaller_$TimeStamp.log"
$AutoUpdaterMSILog             = "$LogFileDir\AutoUpdateInstaller_$TimeStamp.log"

$ApplianceJsonFilePath           = "$ConfigFileDir\appliance.json"
$RCMProxyJsonFilePath            = "$ConfigFileDir\rcmproxyagent.json"
$RCMReplicationAgentJsonFilePath = "$ConfigFileDir\rcmreplicationagent.json"
$PushInstallAgentJsonFilePath    = "$ConfigFileDir\pushinstallagent.json"
$RCMReprotectAgentJsonFilePath   = "$ConfigFileDir\rcmreprotectagent.json"
$AutoUpdaterJsonFilePath         = "$ConfigFileDir\AutoUpdater.json"

$ApplianceJsonFileData   = @{
    "AppInsightsInstrumentationKey"="90b46585-1513-4a55-814c-bd57e9b24709";
    "Cloud"="$Cloud";
    "ComponentVersion"="1.0.0.1";
    "FabricType"="VMwareV2";
    "IsApplianceRegistered"="false";
    "ProviderId"="8416fccd-8af8-466e-8021-79db15038c87";
    "CacheDirectory"="$global:CacheDir";
}

$RCMProxyJsonFileData = @{
	"AppInsightsInstrumentationKey"="90b46585-1513-4a55-814c-bd57e9b24709";
	"IsConfigured"="false";
	"IsRegistered"="false"
}

$RCMReplicationAgentJsonFileData = @{
	"AppInsightsInstrumentationKey"="90b46585-1513-4a55-814c-bd57e9b24709";
	"IsConfigured"="false";
	"IsRegistered"="false"
}

$PushInstallAgentJsonFileData = @{
	"AppInsightsInstrumentationKey"="90b46585-1513-4a55-814c-bd57e9b24709";
	"IsConfigured"="false";
	"IsRegistered"="false"
}

$RCMReprotectAgentJsonFileData = @{
	"AppInsightsInstrumentationKey"="90b46585-1513-4a55-814c-bd57e9b24709";
	"IsConfigured"="false";
	"IsRegistered"="false"
}

$AutoUpdaterJsonFileData = @{
    "ComponentVersion"="1.0.0.1";
    "AutoUpdateEnabled"="True";
    "ProviderId"="8416fccd-8af8-466e-8021-79db15038c87";
    "AutoUpdaterDownloadLink"="https://aka.ms/v2arcmlatestapplianceservices"
}

$RegAzureAppliancePath = "HKLM:\SOFTWARE\Microsoft\Azure Appliance"
$RegAzureCredStorePath = "HKLM:\Software\Microsoft\AzureAppliance"

## Creating the logfile
New-Item -ItemType Directory -Force -Path $LogFileDir | Out-Null
$InstallerLog = "$LogFileDir\AzureMigrateScenarioInstaller_$TimeStamp.log"
Log-Success "Log file created `"$InstallerLog`" for troubleshooting purpose.`n"

<#
.SYNOPSIS
Detect previous installation
Usage:
    DetectPreviousInstallation
#>
function DetectPreviousInstallation
{ 
    if([System.IO.File]::Exists($ApplianceJsonFilePath))
    {
        Log-Error "This host has already been used as DR Appliance. Aborting the installation..."         
        exit -17
    }
}

<#
.SYNOPSIS
Get cache drive.
Usage:
    GetCacheDrive
#>
function GetCacheDrive
{
    $maxDriveFreeSpace = 600
    $driveName = $global:DefaultStringVal
    $drives = ([System.IO.DriveInfo]::getdrives() | Where-Object {$_.DriveType -eq 'Fixed'} | Where-Object {$_.IsReady -eq 'True'} | Where-Object {$_.DriveFormat -eq 'NTFS'} | select -Property Name).Name
    ForEach ($drive in $drives )
    {
        $drive = $drive.Trimend('\')
        $freeSpace = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$drive'" |Foreach-Object {$_.FreeSpace}
		$freeSpaceInGB = $freeSpace / (1024 * 1024 * 1024)
		Log-Info "Free space available in $drive drive - $freeSpaceInGB GB"
 
        if ($freeSpaceInGB -ge $maxDriveFreeSpace) {
            $driveName = $drive
            break
        }
    }

    $global:CacheDir = "$driveName"

    if ($global:CacheDir -eq $global:DefaultStringVal)
    {
        Log-Error "Aborting the installation, as atleast $maxDriveFreeSpace GB free space is required to proceed..."
        exit -20
    }

    $global:CacheDir = "$driveName" + "\"

    Log-Info "Cache drive is set to $global:CacheDir"
}

<#
.SYNOPSIS
Configure Edge Enterprise Browser and hide first run experience.
Usage:
    ConfigureEdgeBrowser
#>

function ConfigureEdgeBrowser
{
    Log-Info "Configuring Edge browser."

	if ( -not (Test-Path $RegHive))
	{                
		New-Item -Path $RegHive -Force
	}
		
	New-ItemProperty -Path $RegHive -Name "HideFirstRunExperience" -PropertyType "dword" -Value 1 -Force
}

<#
.SYNOPSIS
To remove the required file.
Usage:
    RemoveFile -FilePath
#>

function RemoveFile
{
    param(
        [string] $FilePath
        )

		# Removing file from the path.
		if (Test-Path -Path $FilePath)
		{
			Log-Info "Removing file - $FilePath"
			Remove-Item -Path $FilePath -Force
		}
}

<#
.SYNOPSIS
Install MSI
Usage:
    InstallMSI -MSIFilePath $MSIFilePath -MSIInstallLogName $MSIInstallLogName
#>

function InstallMSI
{ 
    param(
        [string] $MSIFilePath,
        [string] $MSIInstallLogName,
        [string] $ExtraArguments = ""
        )

    Log-Info "Installing $MSIFilePath..."

    if (-Not (Test-Path -Path $MSIFilePath -PathType Any))
    {
        Log-Error "MSI not found: $MSIFilePath. Aborting..."
        Log-Warning "Please ensure all MSIs are copied to the same folder as the current script."
        exit -11
    }

    $Arguments = "/i `"$MSIFilePath`" /quiet /lv `"$MSIInstallLogName`""
	
	if (![string]::IsNullOrEmpty($ExtraArguments))
	{
	    $Arguments = $Arguments + "$ExtraArguments"
	}

    $process = (Start-Process -Wait -Passthru -FilePath msiexec -ArgumentList "$Arguments")

    $returnCode = $process.ExitCode;
    
    if ($returnCode -eq 0 -or $returnCode -eq 3010)
    {
        Log-Success "[OK]`n"
    }
    else
    {
        Log-Error "$MSIFilePath installation failed. More logs available at $MSIInstallLogName. Aborting..."
        Log-Warning "Please refer to https://learn.microsoft.com/en-us/windows/win32/msi/windows-installer-error-messages to get details about the error code: $returnCode. Please share the installation log file $MSIInstallLogName while contacting Microsoft Support."
        exit -12
    }
}

<#
.SYNOPSIS
Create JsonFile
Usage:
    CreateJsonFile -JsonFileData $JsonFileData -JsonFilePath $JsonFilePath
#>
function CreateJsonFile
{ 
    param(
        $JsonFileData,
        [string] $JsonFilePath
        )
	
	if (Test-path -path $JsonFilePath)
	{
		Log-Info "Skipping creating config File at $JsonFilePath..."
		return;
	}

    Log-Info "Creating config File at $JsonFilePath..."

    New-Item -Path $ConfigFileDir -type directory -Force | Out-Null
    $JsonFileData | ConvertTo-Json | Add-Content -Path $JsonFilePath -Encoding UTF8

    if ($?)
    {
        Log-Success "[OK]`n"
    }
    else
    {
        Log-Error "Failure in creating $JsonFilePath. Aborting..."
        exit -10
    }
}

<#
.SYNOPSIS
Execute Powershell scripts. 
Usage:
    ExecutePSScripts -ScriptFilePath $ScriptFilePath -ScriptArguments $ScriptArguments
#>

function ExecutePSScripts
{ 
    param(
        [string] $ScriptFilePath,
        [string] $ScriptArguments = ""
        )

    Log-Info "Running powershell script $ScriptFilePath..."
    if (-Not (Test-Path -Path $ScriptFilePath -PathType Any))
    {
        Log-Error "Script file not found: $ScriptFilePath. Aborting..."
        Log-Warning "Please download the package again and retry."
        exit -15
    }

    & "$ScriptFilePath" "$ScriptArguments" | Out-Null

    if ($?)
    {
        Log-Success "[OK]`n"
    }
    else 
    {
        Log-Error "Failed to execute script $ScriptFilePath with error $Error. Aborting..."
        exit -16
    }
}

<#
.SYNOPSIS
Create Version file.
Usage:
    CreateApplianceVersionFile
#>

function CreateApplianceVersionFile
{
    Log-Info "Creating Appliance Version File..."
    $ApplianceVersion = "1." + (Get-Date).ToString('yy.MM.dd')
    
    # Create Appliance version text file.
    New-Item $ApplianceVersionFilePath -ItemType File -Value $ApplianceVersion -Force | Out-Null
    Set-ItemProperty $ApplianceVersionFilePath -name IsReadOnly -value $true

    if ($?)
    {
        Log-Success "[OK]`n"
    }
    else 
    {
        Log-Warning "Failed to create Appliance Version file with at $ApplianceVersionFilePath. Continuing..."
    }
}

<#
.SYNOPSIS
Validate and exit if minimum defined PowerShell version is not available.
Usage:
    ValidatePSVersion
#>

function ValidatePSVersion
{
    [System.Version]$minVer = "4.0"

    Log-Info "Verifying the PowerShell version to run the script..."

    if ($PSVersionTable.PSVersion)
    {
        $global:PsVer = $PSVersionTable.PSVersion
    }
    
    If ($global:PsVer -lt $minVer)
    {
        Log-Error "PowerShell version $minVer, or higher is required. Current PowerShell version is $global:PsVer. Aborting..."
        exit -2;
    }
    else
    {
        Log-Success "[OK]`n"
    }
}

<#
.SYNOPSIS
Validate and exit if PS process in not 64-bit as few cmdlets like install-windowsfeature is not available in 32-bit.
Usage:
    ValidateIsPowerShell64BitProcess
#>

function ValidateIsPowerShell64BitProcess
{
    Log-Info "Verifying the PowerShell is running in 64-bit mode..."

    # This check is valid for PowerShell 3.0 and higher only.
    if ([Environment]::Is64BitProcess)
    {
        Log-Success "[OK]`n"
    }
    else
    {
        Log-Warning "PowerShell process is found to be 32-bit. While launching PowerShell do not select Windows PowerShell (x86) and rerun the script. Aborting..."        
        Log-Error "[Failed]`n"
        exit -3;
    }
}

<#
.SYNOPSIS
Validate OS version
Usage:
    ValidateOSVersion
#>
function ValidateOSVersion
{
    [System.Version]$ver = "0.0"
    [System.Version]$minVer = "10.0"
    Log-Info "Verifying supported Operating System version..."
    $ServerString = "Server 2022"
    $OS = Get-WmiObject Win32_OperatingSystem
    $ver = $OS.Version

    If ($ver -lt $minVer)
    {
        Log-Error "The os version is $ver, minimum supported version is $minVer. Aborting..."
        exit -4
    }
    elseif ($OS.Caption.contains($ServerString) -eq $false)
    {
        Log-Error "OS should be Windows Server 2022. Aborting..."
        exit -5
    }else
    {
        Log-Success "[OK]`n"
    }
}

<#
.SYNOPSIS
Add AzureCloud registry which used to identify NationalCloud
Usage:
    AddAzureCloudRegistry 
#>

function AddingRegistryKeys
{ 
    Log-Info "Adding\Updating Registry Keys...`n"

    if ( -not (Test-Path $RegAzureAppliancePath))
    {
        Log-Info "`tCreating Registry Node: $RegAzureAppliancePath"
        New-Item -Path $RegAzureAppliancePath -Force | Out-Null
    }
            
    New-ItemProperty -Path $RegAzureAppliancePath -Name AzureCloud -Value $Cloud -Force | Out-Null
    New-ItemProperty -Path $RegAzureAppliancePath -Name Type -Value InMageRcm -Force | Out-Null

    if ( -not (Test-Path $RegAzureCredStorePath))
    {
        Log-Info "`tCreating Registry Node: $RegAzureCredStorePath"
        New-Item -Path $RegAzureCredStorePath -Force | Out-Null
    }

    New-ItemProperty -Path $RegAzureCredStorePath -Name CredStoreDefaultPath `
        -value "%Programdata%\Microsoft Azure\CredStore\Credentials.json" -Force | Out-Null

    if ( $?)
    {
        Log-Success "`n[OK]`n"
    }
    else 
    {
        Log-Error "Failed to add\update registry keys. Aborting..."
        Log-Warning "Please ensure that the current user has access to adding registry keys under the path: $RegAzureAppliancePath or $RegAzureCredStorePath"
        exit -6
    }
}

<#
.SYNOPSIS
Enables IIS modules.
Usage:
    EnableIIS 
#>

function EnableIIS
{
    Log-Info "Enabling IIS Role and dependent features..."

    Install-WindowsFeature WAS, WAS-Process-Model, WAS-Config-APIs, Web-Server, `
        Web-WebServer, Web-Mgmt-Service, Web-Request-Monitor, Web-Common-Http, Web-Static-Content, `
        Web-Default-Doc, Web-Dir-Browsing, Web-Http-Errors, Web-App-Dev, Web-CGI, Web-Health, `
        Web-Http-Logging, Web-Log-Libraries, Web-Security, Web-Filtering, Web-Performance, `
        Web-Stat-Compression, Web-Mgmt-Tools, Web-Mgmt-Console, Web-Scripting-Tools, `
        Web-Asp-Net45, Web-Net-Ext45, Web-Http-Redirect, Web-Windows-Auth, Web-Url-Auth

    if ($?)
    {
        Log-Success "[OK]`n"
    }
    else
    {
        Log-Warning "Please ensure the following roles are enabled manually: `
            WAS (Windows Activation Service), WAS-Process-Model, WAS-Config-APIs, Web-Server (IIS), '
            Web-WebServer, Web-Mgmt-Service, Web-Request-Monitor, Web-Common-Http, Web-Static-Content, '
            Web-Default-Doc, Web-Dir-Browsing, Web-Http-Errors, Web-App-Dev, Web-CGI, Web-Health,'
            Web-Http-Logging, Web-Log-Libraries, Web-Security, Web-Filtering, Web-Performance, '
            Web-Stat-Compression, Web-Mgmt-Tools, Web-Mgmt-Console, Web-Scripting-Tools, '
            Web-Asp-Net45, Web-Net-Ext45, Web-Http-Redirect, Web-Windows-Auth, Web-Url-Auth"

        exit -7
    }
}


<#
.SYNOPSIS
Install IIS rewrite module.
Usage:
    InstallRewriteModule
#>

function InstallRewriteModule
{
    Log-Info "Installing the IIS URL Rewrite Module 2..."

    # Check if URL Rewrite Module is already installed.
    $rewriteDll = "$env:SystemRoot\System32\inetsrv\rewrite.dll"
    $rewriteReg = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*IIS URL Rewrite Module*" }
    if ($null -eq $rewriteReg) {
        $rewriteReg = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "*IIS URL Rewrite Module*" }
    }

    if ((Test-Path $rewriteDll) -or ($null -ne $rewriteReg))
    {
        Log-Success "IIS URL Rewrite Module 2 is already installed. Skipping. [OK]`n"
        return
    }

    $rewriteFile = "$PSScriptRoot\rewrite_amd64_en-US.msi"
    if (-not (Test-Path $rewriteFile))
    {
        Log-Error "IIS URL Rewrite Module 2 MSI not found at $rewriteFile."
        Log-Error "Please install URL Rewrite Module 2 manually from https://www.iis.net/downloads/microsoft/url-rewrite and re-run the script."
        exit -8
    }

    $process = (Start-Process -Wait -Passthru -FilePath "MsiExec.exe" `
        -ArgumentList "/i `"$rewriteFile`" /qn /norestart")

    Start-Sleep -Seconds 20

    $returnCode = $process.ExitCode;

    if ($returnCode -eq 0 -or $returnCode -eq 3010)
    {
        Log-Success "[OK]`n"
    }
    elseif ($returnCode -eq 1638)
    {
        # 1638 = another version of the product is already installed.
        Log-Success "IIS URL Rewrite Module 2 is already installed (exit code 1638). [OK]`n"
    }
    else
    {
        Log-Error "IIS URL Rewrite Module 2 installation failed with exit code $returnCode. Aborting..."
        exit -8
    }
}

<#
.SYNOPSIS
Ensure IIS backend services are in running state. During IISReset they can remain in stop state as well.
Usage:
    StartIISServices
#>

function StartIISServices
{
    Log-Info "Ensuring critical services for Configuration Manager are runing..."

    Start-service -Name WAS
    Start-service -Name W3SVC

    if ($?)
    {
        Log-Success "[OK]`n"
    } else 
    {
        Log-Error "Failed to start services WAS/W3SVC. Aborting..."
        Log-Warning "Manually start the services WAS and W3SVC"
        exit -14
    }
}

<#
.SYNOPSIS
Invoke EXE.
Usage:
	InvokeExe -ExePath $ExePath -Arguments $Arguments
#>
function InvokeExe
{ 
	param(
        [string] $ExePath,
        [string] $Arguments
        )
    
    $process = (Start-Process -Wait -Passthru -FilePath $ExePath -ArgumentList "$Arguments")

    $returnCode = $process.ExitCode;
    Log-info "Return code from $ExePath : $returnCode"
    
    if ($returnCode -eq 0 -or $returnCode -eq 3010)
    {
        Log-Success "[OK]`n"
    }
    else
    {
        Log-Error "$ExePath installation failed. Aborting..."
        exit -13
    }
}

<#
.SYNOPSIS
Copy file from source to destination.
Usage:
	CopyFile -SourcePath $SourcePath -DestinationPath $DestinationPath
#>
function CopyFile
{
    param(
        [string] $SourcePath,
        [string] $DestinationPath
        )

    Copy-Item $SourcePath -Destination $DestinationPath
	if ( $? -eq "True" )
	{
		Log-Info "Successfully copied $SourcePath to $DestinationPath"
	}
	else 
	{
		Log-Error "Failed to copy $SourcePath to $DestinationPath."
		exit -18
	}
}

<#
.SYNOPSIS
Install DRA.
Usage:
	InstallDRA
#>
function InstallDRA
{
	$SetupDrExe = "$PSScriptRoot\DRA\SETUPDR.EXE"
    $extractCmd = ' /q /x:' + "$PSScriptRoot\DRA"
	
	Log-Info "Extracting DRA installer."
    InvokeExe -ExePath "$DraExe" -Arguments "$extractCmd"

    Log-Info "Installing DRA."
    InvokeExe -ExePath "$SetupDrExe" -Arguments "/i /LogFileName $DraLog /AdapterName InMageRcm"
}

try
{
    $Error.Clear()
    
    # Validations.
	DetectPreviousInstallation
    ValidatePSVersion
    ValidateIsPowerShell64BitProcess
    ValidateOSVersion
	
	if (-not (Test-Path -Path $EdgeExe -PathType Any))
	{
		Log-Error "Edge browser is not exists on this machine. If not exists, then download the latest edge browser and, install edge browser and, retry the installation."
        exit -19
	}
	else
	{
        ConfigureEdgeBrowser
		RemoveFile -FilePath $EdgeShortCut
		RemoveFile -FilePath $EdgePublicShortCut
	}
	
    GetCacheDrive

    # Add the required registry keys.
    AddingRegistryKeys

    # Enable IIS.
    EnableIIS

    # Install rewrite module.
    InstallRewriteModule
    
    # Set trusted hosts to machine.
	Set-Item -Path WSMan:\localhost\Client\TrustedHosts "*" -Force

    # Copy Agents.
    $AgentsSourcePath = "$PSScriptRoot\Agents"
    $AgentsRepoPath = "$global:CacheDir\Software\Agents"
    New-Item -Path $AgentsRepoPath -type directory -Force
    $Agents = Get-ChildItem -Path $AgentsSourcePath
    ForEach ($agent in $Agents) {
        CopyFile -SourcePath "$AgentsSourcePath\$agent" -DestinationPath $AgentsRepoPath
	}

    # Copy Push clients.
    $PushClientsSourcePath = "$PSScriptRoot\PushClients"
    $PushClientsRepoPath = "$global:CacheDir\Software\PushClients"
    New-Item -Path $PushClientsRepoPath -type directory -Force
    $PushClients = Get-ChildItem -Path $PushClientsSourcePath
    ForEach ($pushclient in $PushClients) {
        CopyFile -SourcePath "$PushClientsSourcePath\$pushclient" -DestinationPath $PushClientsRepoPath
	}

    # Install RCMProxy agent.
    CreateJsonFile -JsonFileData $RCMProxyJsonFileData -JsonFilePath $RCMProxyJsonFilePath
    InstallMSI -MSIFilePath "$PSScriptRoot\$RCMProxyMSI" -MSIInstallLogName $RCMProxyMSILog

    # Install RCMReplication agent.
    CreateJsonFile -JsonFileData $RCMReplicationAgentJsonFileData -JsonFilePath $RCMReplicationAgentJsonFilePath
    InstallMSI -MSIFilePath "$PSScriptRoot\$RCMReplicationAgentMSI" -MSIInstallLogName $RCMReplicationAgentMSILog

    # Install RCMReprotect agent.
    CreateJsonFile -JsonFileData $RCMReprotectAgentJsonFileData -JsonFilePath $RCMReprotectAgentJsonFilePath
    InstallMSI -MSIFilePath "$PSScriptRoot\$RCMReprotectAgentMSI" -MSIInstallLogName $RCMReprotectAgentMSILog

    # Install PushInstall agent.
    CreateJsonFile -JsonFileData $PushInstallAgentJsonFileData -JsonFilePath $PushInstallAgentJsonFilePath
    InstallMSI -MSIFilePath "$PSScriptRoot\$PushInstallAgentMSI" -MSIInstallLogName $PushInstallAgentMSILog

    # Install DRA.
	InstallDRA

    # Install Server Discovery service.
    InstallMSI -MSIFilePath "$PSScriptRoot\$ServerDiscoveryServiceMSI" -MSIInstallLogName $ServerDiscoveryServiceMSILog

    # Install VMware Discovery service.
    InstallMSI -MSIFilePath "$PSScriptRoot\$VMwareDiscoveryServiceMSI" -MSIInstallLogName $VMwareDiscoveryServiceMSILog

    # Install MARS agent.
    InvokeExe -ExePath "$PSScriptRoot\$MarsEXE" -Arguments "/q /nu" 

    # Install Process Server.
    InstallMSI -MSIFilePath "$PSScriptRoot\$ProcessServerMSI" -MSIInstallLogName $ProcessServerMSILog -ExtraArguments "Mode=Rcm"

    # Install Appliance Configuration Manager.
    InstallMSI -MSIFilePath "$PSScriptRoot\$WebAppMSI" -MSIInstallLogName $WebAppMSILog
    
    # Install Agent updater.
    CreateJsonFile -JsonFileData $AutoUpdaterJsonFileData -JsonFilePath $AutoUpdaterJsonFilePath
    InstallMSI -MSIFilePath "$PSScriptRoot\$AutoUpdaterMSI" -MSIInstallLogName $AutoUpdaterMSILog

    # Create Appliance version file.
    CreateApplianceVersionFile

    # Ensure critical services for WebApp are in running state.
    StartIISServices

    New-Item -Path $ScriptsPath -type directory -Force
	
    # Execute powershell scripts
    ExecutePSScripts -ScriptFilePath "$PSScriptRoot\EnableDiskOnline.ps1"
    ExecutePSScripts -ScriptFilePath "$PSScriptRoot\WebBinding.ps1"
	ExecutePSScripts -ScriptFilePath "$PSScriptRoot\SetRegistryForTrustedSites.ps1" -ScriptArguments "-LaunchApplication No"

    # Create Appliance Json file.
	$ApplianceJsonFileData.CacheDirectory = $global:CacheDir
    CreateJsonFile -JsonFileData $ApplianceJsonFileData -JsonFilePath $ApplianceJsonFilePath
	
	# Removing desktop shortcut for Azure Backup.
	RemoveFile -FilePath $AzureBackupShortCut

    Log-Success "Installation completed successfully."

    if ($global:WarningCount -gt 0)
    {
        Log-Warning "Please review the $global:WarningCount warning(s) hit during script execution and take manual corrective action as suggested in the warning(s)."        
    }
}
catch
{
    Log-Error "Script execution failed with error $_.Exception.Message"
    Log-Error "Error Record: $_.Exception.ErrorRecord"
    Log-Error "Exception caught:  $_.Exception"
    Log-Warning "Retry the script after resolving the issue(s) or contact Microsoft Support."
    exit -1
}

# SIG # Begin signature block
# MIIoUQYJKoZIhvcNAQcCoIIoQjCCKD4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAYGiTq22YceEA9
# 5JfHbQI+9YdcckMicdEw40tp0RSNG6CCDYUwggYDMIID66ADAgECAhMzAAAEhJji
# EuB4ozFdAAAAAASEMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjUwNjE5MTgyMTM1WhcNMjYwNjE3MTgyMTM1WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDtekqMKDnzfsyc1T1QpHfFtr+rkir8ldzLPKmMXbRDouVXAsvBfd6E82tPj4Yz
# aSluGDQoX3NpMKooKeVFjjNRq37yyT/h1QTLMB8dpmsZ/70UM+U/sYxvt1PWWxLj
# MNIXqzB8PjG6i7H2YFgk4YOhfGSekvnzW13dLAtfjD0wiwREPvCNlilRz7XoFde5
# KO01eFiWeteh48qUOqUaAkIznC4XB3sFd1LWUmupXHK05QfJSmnei9qZJBYTt8Zh
# ArGDh7nQn+Y1jOA3oBiCUJ4n1CMaWdDhrgdMuu026oWAbfC3prqkUn8LWp28H+2S
# LetNG5KQZZwvy3Zcn7+PQGl5AgMBAAGjggGCMIIBfjAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUBN/0b6Fh6nMdE4FAxYG9kWCpbYUw
# VAYDVR0RBE0wS6RJMEcxLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJh
# dGlvbnMgTGltaXRlZDEWMBQGA1UEBRMNMjMwMDEyKzUwNTM2MjAfBgNVHSMEGDAW
# gBRIbmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIw
# MTEtMDctMDguY3JsMGEGCCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDEx
# XzIwMTEtMDctMDguY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIB
# AGLQps1XU4RTcoDIDLP6QG3NnRE3p/WSMp61Cs8Z+JUv3xJWGtBzYmCINmHVFv6i
# 8pYF/e79FNK6P1oKjduxqHSicBdg8Mj0k8kDFA/0eU26bPBRQUIaiWrhsDOrXWdL
# m7Zmu516oQoUWcINs4jBfjDEVV4bmgQYfe+4/MUJwQJ9h6mfE+kcCP4HlP4ChIQB
# UHoSymakcTBvZw+Qst7sbdt5KnQKkSEN01CzPG1awClCI6zLKf/vKIwnqHw/+Wvc
# Ar7gwKlWNmLwTNi807r9rWsXQep1Q8YMkIuGmZ0a1qCd3GuOkSRznz2/0ojeZVYh
# ZyohCQi1Bs+xfRkv/fy0HfV3mNyO22dFUvHzBZgqE5FbGjmUnrSr1x8lCrK+s4A+
# bOGp2IejOphWoZEPGOco/HEznZ5Lk6w6W+E2Jy3PHoFE0Y8TtkSE4/80Y2lBJhLj
# 27d8ueJ8IdQhSpL/WzTjjnuYH7Dx5o9pWdIGSaFNYuSqOYxrVW7N4AEQVRDZeqDc
# fqPG3O6r5SNsxXbd71DCIQURtUKss53ON+vrlV0rjiKBIdwvMNLQ9zK0jy77owDy
# XXoYkQxakN2uFIBO1UNAvCYXjs4rw3SRmBX9qiZ5ENxcn/pLMkiyb68QdwHUXz+1
# fI6ea3/jjpNPz6Dlc/RMcXIWeMMkhup/XEbwu73U+uz/MIIHejCCBWKgAwIBAgIK
# YQ6Q0gAAAAAAAzANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlm
# aWNhdGUgQXV0aG9yaXR5IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEw
# OTA5WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYD
# VQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+la
# UKq4BjgaBEm6f8MMHt03a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc
# 6Whe0t+bU7IKLMOv2akrrnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4D
# dato88tt8zpcoRb0RrrgOGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+
# lD3v++MrWhAfTVYoonpy4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nk
# kDstrjNYxbc+/jLTswM9sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6
# A4aN91/w0FK/jJSHvMAhdCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmd
# X4jiJV3TIUs+UsS1Vz8kA/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL
# 5zmhD+kjSbwYuER8ReTBw3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zd
# sGbiwZeBe+3W7UvnSSmnEyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3
# T8HhhUSJxAlMxdSlQy90lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS
# 4NaIjAsCAwEAAaOCAe0wggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRI
# bmTlUAXTgqoXNzcitW2oynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTAL
# BgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBD
# uRQFTuHqp8cx0SOJNDBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jv
# c29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3JsMF4GCCsGAQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3J0MIGfBgNVHSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1h
# cnljcHMuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkA
# YwB5AF8AcwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn
# 8oalmOBUeRou09h0ZyKbC5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7
# v0epo/Np22O/IjWll11lhJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0b
# pdS1HXeUOeLpZMlEPXh6I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/
# KmtYSWMfCWluWpiW5IP0wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvy
# CInWH8MyGOLwxS3OW560STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBp
# mLJZiWhub6e3dMNABQamASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJi
# hsMdYzaXht/a8/jyFqGaJ+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYb
# BL7fQccOKO7eZS/sl/ahXJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbS
# oqKfenoi+kiVH6v7RyOA9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sL
# gOppO6/8MO0ETI7f33VtY5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtX
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGiIwghoeAgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAASEmOIS4HijMV0AAAAA
# BIQwDQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEINLp
# skBtYk4OxdRKqChcO5kXMZh0uraWCg+Hk6VjPIaDMEIGCisGAQQBgjcCAQwxNDAy
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20wDQYJKoZIhvcNAQEBBQAEggEAyRrA4WeEoj+YoregdxWO1Af/wFoE5Kx1PTlw
# 5ClOtJuqg9qtJbTPdstboLaPCxxCtVlt38mAIaHeq9d1CUvMK9jnZu91ufN9y08g
# LjKCOvMnwWv3L7a/M1gGjlR0BmBhOVmT/sOmuu6onQGxQPOGPmN4F2/1WfRaePEh
# 8HqyQEBtgqnio+IEgvNKqb/MaYHzdc3KOrIrHXyQpKyE9S737u0w6Y1tXAYS90Vi
# gS9HhGUFFpB9KWrSMZeduR3YbnCiqV1XBri9helSKyQ2X623rAVJujvGRkd7i0Ai
# Qg8Nes0L4nd0AQjmTGaXhSx4vOy5OzUue2j/p5R+x57XzcGz/aGCF6wwgheoBgor
# BgEEAYI3AwMBMYIXmDCCF5QGCSqGSIb3DQEHAqCCF4UwgheBAgEDMQ8wDQYJYIZI
# AWUDBAIBBQAwggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYKKwYBBAGE
# WQoDATAxMA0GCWCGSAFlAwQCAQUABCB57utBxm57aYuaY+dLi32HrPp2+jnNHzb+
# s/f5heoNAgIGaKOuDev0GBIyMDI1MDkyMDAwNDYyNi40MlowBIACAfSggdmkgdYw
# gdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsT
# JE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMe
# blNoaWVsZCBUU1MgRVNOOjJEMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3Nv
# ZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR+zCCBygwggUQoAMCAQICEzMAAAH9c/lo
# Ws0MYe0AAQAAAf0wDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# UENBIDIwMTAwHhcNMjQwNzI1MTgzMTE2WhcNMjUxMDIyMTgzMTE2WjCB0zELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9z
# b2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxk
# IFRTUyBFU046MkQxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCh
# Zaz4P467gmNidEdF527QxMVjM0kRU+cgvNzTZHepue6O+FmCSGn6n+XKZgvORDIb
# bOnFhx5OMgXseJBZu3oVbcBGQGu2ElTPTlmcqlwXfWWlQRvyBReIPbEimjxgz5IP
# RL6FM/VMID/B7fzJncES2Zm1xWdotGn8C+yqD7kojQrDpMMmkrBMuXRVbT/bewqK
# R5YNKcdB5Oms7TMib9u1qBJibdX/zNeV/HLuz8RUV1KCUcaxSrwRm6lQ7xdsfPPu
# 1RHKIPeQ7E2fDmjHV5lf9z9eZbgfpvjI2ZkXTBNm7DfvIDU8ko7JJKtetYSH4fr7
# 5Zvr7WW0wI+gwkdS08/cKfQI1w2+s/Im0NpyqOchOsvOuwd04uqOwfbb1mS+d2TQ
# irEENmAyhj4R/t98VE/ak+SsXUX0hwGRjPyEv5CNf67jLhSqrhS1PtVGeyq9H/H/
# 5AsTSlxISH9cTXDV9ynomarxGccReKTJwws39r8pjGlI/cV8Vstm5/6oivIUvSAQ
# PK1qkafU42NWSIqlU/a6pUhiPhWIKPLmktRx4x6qIqBiqGmZQcITZaywsuF1AEd2
# mXbz6T5ljqbh08WcSgZwke4xwhmfDhw7CLGiNE6v42rvVwmPtDgvRfA++5MdC3Sg
# ftEoxCCazLsJUPu/nl06F0dd1izI7r10B0r6daXJhwIDAQABo4IBSTCCAUUwHQYD
# VR0OBBYEFOkMxcDhlbz7Ivb7e8DpGZTugQqkMB8GA1UdIwQYMBaAFJ+nFV0AXmJd
# g/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0El
# MjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGlt
# ZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0l
# AQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUA
# A4ICAQBj2Fhf5PkCYKtgZof3pN1HlPnb8804bvJJh6im/h+WcNZAuEGWtq8CD6mO
# U2/ldJdmsoa/x7izl0nlZ2F8L3LAVCrhOZedR689e2W5tmT7TYFcrr/beEzRNIqz
# YqWFiKrNtF7xBsx8pcQO28ygdJlPuv7AjYiCNhDCRr7c/1VeARHC7jr9zPPwhH9m
# r687nnbcmV3qyxW7Oz27AismF9xgGPnSZdZEFwyHNqMuNYOByKHQO7KQ9wGmhMuU
# 4vwuleiiqev5AtgTgGlR6ncnJIxh8/PaF84veDTZYR+w7GnwA1tx2KozfV2be9KF
# 4SSaMcDbO4z5OCfiPmf4CfLsg4NhCQis1WEt0wvT167V0g+GnbiUW2dZNg1oVM58
# yoVrcBvwoMqJyanQC2FE1lWDQE8Avnz4HRRygEYrNL2OxzA5O7UmY2WKw4qRVRWR
# InkWj9y18NI90JNVohdcXuXjSTVwz9fY7Ql0BL3tPvyViO3D8/Ju7NfmyHEGH9Gp
# M+8LICEjEFUp83+F+zgIigVqpYnSv/xIHUIazLIhw98SAyjxx6rXDlmjQl+fIWLo
# a6j7Pcs8WX97FBpG5sSuwBRN/IFjn/mWLK+MCDINicQHy8c7tzsWDa0Z3mEaBiz4
# A6hbHbj5dzLGlSQBqMOGTL0OX7wllOO2zoFxP2xhOY6h2T9KAjCCB3EwggVZoAMC
# AQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29m
# dCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIy
# NVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAw
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9
# DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2
# Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N
# 7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXc
# ag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJ
# j361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjk
# lqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37Zy
# L9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M
# 269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLX
# pyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLU
# HMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode
# 2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEA
# ATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYE
# FJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEB
# MEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# RG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEE
# AYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB
# /zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEug
# SaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9N
# aWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsG
# AQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jv
# b0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt
# 4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsP
# MeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++
# Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9
# QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2
# wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aR
# AfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5z
# bcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nx
# t67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3
# Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+AN
# uOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/Z
# cGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNWMIICPgIBATCCAQGhgdmkgdYw
# gdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsT
# JE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMe
# blNoaWVsZCBUU1MgRVNOOjJEMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3Nv
# ZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQCiPRa1VVBQ1Iqi
# q2uOKdECwFR2g6CBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# MA0GCSqGSIb3DQEBCwUAAgUA7HhZZTAiGA8yMDI1MDkxOTIyMzYyMVoYDzIwMjUw
# OTIwMjIzNjIxWjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDseFllAgEAMAcCAQAC
# AhGaMAcCAQACAhJPMAoCBQDsearlAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisG
# AQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQAD
# ggEBABQJ5uYctesv76qUL6ApL89TSnxKMcbj3ydLSnHWdCYGXeuN0AharL+IrwxQ
# v+S2EaflS6N9grvhFmUEPn0v6QCVL+Dkhf3vpsZeopwoW0/X92IwrKGyj3IxQRFG
# /JNjWxLyIlx/LIuH/xFyEWOiL3ca/uF/mQolVADORVt/V/AjZRt58piiO900DVLX
# UkToHGF+xFy1V+ICvvqwITU8xFL5zIYv3SrZ8bBsWdVIvC2ojClgiuOy4B7U2xSR
# NxyaCzJHfRxDzWbD7QrhIZsE5E0czmzWXjta81hql1y8eR7WoGMZHdSQiA5cNSBZ
# srhVvqV/j0eV5s6YFaF+YiGF+L8xggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBQQ0EgMjAxMAITMwAAAf1z+WhazQxh7QABAAAB/TANBglghkgBZQME
# AgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJ
# BDEiBCDZBDL+KOqN7a5M2y4OABhLTscGCkAObYBj9uOuDkWr2TCB+gYLKoZIhvcN
# AQkQAi8xgeowgecwgeQwgb0EIIAoSA3JSjC8h/H94N9hK6keR4XWnoYXCMoGzyVE
# Hg1HMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAH9
# c/loWs0MYe0AAQAAAf0wIgQgnfCnST2B/hfFJrv8nllLp3XMCKVoHK77xV1CQ9XW
# 3mIwDQYJKoZIhvcNAQELBQAEggIAku/XbQ75j1KqSgz7vIZMiVlAg6tMgGQ1r7Ib
# OK1jQYXXJ6M4QUXEq8sonvFjCm/we9MIyHJF4FyEOG9FCbhpl1lFihj3H8ryZxS7
# yuOucd9c7h7TSAeZTPVxf13kg+eMDSKuJsvKY/bpM8tzkRyNheTcoRgrIFc8ELeA
# o9EfXEtaEb1hPT/DZ8CiFC2wO+V1cZf17+GB9tZz/I2GsDnfJBtPHYCZEi7Smli/
# B41rYTtQhkP1R9GbymaopRsSdwQYzaCiFNaESOaZPF3Zj0P0Ht6ucsI+V1/WNB2K
# 986laXStif5m1iIdvOYkMSgxgwESO8sHEIJ6CdwmjbkF2LLESF6/r5NMNxrSmN1H
# CG0gt69wOeQe7DeuzytSFqlBTXpZ124co726ZCck5kCg+6vVOYaT/jEQtuWiOiqT
# /nDFVd0md7gykj35+h5mwXgNbXG8OTQgh7h+mq3N4AKc61dPo6gu3TxTo6LeswFu
# ECnU9185PRfZiebzZrgjoKRtHHjCaEJF+7i0TDMPRrKE7+jD6Ekfwk6psP2zDO0R
# 5mQ1lB5JcFVydZCuhSRiHr5rjyi2c4V3w/witATY/Xcp+N20swZ57pbs0Q1ifxuI
# q/e4vYjXP95CMQbo3tKlB9IupzjxzzEdzP/DJOyOemXMVLysF96YpmVgPJ34FOpP
# rR/WB54=
# SIG # End signature block
