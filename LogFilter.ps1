<#
.SYNOPSIS
    Filters Application and System event logs on Windows Server 2022
    for IIS rewrite module and code integrity issues.
#>

param(
    [int]$Hours = 24
)

$startTime = (Get-Date).AddHours(-$Hours)

# ── Application Log ──────────────────────────────────────────────────
$appSources = @('IIS-W3SVC-WP', 'Application Error', 'SideBySide')

$appKeywords = @(
    'rewrite.dll',
    'module failed to load',
    'access denied',
    'not a valid Win32 application'
)

$keywordPattern = ($appKeywords | ForEach-Object { [regex]::Escape($_) }) -join '|'

Write-Host "`n===== APPLICATION LOG =====" -ForegroundColor Cyan

# Filter by source
$appEvents = Get-WinEvent -FilterHashtable @{
    LogName   = 'Application'
    StartTime = $startTime
} -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -in $appSources }

# Filter by keywords in message
$appKeywordEvents = Get-WinEvent -FilterHashtable @{
    LogName   = 'Application'
    StartTime = $startTime
} -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match $keywordPattern }

$allAppEvents = @($appEvents) + @($appKeywordEvents) |
    Sort-Object -Property RecordId -Unique |
    Sort-Object -Property TimeCreated -Descending

if ($allAppEvents.Count -eq 0) {
    Write-Host "No matching Application log entries found in the last $Hours hour(s)." -ForegroundColor Green
} else {
    Write-Host "Found $($allAppEvents.Count) matching entries:" -ForegroundColor Yellow
    $allAppEvents | Format-Table -AutoSize -Property TimeCreated, ProviderName, Id, LevelDisplayName, @{
        Name = 'Message'; Expression = { $_.Message.Substring(0, [Math]::Min(120, $_.Message.Length)) }
    }
}

# ── System Log ───────────────────────────────────────────────────────
$sysSources = @('Microsoft-Windows-CodeIntegrity', 'AppLocker', 'Microsoft-Windows-AppLocker',
                'Microsoft-Windows-WDAC', 'Microsoft-Windows-Windows Defender Application Control')

Write-Host "`n===== SYSTEM LOG (Code Integrity / AppLocker / WDAC) =====" -ForegroundColor Cyan

$sysEvents = Get-WinEvent -FilterHashtable @{
    LogName   = 'System'
    StartTime = $startTime
} -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -in $sysSources }

if ($sysEvents.Count -eq 0) {
    Write-Host "No Code Integrity / AppLocker / WDAC entries found in the last $Hours hour(s)." -ForegroundColor Green
} else {
    Write-Host "Found $($sysEvents.Count) matching entries:" -ForegroundColor Yellow
    $sysEvents | Format-Table -AutoSize -Property TimeCreated, ProviderName, Id, LevelDisplayName, @{
        Name = 'Message'; Expression = { $_.Message.Substring(0, [Math]::Min(120, $_.Message.Length)) }
    }
}

# ── WDAC / Code Integrity referencing rewrite.dll (the blocker) ─────
Write-Host "`n===== WDAC / CODE INTEGRITY ENTRIES REFERENCING rewrite.dll =====" -ForegroundColor Magenta

$wdacRewrite = @($sysEvents) | Where-Object { $_.Message -match 'rewrite\.dll' }

if ($wdacRewrite.Count -eq 0) {
    Write-Host "No Code Integrity / WDAC entries referencing rewrite.dll found. Likely NOT blocked by WDAC." -ForegroundColor Green
} else {
    Write-Host "*** BLOCKER DETECTED *** $($wdacRewrite.Count) entries reference rewrite.dll:" -ForegroundColor Red
    $wdacRewrite | Format-List TimeCreated, ProviderName, Id, LevelDisplayName, Message
}

Write-Host "`nScan complete. Searched the last $Hours hour(s). Run with -Hours 72 to widen the window." -ForegroundColor DarkGray
