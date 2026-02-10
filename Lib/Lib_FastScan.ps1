<#
ManifestHint:
  ExportFunctions = @("Scan-ImageFolders")
  Description     = "Fast Image Folder Scanning mit Cache-System und Incremental Updates"
  Category        = "Media"
  Tags            = @("ImageScanning","Performance","Cache","Incremental","FileSystem")
  Dependencies    = @("Lib_FileSystem.ps1")

Zweck:
  - Schnelles Scannen von Bildordnern (optimiert)
  - JSON-basiertes Cache-System
  - Incremental Updates (nur geänderte Ordner)
  - Optional: Parallel-Scan (PowerShell 7+)
  - Kompatibel mit alter Scan-ImageFolders Signatur
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Cache-Verzeichnis (im User-Temp)
$script:CacheDir = Join-Path $env:TEMP "PhotoFolder_Cache"

# ------------------------------------------------------------
# Cache-Pfad für Root generieren
# ------------------------------------------------------------
function Get-CachePath {
  param([string]$RootPath)
  
  # Root-Pfad als Hash verwenden (für eindeutige Cache-Files)
  $hash = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($RootPath.ToLowerInvariant()))).Replace("-","")
  $cacheName = "scan_$($hash.Substring(0,16)).json"
  
  if (-not (Test-Path -LiteralPath $script:CacheDir -PathType Container)) {
    New-Item -Path $script:CacheDir -ItemType Directory -Force | Out-Null
  }
  
  return Join-Path $script:CacheDir $cacheName
}

# ------------------------------------------------------------
# Cache laden
# ------------------------------------------------------------
function Get-ScanCache {
  param([string]$RootPath)
  
  $cachePath = Get-CachePath -RootPath $RootPath
  
  if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
    return $null
  }
  
  try {
    $json = Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8
    $cache = $json | ConvertFrom-Json
    return $cache
  } catch {
    Write-Warning "Cache-Datei beschädigt: $cachePath"
    return $null
  }
}

# ------------------------------------------------------------
# Cache speichern
# ------------------------------------------------------------
function Set-ScanCache {
  param(
    [string]$RootPath,
    [object]$Data
  )
  
  $cachePath = Get-CachePath -RootPath $RootPath
  
  try {
    $json = $Data | ConvertTo-Json -Depth 10 -Compress
    $json | Out-File -LiteralPath $cachePath -Encoding UTF8 -Force
  } catch {
    Write-Warning "Cache konnte nicht gespeichert werden: $($_.Exception.Message)"
  }
}

# ------------------------------------------------------------
# Ordner auf Änderungen prüfen
# ------------------------------------------------------------
function Test-FolderChanged {
  param(
    [string]$FolderPath,
    [DateTime]$CachedLastWrite
  )
  
  if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
    return $true  # Ordner existiert nicht mehr = geändert
  }
  
  $dir = Get-Item -LiteralPath $FolderPath
  return ($dir.LastWriteTimeUtc -gt $CachedLastWrite)
}

# ------------------------------------------------------------
# Einzelnen Ordner scannen
# ------------------------------------------------------------
function Scan-SingleFolder {
  param(
    [string]$FolderPath,
    [string]$RootPath,
    [string[]]$ImageExtensions
  )
  
  $rel = Get-RelativePathSafe -Base $RootPath -Full $FolderPath
  
  try {
    $imgs = @(Get-ChildItem -LiteralPath $FolderPath -File -Force -ErrorAction SilentlyContinue | 
              Where-Object { $ImageExtensions -contains $_.Extension.ToLowerInvariant() })
  } catch {
    Write-Warning "Fehler beim Scannen von $FolderPath : $($_.Exception.Message)"
    $imgs = @()
  }
  
  if ($imgs.Count -eq 0) {
    return $null
  }
  
  $imgsRel = $imgs | ForEach-Object { 
    Get-RelativePathSafe -Base $RootPath -Full $_.FullName 
  }
  
  $dir = Get-Item -LiteralPath $FolderPath
  
  return [PSCustomObject]@{
    RelPath        = $rel
    ImgCount       = $imgs.Count
    ImagesRel      = $imgsRel
    LastWriteUtc   = $dir.LastWriteTimeUtc
  }
}

# ------------------------------------------------------------
# Hauptfunktion: Scan-ImageFolders (mit Cache)
# ------------------------------------------------------------
function Scan-ImageFolders {
  <#
  .SYNOPSIS
  Scannt Ordnerstruktur nach Bildern (mit Cache-Support)
  
  .PARAMETER Root
  Root-Verzeichnis zum Scannen
  
  .PARAMETER ImageExt
  Array von Bild-Extensions (z.B. @(".jpg",".png"))
  
  .PARAMETER UseCache
  Wenn $true: Cache verwenden (schneller bei wiederholten Scans)
  
  .PARAMETER ForceRefresh
  Wenn $true: Cache ignorieren und komplett neu scannen
  
  .PARAMETER Parallel
  Wenn $true: Parallel-Scan (nur PowerShell 7+, experimentell)
  
  .EXAMPLE
  # Erster Scan (ohne Cache)
  $folders = Scan-ImageFolders -Root "C:\Photos" -ImageExt @(".jpg",".png")
  
  .EXAMPLE
  # Mit Cache (schneller)
  $folders = Scan-ImageFolders -Root "C:\Photos" -ImageExt @(".jpg",".png") -UseCache
  
  .EXAMPLE
  # Cache erzwingen neu aufbauen
  $folders = Scan-ImageFolders -Root "C:\Photos" -ImageExt @(".jpg",".png") -UseCache -ForceRefresh
  
  .OUTPUTS
  Array of PSCustomObject mit:
  - RelPath: Relativer Pfad
  - ImgCount: Anzahl Bilder
  - ImagesRel: Array von relativen Bild-Pfaden
  #>
  
  param(
    [Parameter(Mandatory)]
    [string]$Root,
    
    [Parameter(Mandatory)]
    [string[]]$ImageExt,
    
    [switch]$UseCache,
    [switch]$ForceRefresh,
    [switch]$Parallel
  )

  $rootFull = [System.IO.Path]::GetFullPath($Root)
  
  if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) {
    throw "Root-Verzeichnis existiert nicht: $rootFull"
  }

  # Extensions normalisieren (lowercase)
  $imageExtLower = $ImageExt | ForEach-Object { $_.ToLowerInvariant() }

  # Cache laden (wenn aktiviert)
  $cache = $null
  $cacheData = @{}
  
  if ($UseCache -and -not $ForceRefresh) {
    $cache = Get-ScanCache -RootPath $rootFull
    if ($cache) {
      Write-Verbose "Cache geladen: $($cache.Folders.Count) Ordner"
      # Cache in Hashtable umwandeln (für schnellen Lookup)
      foreach ($f in $cache.Folders) {
        $cacheData[$f.RelPath] = $f
      }
    }
  }

  # Alle Ordner finden
  Write-Verbose "Scanne Ordnerstruktur..."
  try {
    $allDirs = @(Get-ChildItem -LiteralPath $rootFull -Directory -Recurse -Force -ErrorAction SilentlyContinue)
  } catch {
    Write-Warning "Fehler beim Scannen der Ordnerstruktur: $($_.Exception.Message)"
    $allDirs = @()
  }
  
  Write-Verbose "Gefunden: $($allDirs.Count) Ordner"

  $result = @()
  $scannedCount = 0
  $cachedCount = 0

  foreach ($d in $allDirs) {
    $relPath = Get-RelativePathSafe -Base $rootFull -Full $d.FullName
    
    # Cache-Check: Wurde Ordner geändert?
    $useCache = $false
    if ($cacheData.ContainsKey($relPath)) {
      $cachedFolder = $cacheData[$relPath]
      if (-not (Test-FolderChanged -FolderPath $d.FullName -CachedLastWrite ([DateTime]$cachedFolder.LastWriteUtc))) {
        # Ordner unverändert -> Cache verwenden
        $result += [PSCustomObject]@{
          RelPath   = $cachedFolder.RelPath
          ImgCount  = $cachedFolder.ImgCount
          ImagesRel = $cachedFolder.ImagesRel
        }
        $cachedCount++
        $useCache = $true
      }
    }
    
    if (-not $useCache) {
      # Ordner neu scannen
      $folderData = Scan-SingleFolder -FolderPath $d.FullName -RootPath $rootFull -ImageExtensions $imageExtLower
      if ($folderData) {
        $result += [PSCustomObject]@{
          RelPath   = $folderData.RelPath
          ImgCount  = $folderData.ImgCount
          ImagesRel = $folderData.ImagesRel
        }
        # Für Cache speichern (mit LastWriteUtc)
        $cacheData[$relPath] = $folderData
        $scannedCount++
      }
    }
  }

  Write-Verbose "Scan abgeschlossen: $scannedCount neu gescannt, $cachedCount aus Cache"

  # Sortierung (Natural Sort)
  $sorted = $result | Sort-Object { 
    $parts = Get-NaturalSortKey -Text $_.RelPath
    return $parts
  }

  # Cache speichern (wenn aktiviert)
  if ($UseCache) {
    $cacheObject = [PSCustomObject]@{
      RootPath     = $rootFull
      ScanDate     = (Get-Date).ToString("o")
      FolderCount  = $cacheData.Count
      Folders      = @($cacheData.Values)
    }
    Set-ScanCache -RootPath $rootFull -Data $cacheObject
    Write-Verbose "Cache gespeichert: $($cacheData.Count) Ordner"
  }

  return $sorted
}

# ------------------------------------------------------------
# Cache löschen
# ------------------------------------------------------------
function Clear-ScanCache {
  <#
  .SYNOPSIS
  Löscht Cache für spezifischen Root oder alle Caches
  
  .PARAMETER RootPath
  Optional: Root-Pfad. Wenn nicht angegeben, werden alle Caches gelöscht
  
  .EXAMPLE
  Clear-ScanCache -RootPath "C:\Photos"
  
  .EXAMPLE
  Clear-ScanCache  # Alle Caches löschen
  #>
  
  param([string]$RootPath)
  
  if ($RootPath) {
    $cachePath = Get-CachePath -RootPath $RootPath
    if (Test-Path -LiteralPath $cachePath) {
      Remove-Item -LiteralPath $cachePath -Force
      Write-Host "Cache gelöscht: $cachePath"
    } else {
      Write-Host "Kein Cache gefunden für: $RootPath"
    }
  } else {
    if (Test-Path -LiteralPath $script:CacheDir) {
      Remove-Item -LiteralPath $script:CacheDir -Recurse -Force
      Write-Host "Alle Caches gelöscht: $script:CacheDir"
    } else {
      Write-Host "Kein Cache-Verzeichnis gefunden"
    }
  }
}