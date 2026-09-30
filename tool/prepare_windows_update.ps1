[CmdletBinding()]
param(
  [string]$Dart = 'dart'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'windows_update_build_identity.ps1')
$release = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path -LiteralPath (Join-Path $release 'equis.exe'))) { throw 'Build Windows first.' }
Assert-ProductionWindowsUpdateBuild -ProjectRoot $root -Executable (Join-Path $release 'equis.exe')
if ([Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $release 'equis.exe')).ProductName -ne 'Equis') {
  throw 'Production preparation requires the production Windows ProductName.'
}
if (Test-Path -LiteralPath (Join-Path $release 'equis-update-broker.exe')) {
  throw 'Obsolete broker found. Rebuild the simplified Windows bundle.'
}
if (Test-Path -LiteralPath (Join-Path $release 'app-version.json')) {
  $existing = Get-Content -LiteralPath (Join-Path $release 'app-version.json') -Raw | ConvertFrom-Json
  if ($existing.updateTestMode -eq $true -or ($existing.applicationId -and $existing.applicationId -ne 'app.saga.equis')) {
    throw 'Isolated test bundles cannot be prepared as production releases.'
  }
}
& $Dart compile exe (Join-Path $PSScriptRoot 'update_helper.dart') -o (Join-Path $release 'equis-update-helper.exe')
if ($LASTEXITCODE -ne 0) { throw 'Update helper compilation failed.' }
$versionLine = Get-Content (Join-Path $root 'pubspec.yaml') | Where-Object { $_ -match '^version: ' }
if ($versionLine -notmatch '^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$') { throw 'Invalid version.' }
$versionJson = @{ version=$Matches[1]; build=[int]$Matches[2]; applicationId='app.saga.equis'; innoAppId='B9ECD233-7990-478B-A5F1-C30E4BCAA15E'; updateTestMode=$false } | ConvertTo-Json
[IO.File]::WriteAllText((Join-Path $release 'app-version.json'), $versionJson, [Text.UTF8Encoding]::new($false))
# package_windows_release.ps1 writes the inventory and signed trust catalog
# after optional Authenticode signing has finalized all executable bytes.
