[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[A-Za-z0-9_.-]+$')]
  [string]$DatabaseService,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^age1[0-9a-z]+$')]
  [string]$AgeRecipient,

  [string]$OutputDirectory = $(
    if ($env:LOCALAPPDATA) {
      Join-Path $env:LOCALAPPDATA 'LifeMate\Backups'
    } else {
      Join-Path $HOME '.lifemate/backups'
    }
  ),

  [string]$PolicyPath = $(
    Join-Path $PSScriptRoot '..\..\config\recovery\lifemate-postgres-backup.json'
  ),

  [ValidateRange(1, 3650)]
  [int]$RetentionDays = 0,

  [string]$PgDumpPath = 'pg_dump',
  [string]$AgePath = 'age'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-RedactedStatus {
  param(
    [Parameter(Mandatory = $true)] [string]$Path,
    [Parameter(Mandatory = $true)] [hashtable]$Status
  )
  $Status | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

function Start-RedirectedProcess {
  param(
    [Parameter(Mandatory = $true)] [string]$FilePath,
    [Parameter(Mandatory = $true)] [string[]]$Arguments,
    [switch]$RedirectInput,
    [switch]$RedirectOutput
  )

  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $FilePath
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardError = $true
  $psi.RedirectStandardInput = $RedirectInput.IsPresent
  $psi.RedirectStandardOutput = $RedirectOutput.IsPresent
  foreach ($argument in $Arguments) {
    [void]$psi.ArgumentList.Add($argument)
  }

  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $psi
  if (-not $process.Start()) {
    throw "Failed to start required process: $FilePath"
  }
  return $process
}

if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
  throw 'Portable backup policy file was not found.'
}

$policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
if ($policy.databaseEngine -ne 'postgresql' -or $policy.archiveFormat -ne 'pg_dump_custom') {
  throw 'Unsupported backup policy format.'
}
if ($policy.encryption -ne 'age_recipient') {
  throw 'The backup policy must require recipient-based age encryption.'
}

$schemas = @($policy.schemas | ForEach-Object { [string]$_ })
if ($schemas.Count -eq 0) {
  throw 'At least one LifeMate-owned PostgreSQL schema must be configured.'
}
foreach ($schema in $schemas) {
  if ($schema -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
    throw 'Backup policy contains an invalid schema identifier.'
  }
}

if ($RetentionDays -eq 0) {
  $RetentionDays = [int]$policy.defaultRetentionDays
}
if ($RetentionDays -lt 1) {
  throw 'RetentionDays must resolve to a positive number.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$statusPath = Join-Path $OutputDirectory 'last-status.json'
$timestamp = [DateTimeOffset]::UtcNow
$stamp = $timestamp.ToString('yyyyMMddTHHmmssZ')
$artifactName = "lifemate-$stamp.dump.age"
$manifestName = "lifemate-$stamp.manifest.json"
$artifactPath = Join-Path $OutputDirectory $artifactName
$temporaryArtifactPath = "$artifactPath.part"
$manifestPath = Join-Path $OutputDirectory $manifestName

if (Test-Path -LiteralPath $temporaryArtifactPath) {
  Remove-Item -LiteralPath $temporaryArtifactPath -Force
}

$pgVersion = (& $PgDumpPath --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($pgVersion)) {
  throw 'pg_dump is unavailable or could not report its version.'
}

$pgArgs = [System.Collections.Generic.List[string]]::new()
$pgArgs.Add('--format=custom')
$pgArgs.Add('--no-owner')
$pgArgs.Add('--no-acl')
$pgArgs.Add('--verbose')
$pgArgs.Add('--role=lifemate_backup_reader')
$pgArgs.Add("--dbname=service=$DatabaseService")
foreach ($schema in $schemas) {
  $pgArgs.Add("--schema=$schema")
}

$ageArgs = @(
  '--recipient', $AgeRecipient,
  '--output', $temporaryArtifactPath,
  '-'
)

$pg = $null
$age = $null
try {
  $pg = Start-RedirectedProcess -FilePath $PgDumpPath -Arguments $pgArgs.ToArray() -RedirectOutput
  $age = Start-RedirectedProcess -FilePath $AgePath -Arguments $ageArgs -RedirectInput

  $pgErrorTask = $pg.StandardError.ReadToEndAsync()
  $ageErrorTask = $age.StandardError.ReadToEndAsync()
  $copyTask = $pg.StandardOutput.BaseStream.CopyToAsync($age.StandardInput.BaseStream)

  $copyTask.GetAwaiter().GetResult()
  $age.StandardInput.BaseStream.Flush()
  $age.StandardInput.Close()

  $pg.WaitForExit()
  $age.WaitForExit()
  [void]$pgErrorTask.GetAwaiter().GetResult()
  [void]$ageErrorTask.GetAwaiter().GetResult()

  if ($pg.ExitCode -ne 0) {
    throw "pg_dump failed with exit code $($pg.ExitCode); connection details are intentionally redacted."
  }
  if ($age.ExitCode -ne 0) {
    throw "age encryption failed with exit code $($age.ExitCode); diagnostic paths are intentionally redacted."
  }
  if (-not (Test-Path -LiteralPath $temporaryArtifactPath -PathType Leaf)) {
    throw 'Encrypted backup artifact was not created.'
  }

  $temporaryInfo = Get-Item -LiteralPath $temporaryArtifactPath
  if ($temporaryInfo.Length -le 0) {
    throw 'Encrypted backup artifact is empty.'
  }

  Move-Item -LiteralPath $temporaryArtifactPath -Destination $artifactPath
  $artifactInfo = Get-Item -LiteralPath $artifactPath
  $sha256 = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $recipientSha256 = [Convert]::ToHexString(
    [System.Security.Cryptography.SHA256]::HashData(
      [System.Text.Encoding]::UTF8.GetBytes($AgeRecipient)
    )
  ).ToLowerInvariant()

  $manifest = [ordered]@{
    formatVersion = 1
    createdAtUtc = $timestamp.ToString('o')
    artifact = $artifactName
    ciphertextSha256 = $sha256
    ciphertextBytes = $artifactInfo.Length
    archiveFormat = 'pg_dump_custom'
    encryption = 'age_recipient'
    recipientSha256 = $recipientSha256
    databaseEngine = 'postgresql'
    schemas = $schemas
    pgDumpVersion = $pgVersion
    retentionDays = $RetentionDays
  }
  $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM

  Write-RedactedStatus -Path $statusPath -Status @{
    state = 'success'
    completedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    artifact = $artifactName
    manifest = $manifestName
    ciphertextSha256 = $sha256
  }

  $cutoff = [DateTime]::UtcNow.AddDays(-$RetentionDays)
  Get-ChildItem -LiteralPath $OutputDirectory -File -Filter 'lifemate-*.dump.age' |
    Where-Object { $_.LastWriteTimeUtc -lt $cutoff } |
    ForEach-Object {
      $oldArtifact = $_
      $oldManifest = Join-Path $OutputDirectory ($oldArtifact.Name -replace '\.dump\.age$', '.manifest.json')
      Remove-Item -LiteralPath $oldArtifact.FullName -Force
      if (Test-Path -LiteralPath $oldManifest -PathType Leaf) {
        Remove-Item -LiteralPath $oldManifest -Force
      }
    }

  Write-Output ($manifest | ConvertTo-Json -Depth 5 -Compress)
} catch {
  if ($pg -and -not $pg.HasExited) { try { $pg.Kill($true) } catch {} }
  if ($age -and -not $age.HasExited) { try { $age.Kill($true) } catch {} }
  if (Test-Path -LiteralPath $temporaryArtifactPath) {
    Remove-Item -LiteralPath $temporaryArtifactPath -Force -ErrorAction SilentlyContinue
  }
  Write-RedactedStatus -Path $statusPath -Status @{
    state = 'failure'
    completedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    errorType = $_.Exception.GetType().Name
  }
  throw
} finally {
  if ($pg) { $pg.Dispose() }
  if ($age) { $age.Dispose() }
}
