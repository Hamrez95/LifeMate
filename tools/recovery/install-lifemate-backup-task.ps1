[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[A-Za-z0-9_.-]+$')]
  [string]$DatabaseService,
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^age1[0-9a-z]+$')]
  [string]$AgeRecipient,
  [string]$OutputDirectory = $(Join-Path $env:LOCALAPPDATA 'LifeMate\Backups'),
  [ValidatePattern('^([01]\d|2[0-3]):[0-5]\d$')]
  [string]$DailyAt = '03:00',
  [ValidateRange(1, 3650)]
  [int]$RetentionDays = 14,
  [string]$TaskPrefix = 'LifeMate'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
  throw 'This installer configures Windows Task Scheduler and must run on Windows PowerShell 7+.'
}
if (-not $env:LOCALAPPDATA) {
  throw 'LOCALAPPDATA is required for the default private workstation backup location.'
}

$pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
$backupScript = (Resolve-Path (Join-Path $PSScriptRoot 'lifemate-local-backup.ps1')).Path
$checkScript = (Resolve-Path (Join-Path $PSScriptRoot 'check-lifemate-local-backup.ps1')).Path

foreach ($command in @('pg_dump', 'age')) {
  if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
    throw "$command must be installed and available on PATH before scheduling LifeMate backups."
  }
}

function Quote-TaskValue([string]$Value) {
  return '"' + $Value.Replace('"', '\"') + '"'
}

$backupArguments = @(
  '-NoProfile', '-NonInteractive', '-File', (Quote-TaskValue $backupScript),
  '-DatabaseService', (Quote-TaskValue $DatabaseService),
  '-AgeRecipient', (Quote-TaskValue $AgeRecipient),
  '-OutputDirectory', (Quote-TaskValue $OutputDirectory),
  '-RetentionDays', [string]$RetentionDays
) -join ' '

$checkArguments = @(
  '-NoProfile', '-NonInteractive', '-File', (Quote-TaskValue $checkScript),
  '-OutputDirectory', (Quote-TaskValue $OutputDirectory),
  '-MaximumAgeHours', '26'
) -join ' '

$today = Get-Date
$parts = $DailyAt.Split(':')
$backupTime = Get-Date -Year $today.Year -Month $today.Month -Day $today.Day -Hour ([int]$parts[0]) -Minute ([int]$parts[1]) -Second 0
$checkTime = $backupTime.AddHours(3)

$principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)

$backupTaskName = "$TaskPrefix Encrypted PostgreSQL Backup"
$backupAction = New-ScheduledTaskAction -Execute $pwsh -Argument $backupArguments
$backupTrigger = New-ScheduledTaskTrigger -Daily -At $backupTime
$backupTask = New-ScheduledTask -Action $backupAction -Trigger $backupTrigger -Principal $principal -Settings $settings -Description 'Creates a provider-independent encrypted LifeMate PostgreSQL backup on this workstation. Database credentials remain in PostgreSQL client configuration, not task arguments.'
Register-ScheduledTask -TaskName $backupTaskName -InputObject $backupTask -Force | Out-Null

$checkTaskName = "$TaskPrefix Backup Freshness Check"
$checkAction = New-ScheduledTaskAction -Execute $pwsh -Argument $checkArguments
$checkTrigger = New-ScheduledTaskTrigger -Daily -At $checkTime
$checkTask = New-ScheduledTask -Action $checkAction -Trigger $checkTrigger -Principal $principal -Settings $settings -Description 'Fails when the latest LifeMate encrypted PostgreSQL backup is stale, missing, or fails ciphertext integrity verification.'
Register-ScheduledTask -TaskName $checkTaskName -InputObject $checkTask -Force | Out-Null

$result = [ordered]@{
  backupTask = $backupTaskName
  freshnessTask = $checkTaskName
  dailyAt = $backupTime.ToString('HH:mm')
  freshnessAt = $checkTime.ToString('HH:mm')
  outputDirectory = $OutputDirectory
  secretsInTaskArguments = $false
}
Write-Output ($result | ConvertTo-Json -Compress)
