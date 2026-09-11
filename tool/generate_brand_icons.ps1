param([string]$Source = "$PSScriptRoot/../assets/branding/source/logo.png")
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$brandRoot = [IO.Path]::GetFullPath("$PSScriptRoot/..")
$sourceImage = [Drawing.Image]::FromFile((Resolve-Path -LiteralPath $Source).Path)
function Render-BrandPng([int]$Size) {
    $bitmap = New-Object Drawing.Bitmap($Size, $Size)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $stream = New-Object IO.MemoryStream
    try {
        $graphics.Clear([Drawing.Color]::White)
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $scale = [Math]::Min($Size / $sourceImage.Width, $Size / $sourceImage.Height)
        $width = [int]($sourceImage.Width * $scale)
        $height = [int]($sourceImage.Height * $scale)
        $graphics.DrawImage($sourceImage, [int](($Size-$width)/2), [int](($Size-$height)/2), $width, $height)
        $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
        return ,$stream.ToArray()
    } finally { $stream.Dispose(); $graphics.Dispose(); $bitmap.Dispose() }
}
try {
    $densities = @{ mdpi=48; hdpi=72; xhdpi=96; xxhdpi=144; xxxhdpi=192 }
    foreach ($density in $densities.Keys) {
        $directory = "$brandRoot/android/app/src/main/res/mipmap-$density"
        [IO.Directory]::CreateDirectory($directory) | Out-Null
        [IO.File]::WriteAllBytes("$directory/ic_launcher.png", (Render-BrandPng $densities[$density]))
    }
    [IO.Directory]::CreateDirectory("$brandRoot/assets/branding") | Out-Null
    [IO.File]::WriteAllBytes("$brandRoot/assets/branding/logo.png", (Render-BrandPng 512))
    $sizes = @(16,32,48,64,128,256)
    $images = @($sizes | ForEach-Object { ,(Render-BrandPng $_) })
    $file = [IO.File]::Create("$brandRoot/windows/runner/resources/app_icon.ico")
    $writer = New-Object IO.BinaryWriter($file)
    try {
        $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Length)
        $offset = 6 + 16 * $sizes.Length
        for ($index = 0; $index -lt $sizes.Length; $index++) {
            $dimension = if ($sizes[$index] -eq 256) { 0 } else { $sizes[$index] }
            $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
            $writer.Write([byte]0); $writer.Write([byte]0)
            $writer.Write([uint16]1); $writer.Write([uint16]32)
            $writer.Write([uint32]$images[$index].Length); $writer.Write([uint32]$offset)
            $offset += $images[$index].Length
        }
        foreach ($bytes in $images) { $writer.Write([byte[]]$bytes) }
    } finally { $writer.Dispose(); $file.Dispose() }
} finally { $sourceImage.Dispose() }
Write-Output 'Generated Android, Windows and in-app logo assets.'
