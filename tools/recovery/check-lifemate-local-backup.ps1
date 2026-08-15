[CmdletBinding()]
param(
  [string]$OutputDirectory = $(
    if ($env:LOCALAPPDATA) {
      Join-Path $env:LOCALAPPDATA 'LifeMate\Backups'
    } else {
      Join-Path $HOME '.lifemate/backups'
    }
  ),
  [ValidateRange(1, 168)]
  [int]$MaximumAgeHours = 26
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$manifests = @(Get-ChildItem -LiteralPath $OutputDirectory -File -Filter 'lifemate-*.manifest.json' -ErrorAction Stop |
  Sort-Object LastWriteTimeUtc -Descending)
if ($manifests.Count -eq 0) {
  throw 'No LifeMate backup manifest was found.'
}

$manifest = Get-Content -LiteralPath $manifests[0].FullName -Raw | ConvertFrom-Json
if ($manifest.formatVersion -ne 1 -or $manifest.encryption -ne 'age_recipient') {
  throw 'Latest backup manifest has an unsupported format.'
}

$createdAt = [DateTimeOffset]::Parse([string]$manifest.createdAtUtc)
$age = [DateTimeOffset]::UtcNow - $createdAt
if ($age.TotalHours -gt $MaximumAgeHours) {
  throw "Latest encrypted backup is stale: $([Math]::Round($age.TotalHours, 2)) hours old."
}

$artifactPath = Join-Path $OutputDirectory ([string]$manifest.artifact)
if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
  throw 'Latest encrypted backup artifact is missing.'
}

$actualHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
$expectedHash = ([string]$manifest.ciphertextSha256).ToLowerInvariant()
if ($actualHash -ne $expectedHash) {
  throw 'Latest encrypted backup ciphertext checksum does not match its manifest.'
}

$result = [ordered]@{
  state = 'healthy'
  checkedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
  createdAtUtc = $createdAt.ToString('o')
  ageHours = [Math]::Round($age.TotalHours, 2)
  artifact = [string]$manifest.artifact
  ciphertextSha256 = $actualHash
}
Write-Output ($result | ConvertTo-Json -Compress)
