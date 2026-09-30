[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Version = "1.2.1",
    [int]$Build = 13,

    [Parameter(Mandatory = $false)]
    [string]$CertificateThumbprint = $env:EQUIS_WINDOWS_CERTIFICATE_SHA1,

    [Parameter(Mandatory = $false)]
    [string]$TimestampUrl = $env:EQUIS_WINDOWS_TIMESTAMP_URL,

    [string]$Dart = 'dart',

    [switch]$Unsigned
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'windows_update_build_identity.ps1')
$releaseRoot = Join-Path $projectRoot "build\windows\x64\runner\Release"
$installerScript = Join-Path $projectRoot "installer\equis.iss"
$innoCompiler = Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"

if (-not (Test-Path -LiteralPath $innoCompiler)) {
    $innoCompiler = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
}
if (-not (Test-Path -LiteralPath $innoCompiler)) {
    throw "Inno Setup 6 was not found. Install JRSoftware.InnoSetup first."
}
if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot "equis.exe"))) {
    throw "The Windows release bundle does not exist. Run flutter build windows --release first."
}
$metadata = Get-Content -LiteralPath (Join-Path $releaseRoot 'app-version.json') -Raw | ConvertFrom-Json
Assert-ProductionWindowsUpdateBuild -ProjectRoot $projectRoot -Executable (Join-Path $releaseRoot 'equis.exe')
if ([Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $releaseRoot 'equis.exe')).ProductName -ne 'Equis') {
    throw 'Fixture Windows binaries cannot be packaged as production releases.'
}
if ($metadata.updateTestMode -ne $false -or
    $metadata.applicationId -ne 'app.saga.equis' -or
    $metadata.innoAppId -ne 'B9ECD233-7990-478B-A5F1-C30E4BCAA15E' -or
    $metadata.version -ne $Version -or $metadata.build -ne $Build) {
    throw 'Production packaging requires matching production bundle identity and version.'
}
if (Test-Path -LiteralPath (Join-Path $releaseRoot 'equis-update-broker.exe')) {
    throw 'The obsolete update broker must not be packaged.'
}

if (-not $Unsigned) {
    if ([string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
        throw "A production code-signing certificate thumbprint is required. Use -Unsigned only for local packaging tests."
    }
    if ([string]::IsNullOrWhiteSpace($TimestampUrl)) {
        throw "A trusted RFC 3161 timestamp URL is required."
    }
    $signTool = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($null -eq $signTool) { throw "signtool.exe was not found in the Windows 10 SDK." }
    $signableFiles = Get-ChildItem -LiteralPath $releaseRoot -Recurse -File |
        Where-Object { $_.Extension -in ".exe", ".dll" }
    foreach ($file in $signableFiles) {
        & $signTool.FullName sign /sha1 $CertificateThumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 $file.FullName
        if ($LASTEXITCODE -ne 0) { throw "Signing failed for $($file.FullName)." }
    }
}

# Sign the format 2 catalog after all executable bytes are final.
if ([string]::IsNullOrWhiteSpace($env:UPDATE_SIGNING_SEED)) {
    throw 'UPDATE_SIGNING_SEED is required to sign the Windows trust catalog.'
}
Push-Location -LiteralPath $projectRoot
try {
    & $Dart run tool/update_signing.dart sign-catalog $releaseRoot $Version $Build
    if ($LASTEXITCODE -ne 0) { throw 'Windows trust catalog signing failed.' }
} finally {
    Pop-Location
}
$distRoot = Join-Path $projectRoot 'dist'
New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $releaseRoot 'app-trust.json') `
    -Destination (Join-Path $distRoot 'app-trust.json') -Force
Copy-Item -LiteralPath (Join-Path $releaseRoot 'app-trust.sig') `
    -Destination (Join-Path $distRoot 'app-trust.sig') -Force
if ($Unsigned) {
    & $innoCompiler "/DAppVersion=$Version" "/DAppBuild=$Build" $installerScript
    exit $LASTEXITCODE
}

$signCommand = '"' + $signTool.FullName + '" sign /sha1 ' + $CertificateThumbprint +
    ' /fd SHA256 /tr ' + $TimestampUrl + ' /td SHA256 $f'
& $innoCompiler "/DAppVersion=$Version" "/DAppBuild=$Build" "/DReleaseSigned" "/Srelease=$signCommand" $installerScript
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$installer = Join-Path $projectRoot "dist\Equis-Windows-$Version-setup.exe"
& $signTool.FullName verify /pa /all $installer
exit $LASTEXITCODE
