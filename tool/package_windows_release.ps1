[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Version = "1.0.0",
    [int]$Build = 6,

    [Parameter(Mandatory = $false)]
    [string]$CertificateThumbprint = $env:EQUIS_WINDOWS_CERTIFICATE_SHA1,

    [Parameter(Mandatory = $false)]
    [string]$TimestampUrl = $env:EQUIS_WINDOWS_TIMESTAMP_URL,

    [switch]$Unsigned
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
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

if ($Unsigned) {
    & $innoCompiler "/DAppVersion=$Version" "/DAppBuild=$Build" $installerScript
    exit $LASTEXITCODE
}

if ([string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
    throw "A production code-signing certificate thumbprint is required. Use -Unsigned only for local packaging tests."
}
if ([string]::IsNullOrWhiteSpace($TimestampUrl)) {
    throw "A trusted RFC 3161 timestamp URL is required."
}

$signTool = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1
if ($null -eq $signTool) {
    throw "signtool.exe was not found in the Windows 10 SDK."
}

$signableFiles = Get-ChildItem -LiteralPath $releaseRoot -Recurse -File |
    Where-Object { $_.Extension -in ".exe", ".dll" }
foreach ($file in $signableFiles) {
    & $signTool.FullName sign /sha1 $CertificateThumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 $file.FullName
    if ($LASTEXITCODE -ne 0) { throw "Signing failed for $($file.FullName)." }
}

$signCommand = '"' + $signTool.FullName + '" sign /sha1 ' + $CertificateThumbprint +
    ' /fd SHA256 /tr ' + $TimestampUrl + ' /td SHA256 $f'
& $innoCompiler "/DAppVersion=$Version" "/DAppBuild=$Build" "/DReleaseSigned" "/Srelease=$signCommand" $installerScript
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$installer = Join-Path $projectRoot "dist\Equis-Windows-$Version-setup.exe"
& $signTool.FullName verify /pa /all $installer
exit $LASTEXITCODE
