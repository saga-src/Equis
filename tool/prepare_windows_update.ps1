[CmdletBinding()]
param([string]$Dart = 'dart')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$release = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path -LiteralPath (Join-Path $release 'equis.exe'))) { throw 'Build Windows first.' }
& $Dart compile exe (Join-Path $PSScriptRoot 'update_helper.dart') -o (Join-Path $release 'equis-update-helper.exe')
if ($LASTEXITCODE -ne 0) { throw 'Update helper compilation failed.' }
$prefix = $release.TrimEnd('\') + '\'
$versionLine = Get-Content (Join-Path $root 'pubspec.yaml') | Where-Object { $_ -match '^version: ' }
if ($versionLine -notmatch '^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$') { throw 'Invalid version.' }
$versionJson = @{ version=$Matches[1]; build=[int]$Matches[2] } | ConvertTo-Json
[IO.File]::WriteAllText((Join-Path $release 'app-version.json'), $versionJson, [Text.UTF8Encoding]::new($false))
$files = @(Get-ChildItem -LiteralPath $release -File -Recurse |
    Where-Object Name -ne 'app-files.json' |
    ForEach-Object { $_.FullName.Substring($prefix.Length).Replace('\', '/') } |
    Sort-Object)
$json = ConvertTo-Json -InputObject $files
[IO.File]::WriteAllText((Join-Path $release 'app-files.json'), $json, [Text.UTF8Encoding]::new($false))
