param(
    [Parameter(Mandatory=$true)][string]$PreviousApk,
    [Parameter(Mandatory=$true)][string]$UpdateApk,
    [string]$AndroidSdk = "$PSScriptRoot/../.tooling/android-sdk"
)
$ErrorActionPreference = 'Stop'
$previous = (Resolve-Path -LiteralPath $PreviousApk).Path
$update = (Resolve-Path -LiteralPath $UpdateApk).Path
$buildTools = Get-ChildItem -LiteralPath "$AndroidSdk/build-tools" -Directory |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (!$buildTools) { throw 'Android build-tools are required.' }
$signer = Join-Path $buildTools.FullName 'apksigner.bat'
$aapt = Join-Path $buildTools.FullName 'aapt.exe'
function Get-ApkIdentity([string]$Apk) {
    $certificates = & $signer verify --print-certs $Apk
    if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
    $fingerprints = @($certificates | Select-String 'certificate SHA-256 digest:' | ForEach-Object { ($_.Line -split ': ')[-1].Trim() })
    if ($fingerprints.Count -ne 1) { throw 'Expected one APK signing certificate.' }
    $badging = & $aapt dump badging $Apk
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect APK manifest.' }
    $package = $badging | Select-String "^package: name='([^']+)' versionCode='([0-9]+)'"
    if (!$package) { throw 'Unable to read package identity.' }
    return @{ Certificate=$fingerprints[0]; Package=$package.Matches[0].Groups[1].Value; Version=[long]$package.Matches[0].Groups[2].Value }
}
$old = Get-ApkIdentity $previous
$new = Get-ApkIdentity $update
if ($old.Certificate -ne $new.Certificate) { throw 'Signing certificate mismatch. Do not uninstall the existing app.' }
if ($old.Package -ne $new.Package -or $new.Package -ne 'app.saga.equis') { throw 'Application ID mismatch.' }
if ($new.Version -le $old.Version) { throw 'The update must have a higher version code.' }
Write-Output "Verified update: $($new.Package), build $($old.Version) -> $($new.Version)"
Write-Output "Certificate SHA-256: $($new.Certificate)"
Get-FileHash -LiteralPath $update -Algorithm SHA256
