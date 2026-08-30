param(
    [string]$Source = "release/store/feature_graphic_source.png",
    [string]$Output = "release/store/feature_graphic.png"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$sourcePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\$Source"))
$outputPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\$Output"))
$fontPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\assets\fonts\Oswald-SemiBold.ttf"))
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($outputPath)) | Out-Null

$sourceImage = [System.Drawing.Image]::FromFile($sourcePath)
$bitmap = New-Object System.Drawing.Bitmap 1024, 500
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

$targetAspect = 1024.0 / 500.0
$sourceAspect = $sourceImage.Width / [double]$sourceImage.Height
if ($sourceAspect -gt $targetAspect) {
    $cropHeight = $sourceImage.Height
    $cropWidth = [int]($cropHeight * $targetAspect)
    $cropX = [int](($sourceImage.Width - $cropWidth) / 2)
    $cropY = 0
} else {
    $cropWidth = $sourceImage.Width
    $cropHeight = [int]($cropWidth / $targetAspect)
    $cropX = 0
    $cropY = [int](($sourceImage.Height - $cropHeight) / 2)
}
$graphics.DrawImage($sourceImage, (New-Object System.Drawing.Rectangle 0, 0, 1024, 500),
    $cropX, $cropY, $cropWidth, $cropHeight, [System.Drawing.GraphicsUnit]::Pixel)

$fonts = New-Object System.Drawing.Text.PrivateFontCollection
$fonts.AddFontFile($fontPath)
$titleFont = New-Object System.Drawing.Font($fonts.Families[0], 92,
    [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$subFont = New-Object System.Drawing.Font($fonts.Families[0], 27,
    [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$brass = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 220, 181, 62))
$paper = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 242, 232, 213))
$shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(180, 0, 0, 0))
$graphics.DrawString("KINGPIN", $titleFont, $shadow, 57, 184)
$graphics.DrawString("KINGPIN", $titleFont, $brass, 52, 179)
$graphics.DrawString("A  P I N B A L L  R A C K E T", $subFont, $paper, 57, 287)

$bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$shadow.Dispose(); $paper.Dispose(); $brass.Dispose()
$subFont.Dispose(); $titleFont.Dispose(); $fonts.Dispose()
$graphics.Dispose(); $bitmap.Dispose(); $sourceImage.Dispose()
Write-Output "store art: $outputPath (1024x500)"
