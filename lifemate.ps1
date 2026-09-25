$tool = Join-Path $PSScriptRoot 'tools\lifemate.ps1'
if (-not (Test-Path -LiteralPath $tool)) {
  throw "LifeMate tool was not found: $tool"
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
  $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
  if ($null -eq $pwsh) {
    throw 'LifeMate requires PowerShell 7. Install PowerShell 7, then run .\\lifemate.ps1 again.'
  }
  & $pwsh.Source -NoProfile -File $tool @args
  exit $LASTEXITCODE
}

& $tool @args
exit $LASTEXITCODE
