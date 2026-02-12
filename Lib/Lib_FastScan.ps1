#Requires -Version 5.1

<#
.SYNOPSIS
    Fast Image Folder Scanning mit Cache-System

.DESCRIPTION
    Schnelles Scannen von Bildordnern mit JSON-basiertem Cache-System,
    Incremental Updates und natürlicher Sortierung.
    
    Features:
    - JSON-basiertes Cache-System
    - Incremental Updates (nur geänderte Ordner)
    - Natürliche Sortierung
    - Ignoriert .thumbs Ordner

.EXAMPLE
    $folders = Scan-ImageFolders -Root "C:\Photos" -ImageExt @(".jpg",".png") -UseCache
    
    Scannt Ordner mit Cache

.NOTES
    Autor: Herbert Schrotter
    Version: 1.0.1
    
.LINK
    https://github.com/herbertschrotter-blip/01_Scripte_Sammlung
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# Cache-Verzeichnis (im User-Temp)
$script:CacheDir = Join-Path $env:TEMP "PhotoFolder_Cache"

# ============================================================================
# NATÜRLICHE SORTIERUNG
# ============================================================================

function ConvertTo-NaturalSortKey {
    <#
    .SYNOPSIS
        Konvertiert Text zu Natural-Sort-Key
    
    .DESCRIPTION
        Zerlegt Text in Zahlen und Nicht-Zahlen für natürliche Sortierung.
    
    .PARAMETER Text
        Zu konvertierender Text
    
    .EXAMPLE
        ConvertTo-NaturalSortKey -Text "Bild 10"
    
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )
    
    # Zerlege Text in Zahlen und Nicht-Zahlen
    $parts = [regex]::Split($Text, '(\d+)')
    
    $result = New-Object System.Collections.ArrayList
    
    foreach ($part in $parts) {
        if ($part -match '^\d+$') {
            # Zahl: als Integer speichern (mit führenden Nullen zum Vergleich)
            $num = [int]$part
            [void]$result.Add($num.ToString("D20"))  # 20 Stellen mit Nullen auffüllen
        } else {
            # Text: normal anhängen
            [void]$result.Add($part.ToLower())
        }
    }
    
    return $result -join ''
}

function Sort-Natural {
    <#
    .SYNOPSIS
        Sortiert Objekte natürlich (numerisch-aware)
    
    .DESCRIPTION
        Sortiert so dass "Bild 2" vor "Bild 10" kommt.
    
    .PARAMETER InputObject
        Zu sortierende Objekte
    
    .PARAMETER Property
        Property-Name für Sortierung
    
    .EXAMPLE
        $items | Sort-Natural -Property Name
    
    .OUTPUTS
        System.Object[]
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        
        [Parameter()]
        [string]$Property
    )
    
    begin {
        $items = @()
    }
    
    process {
        $items += $InputObject
    }
    
    end {
        if ($Property) {
            $items | Sort-Object -Property @{
                Expression = { ConvertTo-NaturalSortKey -Text $_.$Property }
            }
        } else {
            $items | Sort-Object -Property @{
                Expression = { ConvertTo-NaturalSortKey -Text $_ }
            }
        }
    }
}

# ============================================================================
# CACHE-FUNKTIONEN
# ============================================================================

function Get-CachePath {
    <#
    .SYNOPSIS
        Generiert Cache-Pfad für Root
    
    .PARAMETER RootPath
        Root-Verzeichnis
    
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )
    
    # Root-Pfad als Hash verwenden (für eindeutige Cache-Files)
    $hash = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($RootPath.ToLowerInvariant()))).Replace("-","")
    $cacheName = "scan_$($hash.Substring(0,16)).json"
    
    if (-not (Test-Path -LiteralPath $script:CacheDir -PathType Container)) {
        New-Item -Path $script:CacheDir -ItemType Directory -Force | Out-Null
    }
    
    return Join-Path $script:CacheDir $cacheName
}

function Get-ScanCache {
    <#
    .SYNOPSIS
        Lädt Cache für Root
    
    .PARAMETER RootPath
        Root-Verzeichnis
    
    .OUTPUTS
        PSCustomObject oder $null
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )
    
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

function Set-ScanCache {
    <#
    .SYNOPSIS
        Speichert Cache für Root
    
    .PARAMETER RootPath
        Root-Verzeichnis
    
    .PARAMETER Data
        Zu speichernde Daten
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,
        
        [Parameter(Mandatory)]
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

function Test-FolderChanged {
    <#
    .SYNOPSIS
        Prüft ob Ordner geändert wurde
    
    .PARAMETER FolderPath
        Ordner-Pfad
    
    .PARAMETER CachedLastWrite
        Gecachter LastWriteTime
    
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath,
        
        [Parameter(Mandatory)]
        [DateTime]$CachedLastWrite
    )
    
    if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
        return $true  # Ordner existiert nicht mehr = geändert
    }
    
    $dir = Get-Item -LiteralPath $FolderPath
    return ($dir.LastWriteTimeUtc -gt $CachedLastWrite)
}

# ============================================================================
# SCAN-FUNKTIONEN
# ============================================================================

function Scan-SingleFolder {
    <#
    .SYNOPSIS
        Scannt einzelnen Ordner
    
    .PARAMETER FolderPath
        Ordner-Pfad
    
    .PARAMETER RootPath
        Root-Pfad
    
    .PARAMETER ImageExtensions
        Bild-Extensions
    
    .OUTPUTS
        PSCustomObject oder $null
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath,
        
        [Parameter(Mandatory)]
        [string]$RootPath,
        
        [Parameter(Mandatory)]
        [string[]]$ImageExtensions
    )
    
    # Skip .thumbs Ordner komplett
    if ((Split-Path -Leaf $FolderPath) -eq '.thumbs') {
        return $null
    }
    
    $rel = Get-RelativePathSafe -Base $RootPath -Full $FolderPath
    
    try {
        $imgs = @(Get-ChildItem -LiteralPath $FolderPath -File -Force -ErrorAction SilentlyContinue | 
                  Where-Object { $ImageExtensions -contains $_.Extension.ToLowerInvariant() })
    } catch {
        Write-Warning "Fehler beim Scannen von $FolderPath : $($_.Exception.Message)"
        $imgs = @()
    }
    
    if (@($imgs).Count -eq 0) {
        return $null
    }
    
    $imgsRel = @($imgs | ForEach-Object { 
        Get-RelativePathSafe -Base $RootPath -Full $_.FullName 
    })
    
    try {
        $dir = Get-Item -LiteralPath $FolderPath -Force -ErrorAction Stop
    } catch {
        Write-Warning "Fehler beim Zugriff auf Ordner $FolderPath : $($_.Exception.Message)"
        return $null
    }
    
    return [PSCustomObject]@{
        RelPath        = $rel
        ImgCount       = @($imgs).Count
        ImagesRel      = $imgsRel
        LastWriteUtc   = $dir.LastWriteTimeUtc
    }
}

function Scan-ImageFolders {
    <#
    .SYNOPSIS
        Scannt Ordnerstruktur nach Bildern (mit Cache-Support)
    
    .DESCRIPTION
        Schnelles Scannen mit Cache-Unterstützung. Nur geänderte Ordner werden neu gescannt.
    
    .PARAMETER Root
        Root-Verzeichnis zum Scannen
    
    .PARAMETER ImageExt
        Array von Bild-Extensions (z.B. @(".jpg",".png"))
    
    .PARAMETER UseCache
        Cache verwenden (schneller bei wiederholten Scans)
    
    .PARAMETER ForceRefresh
        Cache ignorieren und komplett neu scannen
    
    .EXAMPLE
        $folders = Scan-ImageFolders -Root "C:\Photos" -ImageExt @(".jpg",".png") -UseCache
    
    .OUTPUTS
        PSCustomObject[]
        
        Array von Objekten mit RelPath, ImgCount, ImagesRel
    
    .NOTES
        Verwendet JSON-Cache für Performance
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Root,
        
        [Parameter(Mandatory)]
        [string[]]$ImageExt,
        
        [Parameter()]
        [switch]$UseCache,
        
        [Parameter()]
        [switch]$ForceRefresh
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
            Write-Verbose "Cache geladen: $(@($cache.Folders).Count) Ordner"
            # Cache in Hashtable umwandeln (für schnellen Lookup)
            foreach ($f in $cache.Folders) {
                $cacheData[$f.RelPath] = $f
            }
        }
    }

    # Alle Ordner finden (außer .thumbs)
    Write-Verbose "Scanne Ordnerstruktur..."
    try {
        $allDirs = @(Get-ChildItem -LiteralPath $rootFull -Directory -Recurse -Force -ErrorAction SilentlyContinue | 
                     Where-Object { $_.Name -ne '.thumbs' })
    } catch {
        Write-Warning "Fehler beim Scannen der Ordnerstruktur: $($_.Exception.Message)"
        $allDirs = @()
    }
    
    Write-Verbose "Gefunden: $(@($allDirs).Count) Ordner"

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
                    ImagesRel = @($cachedFolder.ImagesRel)
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
                    ImagesRel = @($folderData.ImagesRel)
                }
                # Für Cache speichern (mit LastWriteUtc)
                $cacheData[$relPath] = $folderData
                $scannedCount++
            }
        }
    }

    Write-Verbose "Scan abgeschlossen: $scannedCount neu gescannt, $cachedCount aus Cache"

    # Cache speichern (wenn aktiviert)
    if ($UseCache) {
        $cacheObject = [PSCustomObject]@{
            RootPath     = $rootFull
            ScanDate     = (Get-Date).ToString("o")
            FolderCount  = @($cacheData.Values).Count
            Folders      = @($cacheData.Values)
        }
        Set-ScanCache -RootPath $rootFull -Data $cacheObject
        Write-Verbose "Cache gespeichert: $(@($cacheData.Values).Count) Ordner"
    }

    # Natürlich sortiert zurückgeben
    return $result | Sort-Natural -Property RelPath
}

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
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [string]$RootPath
    )
    
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