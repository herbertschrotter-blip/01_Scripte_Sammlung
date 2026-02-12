#Requires -Version 5.1

<#
.SYNOPSIS
    Dateisystem-Hilfsfunktionen für PhotoFolder

.DESCRIPTION
    Stellt grundlegende Dateisystem-Operationen bereit:
    - Rekursives Scannen von Verzeichnissen
    - Natürliche Sortierung von Ordnernamen
    - Filterung nach Dateiendungen (Bilder, Videos)
    - Cache-Management für Ordner-Strukturen
    - Relative Pfad-Berechnung
    
    Optimiert für große Foto-/Video-Sammlungen mit natürlicher Sortierung.

.EXAMPLE
    # Lib laden
    . .\Lib\Lib_FileSystem.ps1
    
    # Ordner scannen
    $folders = Get-FoldersRecursive -RootPath "C:\Photos"
    
    # Natürlich sortieren
    $sorted = Sort-FoldersNaturally -Folders $folders

.NOTES
    Autor: Herbert Schrotter
    Version: 1.0.1
    
.LINK
    https://github.com/herbertschrotter-blip/01_Scripte_Sammlung
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# ============================================================================
# GLOBALE VARIABLEN
# ============================================================================

# Unterstützte Bildformate
$script:ImageExtensions = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.heic')

# Unterstützte Videoformate
$script:VideoExtensions = @('.mp4', '.avi', '.mov', '.wmv', '.mkv', '.webm', '.m4v', '.mpg', '.mpeg')

# ============================================================================
# RELATIVE PFAD-BERECHNUNG
# ============================================================================

function Get-RelativePathSafe {
    <#
    .SYNOPSIS
        Berechnet relativen Pfad mit Fehlerbehandlung
    
    .DESCRIPTION
        Berechnet den relativen Pfad von Base zu Target.
        Bei Fehler (z.B. unterschiedliche Laufwerke) wird der vollständige Target-Pfad zurückgegeben.
    
    .PARAMETER Base
        Basis-Pfad (z.B. "C:\Photos")
    
    .PARAMETER Target
        Ziel-Pfad (z.B. "C:\Photos\Vacation\2024")
    
    .EXAMPLE
        Get-RelativePathSafe -Base "C:\Photos" -Target "C:\Photos\Vacation"
        
        Gibt zurück: "Vacation"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Base,
        
        [Parameter(Mandatory)]
        [string]$Target
    )
    
    try {
        $Base = $Base.TrimEnd('\')
        $Target = $Target.TrimEnd('\')
        
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $relativePath = [System.IO.Path]::GetRelativePath($Base, $Target)
        }
        else {
            if ($Target.StartsWith($Base, [StringComparison]::OrdinalIgnoreCase)) {
                $relativePath = $Target.Substring($Base.Length).TrimStart('\')
            }
            else {
                $relativePath = $Target
            }
        }
        
        if ([string]::IsNullOrEmpty($relativePath)) {
            $relativePath = '.'
        }
        
        Write-Verbose "Relativer Pfad: '$Base' -> '$Target' = '$relativePath'"
        return $relativePath
    }
    catch {
        Write-Verbose "Fehler bei Pfad-Berechnung, verwende vollständigen Pfad: $_"
        return $Target
    }
}

# ============================================================================
# ORDNER SCANNEN (REKURSIV)
# ============================================================================

function Get-FoldersRecursive {
    <#
    .SYNOPSIS
        Scannt Verzeichnisbaum rekursiv und gibt alle Ordner zurück
    
    .DESCRIPTION
        Durchsucht den angegebenen Root-Pfad rekursiv nach allen Unterordnern.
        Gibt strukturierte Objekte mit Pfad, Tiefe und Parent-Informationen zurück.
        Ignoriert versteckte Ordner und System-Ordner.
    
    .PARAMETER RootPath
        Root-Verzeichnis für den Scan
    
    .PARAMETER MaxDepth
        Maximale Scan-Tiefe (Standard: unbegrenzt)
    
    .EXAMPLE
        $folders = Get-FoldersRecursive -RootPath "C:\Photos"
        
        Scannt alle Unterordner in C:\Photos
    
    .EXAMPLE
        $folders = Get-FoldersRecursive -RootPath "C:\Photos" -MaxDepth 3
        
        Scannt nur bis Tiefe 3
    
    .OUTPUTS
        PSCustomObject[]
        
        Gibt Array von Objekten zurück mit Eigenschaften:
        - Path: Vollständiger Pfad
        - Name: Ordnername
        - Depth: Tiefe im Verzeichnisbaum
        - Parent: Parent-Pfad
    
    .NOTES
        Verwendet Get-ChildItem -Recurse für Performance
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_ -PathType Container})]
        [string]$RootPath,
        
        [Parameter()]
        [int]$MaxDepth = [int]::MaxValue
    )
    
    try {
        Write-Verbose "Scanne Ordner rekursiv: $RootPath"
        
        $folders = @()
        $rootDepth = ($RootPath -replace '[^\\]', '').Length
        
        Get-ChildItem -LiteralPath $RootPath -Directory -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $currentDepth = (($_.FullName -replace '[^\\]', '').Length) - $rootDepth
            
            if ($currentDepth -le $MaxDepth) {
                $folders += [PSCustomObject]@{
                    Path   = $_.FullName
                    Name   = $_.Name
                    Depth  = $currentDepth
                    Parent = $_.Parent.FullName
                }
            }
        }
        
        Write-Verbose "Gefundene Ordner: $($folders.Count)"
        return $folders
    }
    catch {
        Write-Error "Fehler beim Scannen von '$RootPath': $_"
        throw
    }
}

# ============================================================================
# NATÜRLICHE SORTIERUNG
# ============================================================================

function Sort-FoldersNaturally {
    <#
    .SYNOPSIS
        Sortiert Ordner mit natürlicher Sortierung (numerisch-aware)
    
    .DESCRIPTION
        Sortiert Ordnernamen natürlich, sodass "Ordner 2" vor "Ordner 10" kommt.
        Berücksichtigt Zahlen in Dateinamen korrekt (nicht lexikalisch).
        
        Beispiel:
        - Lexikalisch: Ordner 1, Ordner 10, Ordner 2
        - Natürlich:   Ordner 1, Ordner 2, Ordner 10
    
    .PARAMETER Folders
        Array von Ordner-Objekten (aus Get-FoldersRecursive)
    
    .EXAMPLE
        $sorted = Sort-FoldersNaturally -Folders $folders
        
        Sortiert Ordner natürlich
    
    .EXAMPLE
        # Vorher: "Bild 1", "Bild 10", "Bild 2"
        # Nachher: "Bild 1", "Bild 2", "Bild 10"
    
    .OUTPUTS
        PSCustomObject[]
        
        Sortiertes Array von Ordner-Objekten
    
    .NOTES
        Verwendet Regex für Zahlen-Erkennung und Padding
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject[]]$Folders
    )
    
    begin {
        Write-Verbose "Sortiere Ordner natürlich"
        $allFolders = @()
    }
    
    process {
        $allFolders += $Folders
    }
    
    end {
        try {
            $sorted = $allFolders | Sort-Object -Property @{
                Expression = {
                    # Zahlen mit führenden Nullen auffüllen für korrekte Sortierung
                    [regex]::Replace($_.Name, '\d+', { 
                        param($match)
                        $match.Value.PadLeft(10, '0')
                    })
                }
            }
            
            Write-Verbose "Ordner sortiert: $($sorted.Count)"
            return $sorted
        }
        catch {
            Write-Error "Fehler beim Sortieren der Ordner: $_"
            throw
        }
    }
}

# ============================================================================
# DATEI-FILTERUNG
# ============================================================================

function Get-MediaFiles {
    <#
    .SYNOPSIS
        Gibt alle Bild- und Videodateien in einem Ordner zurück
    
    .DESCRIPTION
        Filtert Dateien nach unterstützten Bild- und Videoformaten.
        Gibt strukturierte Objekte mit Dateipfad und Typ zurück.
    
    .PARAMETER FolderPath
        Pfad zum zu scannenden Ordner
    
    .PARAMETER IncludeImages
        Bilddateien einschließen (Standard: true)
    
    .PARAMETER IncludeVideos
        Videodateien einschließen (Standard: true)
    
    .EXAMPLE
        $files = Get-MediaFiles -FolderPath "C:\Photos\Vacation"
        
        Gibt alle Bild- und Videodateien zurück
    
    .EXAMPLE
        $images = Get-MediaFiles -FolderPath $path -IncludeVideos:$false
        
        Nur Bilddateien
    
    .OUTPUTS
        PSCustomObject[]
        
        Array von Objekten mit Eigenschaften:
        - Path: Vollständiger Dateipfad
        - Name: Dateiname
        - Extension: Dateiendung
        - Type: 'Image' oder 'Video'
        - Size: Dateigröße in Bytes
    
    .NOTES
        Verwendet script:ImageExtensions und script:VideoExtensions
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_ -PathType Container})]
        [string]$FolderPath,
        
        [Parameter()]
        [bool]$IncludeImages = $true,
        
        [Parameter()]
        [bool]$IncludeVideos = $true
    )
    
    try {
        Write-Verbose "Scanne Media-Dateien: $FolderPath"
        
        $mediaFiles = @()
        
        Get-ChildItem -LiteralPath $FolderPath -File -ErrorAction SilentlyContinue | ForEach-Object {
            $extension = $_.Extension.ToLower()
            $type = $null
            
            if ($IncludeImages -and $extension -in $script:ImageExtensions) {
                $type = 'Image'
            }
            elseif ($IncludeVideos -and $extension -in $script:VideoExtensions) {
                $type = 'Video'
            }
            
            if ($type) {
                $mediaFiles += [PSCustomObject]@{
                    Path      = $_.FullName
                    Name      = $_.Name
                    Extension = $extension
                    Type      = $type
                    Size      = $_.Length
                }
            }
        }
        
        Write-Verbose "Gefundene Media-Dateien: $($mediaFiles.Count) ($($mediaFiles | Where-Object Type -eq 'Image' | Measure-Object | Select-Object -ExpandProperty Count) Bilder, $($mediaFiles | Where-Object Type -eq 'Video' | Measure-Object | Select-Object -ExpandProperty Count) Videos)"
        
        return $mediaFiles
    }
    catch {
        Write-Error "Fehler beim Scannen von Media-Dateien in '$FolderPath': $_"
        throw
    }
}

# ============================================================================
# ORDNER-STATISTIK
# ============================================================================

function Get-FolderStatistics {
    <#
    .SYNOPSIS
        Berechnet Statistiken für einen Ordner
    
    .DESCRIPTION
        Zählt Dateien nach Typ und berechnet Gesamtgröße.
        Gibt strukturiertes Statistik-Objekt zurück.
    
    .PARAMETER FolderPath
        Pfad zum zu analysierenden Ordner
    
    .EXAMPLE
        $stats = Get-FolderStatistics -FolderPath "C:\Photos\Vacation"
        
        Gibt zurück: @{ImageCount=42; VideoCount=5; TotalSize=1.2GB; ...}
    
    .OUTPUTS
        PSCustomObject
        
        Objekt mit Eigenschaften:
        - FolderPath: Analysierter Pfad
        - ImageCount: Anzahl Bilder
        - VideoCount: Anzahl Videos
        - TotalFiles: Gesamtanzahl Dateien
        - TotalSize: Gesamtgröße in Bytes
    
    .NOTES
        Verwendet Get-MediaFiles intern
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_ -PathType Container})]
        [string]$FolderPath
    )
    
    try {
        Write-Verbose "Berechne Statistiken für: $FolderPath"
        
        $mediaFiles = Get-MediaFiles -FolderPath $FolderPath
        $images = $mediaFiles | Where-Object Type -eq 'Image'
        $videos = $mediaFiles | Where-Object Type -eq 'Video'
        
        $stats = [PSCustomObject]@{
            FolderPath = $FolderPath
            ImageCount = $images.Count
            VideoCount = $videos.Count
            TotalFiles = $mediaFiles.Count
            TotalSize  = ($mediaFiles | Measure-Object -Property Size -Sum).Sum
        }
        
        Write-Verbose "Statistiken: $($stats.ImageCount) Bilder, $($stats.VideoCount) Videos, $([math]::Round($stats.TotalSize / 1MB, 2)) MB"
        
        return $stats
    }
    catch {
        Write-Error "Fehler beim Berechnen der Statistiken für '$FolderPath': $_"
        throw
    }
}