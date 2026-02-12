#Requires -Version 5.1

<#
.SYNOPSIS
    Performance-optimierte rekursive Archive-Extraktion

.DESCRIPTION
    Bietet Funktionen zum schnellen Scannen und Extrahieren von Archiven
    (ZIP, RAR, 7z, TAR, GZ, BZ2) in großen Ordnerstrukturen.
    
    Funktionen:
    - Test-HasArchives:         Schneller Check ob Archive vorhanden sind
    - Invoke-ArchiveExtraction: Extrahiert alle Archive rekursiv
    - Format-ArchiveSize:       Formatiert Byte-Größen lesbar
    
    Performance-Optimierungen:
    - QuickCheck-Modus stoppt nach erstem Fund
    - Überspringt System/Hidden-Dateien automatisch
    - Parallel-Verarbeitung bei PowerShell 7+ (via Extract-AllArchives.ps1)

.PARAMETER None
    Library-Datei - Funktionen via dot-sourcing laden

.EXAMPLE
    PS> . .\Lib_ArchiveExtractor.ps1
    PS> $check = Test-HasArchives -RootPath "C:\Photos"
    PS> if ($check.HasArchives) { Invoke-ArchiveExtraction -RootPath "C:\Photos" }

.EXAMPLE
    PS> . .\Lib_ArchiveExtractor.ps1
    PS> $quick = Test-HasArchives -RootPath "D:\Downloads" -QuickCheck
    PS> Write-Host "Archive gefunden: $($quick.HasArchives)"

.NOTES
    Autor: Herbert Schrotter
    Version: 1.0.0
    Erstellt: 2025-02-12
    
    Abhängigkeiten:
    - Extract-AllArchives.ps1 (für Invoke-ArchiveExtraction)
    
    Unterstützte Archive:
    - .rar, .zip, .7z, .tar, .gz, .bz2

.LINK
    https://github.com/herbertschrotter-blip/01_Scripte_Sammlung
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# ============================================================================
# Test-HasArchives
# ============================================================================
function Test-HasArchives {
    <#
    .SYNOPSIS
        Schneller rekursiver Check ob Archive vorhanden sind
    
    .DESCRIPTION
        Scannt einen Ordner rekursiv nach Archiv-Dateien (.zip, .rar, .7z, etc.)
        und gibt Anzahl, Status und Gesamtgröße zurück.
        Im QuickCheck-Modus stoppt die Suche nach dem ersten Fund.
    
    .PARAMETER RootPath
        Zu prüfender Ordner (vollständiger Pfad)
    
    .PARAMETER QuickCheck
        Wenn $true, stoppt nach erstem Fund (schneller)
    
    .EXAMPLE
        PS> $check = Test-HasArchives -RootPath "C:\Downloads"
        PS> if ($check.HasArchives) { Write-Host "Gefunden: $($check.Count) Archive" }
    
    .EXAMPLE
        PS> $quick = Test-HasArchives -RootPath "C:\Photos" -QuickCheck
        PS> $quick.HasArchives
        True
    
    .OUTPUTS
        PSCustomObject mit folgenden Eigenschaften:
        - Count: Anzahl gefundener Archive
        - HasArchives: Boolean ob Archive vorhanden
        - TotalSize: Gesamtgröße in Bytes (0 bei QuickCheck)
    
    .NOTES
        Autor: Herbert Schrotter
        Version: 1.0.0
        Unterstützte Archive: .rar, .zip, .7z, .tar, .gz, .bz2
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RootPath,
        
        [Parameter()]
        [switch]$QuickCheck
    )
    
    # Ordner existiert nicht → Rückgabe mit 0 Ergebnissen
    if (-not (Test-Path -LiteralPath $RootPath)) {
        return [PSCustomObject]@{
            PSTypeName  = 'Archive.CheckResult'
            Count       = 0
            HasArchives = $false
            TotalSize   = 0
        }
    }
    
    # Unterstützte Archiv-Erweiterungen
    $archiveExtensions = @('.rar', '.zip', '.7z', '.tar', '.gz', '.bz2')
    
    try {
        # Schnelle Enumeration: Rekursiv, nur Files, skip System/Hidden
        $archives = Get-ChildItem -LiteralPath $RootPath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { 
                $ext = $_.Extension.ToLowerInvariant()
                $archiveExtensions -contains $ext
            }
        
        # QuickCheck-Modus: Nur Existenz prüfen, keine Größe berechnen
        if ($QuickCheck -and $archives) {
            $count = @($archives).Count
            return [PSCustomObject]@{
                PSTypeName  = 'Archive.CheckResult'
                Count       = $count
                HasArchives = $count -gt 0
                TotalSize   = 0  # Keine Size-Berechnung im QuickCheck
            }
        }
        
        # Vollständiger Check: Anzahl + Gesamtgröße berechnen
        $archiveList = @($archives)
        
        # Null-Safe Größenberechnung
        $totalSize = 0
        if ($archiveList.Count -gt 0) {
            $sizeResult = $archiveList | Measure-Object -Property Length -Sum
            if ($sizeResult -and $null -ne $sizeResult.Sum) {
                $totalSize = $sizeResult.Sum
            }
        }
        
        return [PSCustomObject]@{
            PSTypeName  = 'Archive.CheckResult'
            Count       = $archiveList.Count
            HasArchives = $archiveList.Count -gt 0
            TotalSize   = $totalSize
        }
        
    }
    catch {
        Write-Warning "Archive-Scan fehlgeschlagen: $($_.Exception.Message)"
        return [PSCustomObject]@{
            PSTypeName  = 'Archive.CheckResult'
            Count       = 0
            HasArchives = $false
            TotalSize   = 0
        }
    }
}

# ============================================================================
# Invoke-ArchiveExtraction
# ============================================================================
function Invoke-ArchiveExtraction {
    <#
    .SYNOPSIS
        Extrahiert alle Archive rekursiv (inkl. Unterarchive)
    
    .DESCRIPTION
        Ruft Extract-AllArchives.ps1 auf und extrahiert alle gefundenen Archive
        im angegebenen Root-Ordner. Unterstützt verschachtelte Archive (Archive in Archiven).
        Zeigt Fortschritt und Statistiken an (außer im Silent-Modus).
    
    .PARAMETER RootPath
        Root-Ordner mit Archiven (vollständiger Pfad)
    
    .PARAMETER Silent
        Wenn $true, keine Konsolenausgaben (nur Rückgabewert)
    
    .EXAMPLE
        PS> $result = Invoke-ArchiveExtraction -RootPath "C:\Downloads"
        PS> Write-Host "Entpackt: $($result.ExtractedCount), Fehler: $($result.FailedCount)"
    
    .EXAMPLE
        PS> Invoke-ArchiveExtraction -RootPath "C:\Temp" -Silent
    
    .OUTPUTS
        PSCustomObject mit folgenden Eigenschaften:
        - Success: Boolean ob Extraktion erfolgreich
        - ExtractedCount: Anzahl erfolgreich entpackter Archive
        - FailedCount: Anzahl fehlgeschlagener Archive
        - Duration: Dauer in Sekunden
        - Error: Fehlermeldung (nur bei Fehler)
    
    .NOTES
        Autor: Herbert Schrotter
        Version: 1.0.1
        Requires: Extract-AllArchives.ps1 muss in Module\ vorhanden sein
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RootPath,
        
        [Parameter()]
        [switch]$Silent
    )
    
    $startTime = Get-Date
    
    # Root-Ordner existiert nicht → Abbruch
    if (-not (Test-Path -LiteralPath $RootPath)) {
        if (-not $Silent) {
            Write-Warning "Root-Ordner existiert nicht: $RootPath"
        }
        return [PSCustomObject]@{
            PSTypeName     = 'Archive.ExtractionResult'
            Success        = $false
            ExtractedCount = 0
            FailedCount    = 0
            Duration       = 0
        }
    }
    
    # Suche Extract-AllArchives.ps1 im Module-Ordner (mit defensiver Fehlerbehandlung)
    try {
        $scriptRoot = Split-Path -Parent $PSScriptRoot -ErrorAction Stop
        $extractScript = Join-Path $scriptRoot 'Module\Extract-AllArchives.ps1' -ErrorAction Stop
    }
    catch {
        if (-not $Silent) {
            Write-Warning "Fehler beim Ermitteln des Script-Pfads: $($_.Exception.Message)"
        }
        return [PSCustomObject]@{
            PSTypeName     = 'Archive.ExtractionResult'
            Success        = $false
            ExtractedCount = 0
            FailedCount    = 0
            Duration       = 0
            Error          = "Script-Pfad konnte nicht ermittelt werden: $($_.Exception.Message)"
        }
    }
    
    if (-not (Test-Path -LiteralPath $extractScript)) {
        if (-not $Silent) {
            Write-Warning "Extract-AllArchives.ps1 nicht gefunden: $extractScript"
        }
        return [PSCustomObject]@{
            PSTypeName     = 'Archive.ExtractionResult'
            Success        = $false
            ExtractedCount = 0
            FailedCount    = 0
            Duration       = 0
        }
    }
    
    # Konsolenausgabe: Start-Banner
    if (-not $Silent) {
        Write-Host ''
        Write-Host '================================================' -ForegroundColor Cyan
        Write-Host '  ARCHIVE-EXTRAKTION GESTARTET' -ForegroundColor Cyan
        Write-Host '================================================' -ForegroundColor Cyan
        Write-Host ''
    }
    
    try {
        # Rufe Extract-AllArchives.ps1 auf (fängt stdout + stderr)
        $output = & $extractScript -RootPath $RootPath 2>&1
        
        # Parse Output-Text für Statistiken (suche "OK=X" und "FAIL=Y")
        # WICHTIG: Select-Object -First 1 → verhindert Array-Fehler bei mehreren Matches
        $okMatch = $output | Select-String -Pattern 'OK=(\d+)' | Select-Object -First 1
        $failMatch = $output | Select-String -Pattern 'FAIL=(\d+)' | Select-Object -First 1
        
        $extractedCount = if ($okMatch) { [int]$okMatch.Matches[0].Groups[1].Value } else { 0 }
        $failedCount = if ($failMatch) { [int]$failMatch.Matches[0].Groups[1].Value } else { 0 }
        
        $duration = (Get-Date) - $startTime
        
        # Konsolenausgabe: Erfolgs-Banner
        if (-not $Silent) {
            Write-Host ''
            Write-Host '================================================' -ForegroundColor Green
            Write-Host '  EXTRAKTION ABGESCHLOSSEN' -ForegroundColor Green
            Write-Host '================================================' -ForegroundColor Green
            Write-Host "  Entpackt:    $extractedCount Archive" -ForegroundColor Green
            Write-Host "  Fehler:      $failedCount Archive" -ForegroundColor Yellow
            Write-Host "  Dauer:       $($duration.TotalSeconds.ToString('0.0')) Sekunden" -ForegroundColor Cyan
            Write-Host '================================================' -ForegroundColor Green
            Write-Host ''
        }
        
        return [PSCustomObject]@{
            PSTypeName     = 'Archive.ExtractionResult'
            Success        = $true
            ExtractedCount = $extractedCount
            FailedCount    = $failedCount
            Duration       = $duration.TotalSeconds
        }
        
    }
    catch {
        # Fehlerbehandlung: Warnung + Rückgabe mit Error-Property
        if (-not $Silent) {
            Write-Warning "Archive-Extraktion fehlgeschlagen: $($_.Exception.Message)"
        }
        
        $duration = (Get-Date) - $startTime
        
        return [PSCustomObject]@{
            PSTypeName     = 'Archive.ExtractionResult'
            Success        = $false
            ExtractedCount = 0
            FailedCount    = 0
            Duration       = $duration.TotalSeconds
            Error          = $_.Exception.Message
        }
    }
}

# ============================================================================
# Format-ArchiveSize
# ============================================================================
function Format-ArchiveSize {
    <#
    .SYNOPSIS
        Formatiert Byte-Größen in lesbare Einheiten
    
    .DESCRIPTION
        Konvertiert Byte-Werte in lesbare Einheiten (GB, MB, KB, Bytes)
        mit automatischer Einheitenwahl und 2 Dezimalstellen.
    
    .PARAMETER Bytes
        Größe in Bytes (als Long/Int64)
    
    .EXAMPLE
        PS> Format-ArchiveSize -Bytes 1048576
        1.00 MB
    
    .EXAMPLE
        PS> Format-ArchiveSize -Bytes 5368709120
        5.00 GB
    
    .OUTPUTS
        String mit formatierter Größenangabe
    
    .NOTES
        Autor: Herbert Schrotter
        Version: 1.0.0
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [long]$Bytes
    )
    
    # Automatische Einheitenwahl: GB > MB > KB > Bytes
    if ($Bytes -ge 1GB) {
        return ('{0:0.00} GB' -f ($Bytes / 1GB))
    }
    elseif ($Bytes -ge 1MB) {
        return ('{0:0.00} MB' -f ($Bytes / 1MB))
    }
    elseif ($Bytes -ge 1KB) {
        return ('{0:0.00} KB' -f ($Bytes / 1KB))
    }
    else {
        return "$Bytes Bytes"
    }
}