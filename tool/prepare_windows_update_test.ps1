[CmdletBinding()]
param(
  [string]$Version = '1.2.1',
  [int]$Build = 13,
  [string]$FixtureRoot = '',
  [string]$Flutter = '',
  [string]$Dart = '',
  [string]$InnoCompiler = ''
)

# This command builds only a disposable fixture; it never installs or publishes.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (!$Flutter) { $Flutter = Join-Path $projectRoot '.tooling/flutter/bin/flutter.bat' }
if (!$Dart) { $Dart = Join-Path $projectRoot '.tooling/flutter/bin/dart.bat' }
if (!$InnoCompiler) { $InnoCompiler = Join-Path $env:LOCALAPPDATA 'Programs/Inno Setup 6/ISCC.exe' }
if (!(Test-Path -LiteralPath $InnoCompiler)) { $InnoCompiler = 'C:/Program Files (x86)/Inno Setup 6/ISCC.exe' }
foreach ($executable in @($Flutter, $Dart, $InnoCompiler)) {
  if (!(Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'The fixture build toolchain is unavailable.' }
}
if ($Version -notmatch '^\d+\.\d+\.\d+$' -or $Build -lt 1) { throw 'Invalid fixture version.' }
$fixtureParent = [IO.Path]::GetFullPath((Join-Path $projectRoot '.tooling/windows-update-test'))
if (!$FixtureRoot) { $FixtureRoot = Join-Path $fixtureParent ([guid]::NewGuid().ToString('N')) }
$fixtureRoot = [IO.Path]::GetFullPath($FixtureRoot)
if ([IO.Path]::GetDirectoryName($fixtureRoot) -ne $fixtureParent -or
    [IO.Path]::GetFileName($fixtureRoot) -notmatch '^[a-f0-9]{32}$') {
  throw 'Fixture roots must be GUID directories inside .tooling/windows-update-test.'
}
function Assert-FixturePath([string]$Path) {
  $absolute = [IO.Path]::GetFullPath($Path)
  if (!$absolute.StartsWith($fixtureRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Fixture output is outside its disposable root.'
  }
  $current = $absolute
  while ($current) {
    if (Test-Path -LiteralPath $current) {
      $item = Get-Item -LiteralPath $current -Force
      if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Fixture paths must not contain reparse points.' }
    }
    $parent = [IO.Path]::GetDirectoryName($current)
    if ($parent -eq $current) { break }
    $current = $parent
  }
  return $absolute
}
$source = Assert-FixturePath (Join-Path $fixtureRoot 'source')
$artifacts = Assert-FixturePath (Join-Path $fixtureRoot "artifacts/$Version+$Build")
$profile = Assert-FixturePath (Join-Path $fixtureRoot 'profile')
$install = Assert-FixturePath (Join-Path $fixtureRoot 'install/Equis Update Test')
$keys = Assert-FixturePath (Join-Path $fixtureRoot 'keys')
$cache = Assert-FixturePath (Join-Path $fixtureRoot 'pub-cache')
New-Item -ItemType Directory -Path $source,$artifacts,$profile,$keys,$cache -Force | Out-Null
# /XJ avoids crossing repository junctions; signing secrets are excluded.
& robocopy $projectRoot $source /E /XJ /NFL /NDL /NJH /NJS /NP /XD .git .tooling .dart_tool build dist .update-signing .codex .claude
if ($LASTEXITCODE -ge 8) { throw 'Disposable source copy failed.' }
$saved = @{}
foreach ($name in @('UPDATE_SIGNING_SEED','EQUIS_UPDATE_TEST_ROOT','EQUIS_UPDATE_TEST_PUBLIC_KEY','PUB_CACHE')) {
  $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
  $env:UPDATE_SIGNING_SEED = $null
  $env:EQUIS_UPDATE_TEST_ROOT = $fixtureRoot
  $env:PUB_CACHE = $cache
  $fixturePubspec = Join-Path $source 'pubspec.yaml'
  $pubspec = Get-Content -LiteralPath $fixturePubspec -Raw
  if ($pubspec -notmatch '(?m)^version: \d+\.\d+\.\d+\+\d+\r?$') { throw 'Fixture pubspec version is invalid.' }
  $pubspec = [regex]::Replace($pubspec, '(?m)^version: \d+\.\d+\.\d+\+\d+\r?$', "version: $Version+$Build")
  [IO.File]::WriteAllText($fixturePubspec, $pubspec, [Text.UTF8Encoding]::new($false))
  # path_provider, SharedPreferences and Windows DPAPI storage use ProductName.
  # Keep it stable between fixture versions and separate from production.
  $fixtureProductName = 'Equis Update Test ' + [IO.Path]::GetFileName($fixtureRoot)
  $runnerResource = Join-Path $source 'windows/runner/Runner.rc'
  $resourceText = Get-Content -LiteralPath $runnerResource -Raw
  if ($resourceText -notmatch 'VALUE "ProductName", "Equis"') { throw 'Unexpected fixture runner metadata.' }
  $resourceText = $resourceText.Replace('VALUE "ProductName", "Equis"', ('VALUE "ProductName", "' + $fixtureProductName + '"'))
  [IO.File]::WriteAllText($runnerResource, $resourceText, [Text.UTF8Encoding]::new($false))
  Push-Location -LiteralPath $source
  try {
    & $Flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Fixture dependencies failed.' }
    if (!(Test-Path -LiteralPath (Join-Path $keys 'ed25519.seed'))) {
      & $Dart run tool/update_signing.dart init-test $keys
      if ($LASTEXITCODE -ne 0) { throw 'Fixture key generation failed.' }
    }
    $env:EQUIS_UPDATE_TEST_PUBLIC_KEY = (Get-Content -LiteralPath (Join-Path $keys 'public-key.txt') -Raw).Trim()
    $definitions = @(
      'EQUIS_UPDATE_TEST_MODE=true',
      "EQUIS_UPDATE_TEST_PUBLIC_KEY=$env:EQUIS_UPDATE_TEST_PUBLIC_KEY",
      "EQUIS_UPDATE_TEST_ROOT=$profile",
      'EQUIS_WINDOWS_INSTALLED_UPDATE_ENABLED=true',
      "EQUIS_VERSION=$Version", "EQUIS_BUILD=$Build"
    )
    $flutterDefinitions = @($definitions | ForEach-Object { '--dart-define=' + $_ })
    & $Flutter build windows --release @flutterDefinitions
    if ($LASTEXITCODE -ne 0) { throw 'Fixture Windows build failed.' }
    $release = Assert-FixturePath (Join-Path $source 'build/windows/x64/runner/Release')
    $dartDefinitions = @($definitions | ForEach-Object { '-D' + $_ })
    & $Dart compile exe @dartDefinitions tool/update_helper.dart -o (Join-Path $release 'equis-update-helper.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Fixture helper compilation failed.' }
    $metadata = @{ version=$Version; build=$Build; applicationId='app.saga.equis.update-test'; innoAppId='8B18F7D4-35F6-4DDE-ABFD-E76991B831D2'; updateTestMode=$true } | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $release 'app-version.json'), $metadata, [Text.UTF8Encoding]::new($false))
    $env:UPDATE_SIGNING_SEED = (Get-Content -LiteralPath (Join-Path $keys 'ed25519.seed') -Raw).Trim()
    & $Dart run tool/update_signing.dart sign-catalog-test $release $Version $Build
    if ($LASTEXITCODE -ne 0) { throw 'Fixture catalog signing failed.' }
    Copy-Item -LiteralPath (Join-Path $release 'app-trust.json'),(Join-Path $release 'app-trust.sig') -Destination $artifacts
    & $InnoCompiler '/DUpdateTestMode' '/DUpdateInnoAppId=8B18F7D4-35F6-4DDE-ABFD-E76991B831D2' "/DUpdateReleaseRoot=$release" "/DUpdateOutputDir=$artifacts" "/DUpdateInstallRoot=$install" "/DAppVersion=$Version" "/DAppBuild=$Build" installer/equis.iss
    if ($LASTEXITCODE -ne 0) { throw 'Fixture installer compilation failed.' }
    & (Join-Path $PSScriptRoot 'package_windows_portable.ps1') -ReleaseDirectory $release -DestinationPath (Join-Path $artifacts "Equis-Windows-$Version-portable.zip") -Force
    & $Dart run tool/update_signing.dart sign-test $artifacts $Version $Build
    if ($LASTEXITCODE -ne 0) { throw 'Fixture manifest signing failed.' }
    & $Dart run tool/verify_update_release.dart --test $artifacts
    if ($LASTEXITCODE -ne 0) { throw 'Fixture artifact verification failed.' }
    # Stage only the verified local installed-update payload. Fixture apps
    # restore this cache instead of consulting the production release feed.
    $updates = Assert-FixturePath (Join-Path $profile 'updates')
    New-Item -ItemType Directory -Path $updates -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $artifacts 'update-manifest.json') -Destination (Join-Path $updates 'manifest.json')
    Copy-Item -LiteralPath (Join-Path $artifacts 'update-manifest.sig') -Destination (Join-Path $updates 'manifest.sig')
    Copy-Item -LiteralPath (Join-Path $artifacts "Equis-Windows-$Version-setup.exe") -Destination $updates
    $description = @{ applicationId='app.saga.equis.update-test'; innoAppId='8B18F7D4-35F6-4DDE-ABFD-E76991B831D2'; profile=$profile; nativeProductName=$fixtureProductName; installRoot=$install; artifacts=$artifacts; publicKey=$env:EQUIS_UPDATE_TEST_PUBLIC_KEY } | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'fixture.json'), $description, [Text.UTF8Encoding]::new($false))
  } finally { Pop-Location }
} finally {
  foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
}
Write-Output $fixtureRoot
