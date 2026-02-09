<#
ManifestHint:
  ExportFunctions = @(
    "Get-RelativePathSafe","Resolve-FullPathSafe",
    "Get-ContentTypeByExt",
    "Scan-ImageFolders","Delete-FolderSafe"
  )
  Description     = "Index/Scan/Delete Helpers: sichere Pfade, ContentTypes, Folder-Scan, Delete (Papierkorb/HardDelete)."
  Category        = "Media"
  Tags            = @("Index","Scan","Photos","Videos","RecycleBin","HardDelete","PathSafety")
  Dependencies    = @("Microsoft.VisualBasic")

Zweck:
  - Foto-Ordner scannen + sichere Pfadauflösung + Löschlogik.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RelativePathSafe {
  param([string]$Base, [string]$Full)

  $baseFull = [System.IO.Path]::GetFullPath($Base)
  $fullFull = [System.IO.Path]::GetFullPath($Full)

  if (-not $fullFull.StartsWith($baseFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Path außerhalb Root: $fullFull"
  }

  $rel = $fullFull.Substring($baseFull.Length).TrimStart('\','/')
  return $rel
}

function Resolve-FullPathSafe {
  param(
    [string]$RootFull,
    [string]$RelPath
  )

  if ([string]::IsNullOrWhiteSpace($RelPath)) {
    throw "RelPath leer"
  }

  # Zusätzliche Absicherung gegen Traversal
  if ($RelPath -match '(^|[\\/])\.\.([\\/]|$)') {
    throw "Ungültiger RelPath (..): $RelPath"
  }

  $full = Join-Path $RootFull $RelPath
  $full = [System.IO.Path]::GetFullPath($full)

  if (-not $full.StartsWith($RootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Ungültiger Zielpfad (außerhalb Root): $full"
  }

  return $full
}

function Get-ContentTypeByExt {
  param([string]$Path)
  switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
    ".jpg"  { "image/jpeg" }
    ".jpeg" { "image/jpeg" }
    ".png"  { "image/png" }
    ".webp" { "image/webp" }
    ".gif"  { "image/gif" }
    ".bmp"  { "image/bmp" }
    ".tif"  { "image/tiff" }
    ".tiff" { "image/tiff" }

    # Video
    ".mp4"  { "video/mp4" }
    ".m4v"  { "video/mp4" }
    ".webm" { "video/webm" }
    ".ogv"  { "video/ogg" }
    ".mov"  { "video/quicktime" }
    ".mkv"  { "video/x-matroska" }
    ".avi"  { "video/x-msvideo" }

    default { "application/octet-stream" }
  }
}

function Get-NaturalSortKey {
  param([string]$Text)
  # Zerlegt Text in Segmente: Zahlen werden als Long gepaddet, Text bleibt lowercase
  [regex]::Replace($Text, '(\d+)', {
    param($m)
    $m.Value.PadLeft(20, '0')
  }).ToLowerInvariant()
}

function Scan-ImageFolders {
  param(
    [string]$Root,
    [string[]]$ImageExt
  )

  $rootFull = [System.IO.Path]::GetFullPath($Root)
  $folders = @()

  $allDirs = Get-ChildItem -LiteralPath $rootFull -Directory -Recurse -Force -ErrorAction SilentlyContinue
  $allDirs = @((Get-Item -LiteralPath $rootFull)) + @($allDirs)

  foreach ($d in $allDirs) {
    try {
      $imgs = Get-ChildItem -LiteralPath $d.FullName -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $ImageExt -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object { Get-NaturalSortKey $_.Name }

      if ($imgs.Count -gt 0) {
        $folders += [pscustomobject]@{
          FullPath   = $d.FullName
          RelPath    = Get-RelativePathSafe -Base $rootFull -Full $d.FullName
          ImgCount   = $imgs.Count
          ImagesRel  = @($imgs | ForEach-Object { Get-RelativePathSafe -Base $rootFull -Full $_.FullName })
        }
      }
    } catch {
      # Ordner überspringen, Scan fortsetzen
    }
  }

  return $folders | Sort-Object { Get-NaturalSortKey $_.RelPath }
}

function Delete-FolderSafe {
  param(
    [string]$RootFull,
    [string]$RelFolder,
    [switch]$HardDelete
  )

  $targetFull = Resolve-FullPathSafe -RootFull $RootFull -RelPath $RelFolder

  if (-not (Test-Path -LiteralPath $targetFull -PathType Container)) {
    throw "Ordner nicht gefunden: $targetFull"
  }

  if ($HardDelete) {
    Remove-Item -LiteralPath $targetFull -Recurse -Force
  } else {
    Add-Type -AssemblyName Microsoft.VisualBasic | Out-Null
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
      $targetFull,
      [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
      [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
    )
  }
}