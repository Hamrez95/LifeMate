[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string]$EncryptedBackupPath,
  [Parameter(Mandatory = $true)] [string]$AgeIdentityPath,
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[A-Za-z0-9_.-]+$')]
  [string]$TargetDatabaseService,
  [Parameter(Mandatory = $true)]
  [ValidateSet('RESTORE-LIFEMATE-DISPOSABLE')]
  [string]$Confirmation,
  [string]$AgePath = 'age',
  [string]$PgRestorePath = 'pg_restore',
  [string]$PsqlPath = 'psql'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
  foreach ($argument in $Arguments) { [void]$psi.ArgumentList.Add($argument) }
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $psi
  if (-not $process.Start()) { throw "Failed to start required process: $FilePath" }
  return $process
}

if ($Confirmation -ne 'RESTORE-LIFEMATE-DISPOSABLE') {
  throw 'Restore requires explicit disposable-target confirmation.'
}
if (-not (Test-Path -LiteralPath $EncryptedBackupPath -PathType Leaf)) {
  throw 'Encrypted backup artifact was not found.'
}
if (-not (Test-Path -LiteralPath $AgeIdentityPath -PathType Leaf)) {
  throw 'Local age recovery identity file was not found.'
}
if ($TargetDatabaseService -notmatch '(restore|disposable|test)') {
  throw 'Target PostgreSQL service name must clearly identify a restore/disposable/test target.'
}

$manifestPath = $EncryptedBackupPath -replace '\.dump\.age$', '.manifest.json'
if ($manifestPath -eq $EncryptedBackupPath -or -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw 'Matching backup manifest was not found.'
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.encryption -ne 'age_recipient' -or $manifest.archiveFormat -ne 'pg_dump_custom') {
  throw 'Backup manifest is not a supported encrypted PostgreSQL archive.'
}
$actualHash = (Get-FileHash -LiteralPath $EncryptedBackupPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne ([string]$manifest.ciphertextSha256).ToLowerInvariant()) {
  throw 'Encrypted backup checksum validation failed before restore.'
}

$age = $null
$restore = $null
try {
  $age = Start-RedirectedProcess -FilePath $AgePath -Arguments @(
    '--decrypt', '--identity', $AgeIdentityPath, $EncryptedBackupPath
  ) -RedirectOutput
  $restore = Start-RedirectedProcess -FilePath $PgRestorePath -Arguments @(
    "--dbname=service=$TargetDatabaseService",
    '--no-owner', '--no-acl', '--exit-on-error'
  ) -RedirectInput

  $ageErrorTask = $age.StandardError.ReadToEndAsync()
  $restoreErrorTask = $restore.StandardError.ReadToEndAsync()
  $copyTask = $age.StandardOutput.BaseStream.CopyToAsync($restore.StandardInput.BaseStream)
  $copyTask.GetAwaiter().GetResult()
  $restore.StandardInput.Close()

  $age.WaitForExit()
  $restore.WaitForExit()
  [void]$ageErrorTask.GetAwaiter().GetResult()
  [void]$restoreErrorTask.GetAwaiter().GetResult()
  if ($age.ExitCode -ne 0) {
    throw "age decryption failed with exit code $($age.ExitCode); private key and path diagnostics are intentionally redacted."
  }
  if ($restore.ExitCode -ne 0) {
    throw "pg_restore failed with exit code $($restore.ExitCode); connection and archive diagnostics are intentionally redacted."
  }
} finally {
  if ($age -and -not $age.HasExited) { try { $age.Kill($true) } catch {} }
  if ($restore -and -not $restore.HasExited) { try { $restore.Kill($true) } catch {} }
  if ($age) { $age.Dispose() }
  if ($restore) { $restore.Dispose() }
}

$verificationSql = @'
DO $$
DECLARE
  required_schema text;
  runtime_role_count integer;
  unsafe_runtime_role_count integer;
BEGIN
  FOREACH required_schema IN ARRAY ARRAY[
    'analytics','care','commerce','consent','core','ecosystem',
    'identity','integration','lifemate','public','security'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname=required_schema) THEN
      RAISE EXCEPTION 'required LifeMate schema missing after restore: %', required_schema;
    END IF;
  END LOOP;

  IF to_regclass('identity.accounts') IS NULL
     OR to_regclass('core.persons') IS NULL
     OR to_regclass('core.account_person_links') IS NULL
     OR to_regclass('lifemate.medications') IS NULL
     OR to_regclass('lifemate.health_observations') IS NULL THEN
    RAISE EXCEPTION 'critical identity/healthcare tables missing after restore';
  END IF;

  SELECT count(*) INTO runtime_role_count
  FROM pg_roles
  WHERE rolname IN ('lifemate_edge_runtime','lifemate_worker_runtime','lifemate_admin_runtime');
  IF runtime_role_count <> 3 THEN
    RAISE EXCEPTION 'restricted runtime roles must be provisioned before recovery verification';
  END IF;

  SELECT count(*) INTO unsafe_runtime_role_count
  FROM pg_roles
  WHERE rolname IN ('lifemate_edge_runtime','lifemate_worker_runtime','lifemate_admin_runtime')
    AND (rolsuper OR rolbypassrls);
  IF unsafe_runtime_role_count <> 0 THEN
    RAISE EXCEPTION 'restored runtime role regained elevated privileges';
  END IF;
END $$;
SELECT 'lifemate_restore_structure_ok';
'@

$verifyOutput = & $PsqlPath "--dbname=service=$TargetDatabaseService" '--set=ON_ERROR_STOP=1' '--tuples-only' '--no-align' "--command=$verificationSql" 2>&1
if ($LASTEXITCODE -ne 0 -or ($verifyOutput -join "`n") -notmatch 'lifemate_restore_structure_ok') {
  throw 'Post-restore structural/security verification failed.'
}

$result = [ordered]@{
  state = 'restored_and_verified'
  verifiedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
  ciphertextSha256 = $actualHash
  targetClass = 'disposable_non_production'
  plaintextArchivePersisted = $false
}
Write-Output ($result | ConvertTo-Json -Compress)
