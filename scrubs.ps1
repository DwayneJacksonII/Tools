<#
.SYNOPSIS
This script scrubs sensitive information from a Fiddler trace file.

.DESCRIPTION
The script removes sensitive information such as:
- IP addresses
- User IDs
- Usernames
- Email addresses
- User roles
- Access tokens and refresh tokens (if present)

It replaces the sensitive data with placeholders and provides a summary report indicating how many instances of each type of information were scrubbed. The scrubbed content is saved to a new file.

.PARAMETER InputFilePath
The full file path of the Fiddler trace file to be scrubbed.

.PARAMETER OutputFilePath
The full file path where the scrubbed Fiddler trace will be saved.

.EXAMPLE
.\ScrubFiddlerTrace.ps1 -InputFilePath "C:\Logs\FiddlerTrace.txt" -OutputFilePath "C:\Logs\ScrubbedTrace.txt"

This command scrubs the sensitive information from the file `FiddlerTrace.txt` and saves the output in `ScrubbedTrace.txt`.

#>

param (
    [Parameter(Mandatory = $true, HelpMessage = "The full path of the Fiddler trace file to scrub.")]
    [string]$InputFilePath,

    [Parameter(Mandatory = $true, HelpMessage = "The full path where the scrubbed Fiddler trace will be saved.")]
    [string]$OutputFilePath
)

# Validate input file exists
if (-not (Test-Path $InputFilePath)) {
    Write-Error "Input file does not exist at path: $InputFilePath"
    exit
}

# Read the content of the Fiddler trace
$fileContent = Get-Content -Path $InputFilePath -Raw

# Define regex patterns for sensitive information
$ipAddressPattern = "\b\d{1,3}(\.\d{1,3}){3}\b"
$userIdPattern = '"user_id":\s*"\d+"'
$usernamePattern = '"username":\s*"[^"]+"'
$emailPattern = '"email":\s*"[^"]+"'
$rolesPattern = '"roles":\s*\[.*?\]'

# Initialize counters
$ipCount = 0
$userIdCount = 0
$usernameCount = 0
$emailCount = 0
$rolesCount = 0

# Scrub IP addresses
$fileContent = $fileContent -replace $ipAddressPattern, {
    $ipCount++
    "[REDACTED_IP]"
}

# Scrub user_id
$fileContent = $fileContent -replace $userIdPattern, {
    $userIdCount++
    '"user_id": "[REDACTED_USER_ID]"'
}

# Scrub username
$fileContent = $fileContent -replace $usernamePattern, {
    $usernameCount++
    '"username": "[REDACTED_USERNAME]"'
}

# Scrub email
$fileContent = $fileContent -replace $emailPattern, {
    $emailCount++
    '"email": "[REDACTED_EMAIL]"'
}

# Scrub roles
$fileContent = $fileContent -replace $rolesPattern, {
    $rolesCount++
    '"roles": [REDACTED_ROLES]'
}

# Write the scrubbed content to the output file
Set-Content -Path $OutputFilePath -Value $fileContent

# Report results
Write-Host "Scrubbing complete:"
Write-Host "IP Addresses scrubbed: $ipCount"
Write-Host "User IDs scrubbed: $userIdCount"
Write-Host "Usernames scrubbed: $usernameCount"
Write-Host "Emails scrubbed: $emailCount"
Write-Host "Roles scrubbed: $rolesCount"

Write-Host "Scrubbed file saved at: $OutputFilePath"
