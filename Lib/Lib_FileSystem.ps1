<#
ManifestHint:
  ExportFunctions = @(
    "Get-RelativePathSafe","Resolve-FullPathSafe",
    "Get-ContentTypeByExt","Get-NaturalSortKey",
    "Delete-FolderSafe","Delete-FileSafe"
  )
  Description     = "FileSystem Helper: Path Safety, Content-Type Detection, Natural Sorting, Safe Delete Operations"
  Category        = "FileSystem"
  Tags            = @("FileSystem","PathSafety","ContentType","NaturalSort","Delete","RecycleBin")
  Dependencies    = @("Microsoft.VisualBasic")

Zweck:
  - Path Safety: Relative/Absolute Path Conversion mit Security
  - Content-Type Detection: MIME-Types für Web-Serving
  - Natural Sorting: Natürliche Sortierung (z.B. "Datei10" nach "Datei2")
  - Safe Delete: Papierkorb oder HardDelete für Files/Folders
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Assembly für Delete-Operationen vorladen
Add-Type -AssemblyName Microsoft.VisualBasic | Out-Null

# ------------------------------------------------------------
# Relativer Pfad (sicher)
# ------------------------------------------------------------
function Get-RelativePathSafe {
  <#
  .SYNOPSIS
  Konvertiert absoluten Pfad zu relativem Pfad (sicher)
  
  .PARAMETER Base
  Basis-Pfad (Root)
  
  .PARAMETER Full
  Vollständiger Pfad
  
  .EXAMPLE
  Get-RelativePathSafe -Base "C:\Photos" -Full "C:\Photos\2024\Summer\img.jpg"
  # Returns: "2024\Summer\img.jpg"
  #>
  
  param(
    [Parameter(Mandatory)]
    [string]$Base,
    
    [Parameter(Mandatory)]
    [string]$Full
  )

  $baseFull = [System.IO.Path]::GetFullPath($Base).TrimEnd('\', '/')
  $targetFull = [System.IO.Path]::GetFullPath($Full).TrimEnd('\', '/')

  if (-not $targetFull.StartsWith($baseFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Path '$Full' is outside base '$Base'"
  }

  $rel = $targetFull.Substring($baseFull.Length).TrimStart('\', '/')
  return $rel
}

# ------------------------------------------------------------
# Absoluter Pfad (sicher, Path-Traversal-geschützt)
# ------------------------------------------------------------
function Resolve-FullPathSafe {
  <#
  .SYNOPSIS
  Konvertiert relativen Pfad zu absolutem Pfad (mit Security-Check)
  
  .PARAMETER RootFull
  Root-Verzeichnis (muss absolut sein)
  
  .PARAMETER RelPath
  Relativer Pfad
  
  .EXAMPLE
  Resolve-FullPathSafe -RootFull "C:\Photos" -RelPath "2024\img.jpg"
  # Returns: "C:\Photos\2024\img.jpg"
  
  .NOTES
  Wirft Exception bei Path-Traversal-Versuchen (../)
  #>
  
  param(
    [Parameter(Mandatory)]
    [string]$RootFull,
    
    [Parameter(Mandatory)]
    [string]$RelPath
  )

  $joined = [System.IO.Path]::Combine($RootFull, $RelPath)
  $abs = [System.IO.Path]::GetFullPath($joined)

  if (-not $abs.StartsWith($RootFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Path traversal detected: $RelPath"
  }

  return $abs
}

# ------------------------------------------------------------
# Content-Type für Extension
# ------------------------------------------------------------
function Get-ContentTypeByExt {
  <#
  .SYNOPSIS
  Gibt MIME-Type für Dateiendung zurück
  
  .PARAMETER Path
  Dateipfad oder Extension
  
  .EXAMPLE
  Get-ContentTypeByExt -Path "image.jpg"
  # Returns: "image/jpeg"
  #>
  
  param([string]$Path)

  $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()

  switch ($ext) {
    ".jpg"  { return "image/jpeg" }
    ".jpeg" { return "image/jpeg" }
    ".png"  { return "image/png" }
    ".gif"  { return "image/gif" }
    ".webp" { return "image/webp" }
    ".bmp"  { return "image/bmp" }
    ".ico"  { return "image/x-icon" }
    ".svg"  { return "image/svg+xml" }
    ".tif"  { return "image/tiff" }
    ".tiff" { return "image/tiff" }
    ".mp4"  { return "video/mp4" }
    ".webm" { return "video/webm" }
    ".mp3"  { return "audio/mpeg" }
    ".wav"  { return "audio/wav" }
    ".pdf"  { return "application/pdf" }
    ".json" { return "application/json" }
    ".xml"  { return "application/xml" }
    ".html" { return "text/html" }
    ".htm"  { return "text/html" }
    ".css"  { return "text/css" }
    ".js"   { return "application/javascript" }
    ".txt"  { return "text/plain" }
    default { return "application/octet-stream" }
  }
}

# ------------------------------------------------------------
# Natural Sort Key
# ------------------------------------------------------------
function Get-NaturalSortKey {
  <#
  .SYNOPSIS
  Generiert Sort-Key für natürliche Sortierung
  
  .PARAMETER Text
  Text zum Sortieren
  
  .EXAMPLE
  @("File1","File10","File2") | Sort-Object { Get-NaturalSortKey $_ }
  # Returns: File1, File2, File10
  
  .NOTES
  Splittet Text in alphanumerische und numerische Teile
  #>
  
  param([string]$Text)

  $parts = [regex]::Split($Text, '(\d+)')
  $result = @()

  foreach ($p in $parts) {
    if ([string]::IsNullOrWhiteSpace($p)) { continue }

    $num = 0
    if ([int]::TryParse($p, [ref]$num)) {
      $result += [PSCustomObject]@{ Type = "N"; Val = $num }
    } else {
      $result += [PSCustomObject]@{ Type = "S"; Val = $p.ToLowerInvariant() }
    }
  }

  return $result
}

# ------------------------------------------------------------
# Ordner sicher löschen (Papierkorb oder HardDelete)
# ------------------------------------------------------------
function Delete-FolderSafe {
  <#
  .SYNOPSIS
  Löscht Ordner sicher (Papierkorb oder permanent)
  
  .PARAMETER RootFull
  Root-Verzeichnis (für Path-Safety-Check)
  
  .PARAMETER RelFolder
  Relativer Ordnerpfad
  
  .PARAMETER HardDelete
  Wenn $true: permanent löschen, sonst Papierkorb
  
  .EXAMPLE
  Delete-FolderSafe -RootFull "C:\Photos" -RelFolder "2024\OldStuff" -HardDelete:$false
  #>
  
  param(
    [Parameter(Mandatory)]
    [string]$RootFull,
    
    [Parameter(Mandatory)]
    [string]$RelFolder,
    
    [switch]$HardDelete
  )

  $targetFull = Resolve-FullPathSafe -RootFull $RootFull -RelPath $RelFolder

  if (-not (Test-Path -LiteralPath $targetFull -PathType Container)) {
    Write-Warning "Ordner nicht gefunden: $targetFull"
    return
  }

  if ($HardDelete) {
    Remove-Item -LiteralPath $targetFull -Recurse -Force
  } else {
    # Shell.Application COM-Objekt für Papierkorb (DeleteDirectory unterstützt kein RecycleOption)
    try {
      $shell = New-Object -ComObject Shell.Application
      $folder = $shell.NameSpace(0).ParseName($targetFull)
      if ($folder) {
        $folder.InvokeVerb("delete")
      } else {
        Write-Warning "Shell.Application konnte Ordner nicht finden: $targetFull"
        # Fallback: Microsoft.VisualBasic (zeigt Dialoge)
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
          $targetFull,
          [Microsoft.VisualBasic.FileIO.UIOption]::AllDialogs,
          [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
      }
    } catch {
      Write-Warning "Shell.Application fehlgeschlagen für $targetFull : $($_.Exception.Message)"
      # Fallback
      [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
        $targetFull,
        [Microsoft.VisualBasic.FileIO.UIOption]::AllDialogs,
        [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
      )
    }
  }
}

# ------------------------------------------------------------
# Datei sicher löschen (Papierkorb oder HardDelete)
# ------------------------------------------------------------
function Delete-FileSafe {
  <#
  .SYNOPSIS
  Löscht Datei sicher (Papierkorb oder permanent)
  
  .PARAMETER RootFull
  Root-Verzeichnis (für Path-Safety-Check)
  
  .PARAMETER RelFile
  Relativer Dateipfad
  
  .PARAMETER HardDelete
  Wenn $true: permanent löschen, sonst Papierkorb
  
  .EXAMPLE
  Delete-FileSafe -RootFull "C:\Photos" -RelFile "2024\bad.jpg" -HardDelete:$false
  #>
  
  param(
    [Parameter(Mandatory)]
    [string]$RootFull,
    
    [Parameter(Mandatory)]
    [string]$RelFile,
    
    [switch]$HardDelete
  )

  $targetFull = Resolve-FullPathSafe -RootFull $RootFull -RelPath $RelFile

  if (-not (Test-Path -LiteralPath $targetFull -PathType Leaf)) {
    Write-Warning "Datei nicht gefunden: $targetFull"
    return
  }

  if ($HardDelete) {
    Remove-Item -LiteralPath $targetFull -Force
  } else {
    # RecycleOption funktioniert für Dateien (im Gegensatz zu Ordnern)
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
      $targetFull,
      [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
      [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
    )
  }
}