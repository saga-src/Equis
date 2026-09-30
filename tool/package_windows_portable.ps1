[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DestinationPath,
    [string]$ReleaseDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build/windows/x64/runner/Release'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$releaseRoot = (Resolve-Path -LiteralPath $ReleaseDirectory).Path.TrimEnd('\', '/')
$releasePrefix = $releaseRoot + [IO.Path]::DirectorySeparatorChar
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath)
if ([IO.Path]::GetExtension($destination) -ne '.zip' -or
    $destination.StartsWith($releasePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Write the portable ZIP outside the release bundle.'
}
if ((Test-Path -LiteralPath $destination) -and -not $Force) {
    throw 'The destination already exists. Use -Force to replace this ZIP.'
}
foreach ($required in @('equis.exe', 'equis-update-helper.exe', 'app-trust.json', 'app-trust.sig')) {
    if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot $required) -PathType Leaf)) {
        throw "Missing release file: $required"
    }
}
# Include hidden files; the signed catalog will reject any missing/extra bytes.
$items = @(Get-Item -LiteralPath $releaseRoot) + @(Get-ChildItem -LiteralPath $releaseRoot -Recurse -Force)
if (@($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) {
    throw 'Portable bundles must not contain links or redirected directories.'
}
$files = @($items | Where-Object { -not $_.PSIsContainer } | Sort-Object FullName)
$stream = $null
$archive = $null
try {
    $mode = if ($Force) { [IO.FileMode]::Create } else { [IO.FileMode]::CreateNew }
    $stream = [IO.File]::Open($destination, $mode, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
    foreach ($file in $files) {
        # ZIP entry paths use '/', regardless of the host's path separator.
        $entryName = $file.FullName.Substring($releasePrefix.Length).Replace('\', '/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $file.FullName, $entryName, [IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
} finally {
    if ($null -ne $archive) { $archive.Dispose() }
    if ($null -ne $stream) { $stream.Dispose() }
}
Write-Output "Portable ZIP created with $($files.Count) files: $destination"
