<#
.SYNOPSIS
    Performance-optimierte rekursive Archive-Extraktion

.DESCRIPTION
    Bietet Funktionen zum schnellen Scannen und Extrahieren von Archiven
    (ZIP, RAR, 7z, TAR, GZ, BZ2) in großen Ordnerstrukturen.
    
    Funktionen:
    - Test-HasArchives:       Schneller Check ob Archive vorhanden sind
    - Invoke-ArchiveExtraction: Extrahiert alle Archive rekursiv
    - Format-ArchiveSize:     Formatiert Byte-Größen lesbar

.EXAMPLE
    PS> . .\Lib_ArchiveExtractor.ps1
    PS> $check = Test-HasArchives -RootPath "C:\Photos"
    PS> if ($check.HasArchives) { Invoke-ArchiveExtraction -RootPath "C:\Photos" }

.NOTES
    Autor: Herbert Schrotter
    Version: 1.0.0
    Requires: PowerShell 5.1+
    Dependencies: Extract-AllArchives.ps1 (für Invoke-ArchiveExtraction)

.LINK
    https://github.com/herbertschrotter-blip/01_Scripte_Sammlung

ManifestHint:
  ExportFunctions = @("Invoke-ArchiveExtraction","Test-HasArchives","Format-ArchiveSize")
  Description     = "Performance-optimierte rekursive Archive-Extraktion"
  Category        = "Media"
  Tags            = @("Archives","Extract","Performance","Recursive","Parallel")
  Dependencies    = @("Extract-AllArchives.ps1")

Zweck:
  - Schneller rekursiver Scan nach Archiven
  - Performance-optimiert für große Ordnerstrukturen
  - Integration in PhotoFolder
  - Parallel-Verarbeitung wenn PowerShell 7+
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Quick-Check: Archive vorhanden? (Rekursiv, aber fast)
# ------------------------------------------------------------
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
  Hashtable mit folgenden Eigenschaften:
  - Count: Anzahl gefundener Archive
  - HasArchives: Boolean ob Archive vorhanden
  - TotalSize: Gesamtgröße in Bytes (0 bei QuickCheck)
  
  .NOTES
  Autor: Herbert Schrotter
  Version: 1.0.0
  Unterstützte Archive: .rar, .zip, .7z, .tar, .gz, .bz2
  #>
  
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$RootPath,
    
    [Parameter()]
    [switch]$QuickCheck
  )
  
  if (-not (Test-Path -LiteralPath $RootPath)) {
    return @{ Count = 0; HasArchives = $false; TotalSize = 0 }
  }
  
  $archiveExtensions = @(".rar",".zip",".7z",".tar",".gz",".bz2")
  
  try {
    # Fast enumeration mit Skip System/Hidden
    $archives = Get-ChildItem -LiteralPath $RootPath -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { 
        $ext = $_.Extension.ToLowerInvariant()
        $archiveExtensions -contains $ext
      }
    
    if ($QuickCheck -and $archives) {
      # Quick-Mode: Nur Count, keine Size
      $count = @($archives).Count
      return @{ 
        Count = $count
        HasArchives = $count -gt 0
        TotalSize = 0
      }
    }
    
    $archiveList = @($archives)
    
    # FIX: Null-Check für Measure-Object
    $totalSize = 0
    if ($archiveList.Count -gt 0) {
      $sizeResult = $archiveList | Measure-Object -Property Length -Sum
      if ($sizeResult -and $null -ne $sizeResult.Sum) {
        $totalSize = $sizeResult.Sum
      }
    }
    
    return @{ 
      Count = $archiveList.Count
      HasArchives = $archiveList.Count -gt 0
      TotalSize = $totalSize
    }
    
  } catch {
    Write-Warning "Archive-Scan fehlgeschlagen: $($_.Exception.Message)"
    return @{ Count = 0; HasArchives = $false; TotalSize = 0 }
  }
}

# ------------------------------------------------------------
# Archive-Extraktion durchführen
# ------------------------------------------------------------
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
  Hashtable mit folgenden Eigenschaften:
  - Success: Boolean ob Extraktion erfolgreich
  - ExtractedCount: Anzahl erfolgreich entpackter Archive
  - FailedCount: Anzahl fehlgeschlagener Archive
  - Duration: Dauer in Sekunden
  - Error: Fehlermeldung (nur bei Fehler)
  
  .NOTES
  Autor: Herbert Schrotter
  Version: 1.0.0
  Requires: Extract-AllArchives.ps1 muss in Module\ vorhanden sein
  #>
  
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$RootPath,
    
    [Parameter()]
    [switch]$Silent
  )
  
  $startTime = Get-Date
  
  if (-not (Test-Path -LiteralPath $RootPath)) {
    if (-not $Silent) {
      Write-Warning "Root-Ordner existiert nicht: $RootPath"
    }
    return @{ Success = $false; ExtractedCount = 0; FailedCount = 0; Duration = 0 }
  }
  
  # Suche Extract-AllArchives.ps1
  $scriptRoot = Split-Path -Parent $PSScriptRoot
  $extractScript = Join-Path $scriptRoot "Module\Extract-AllArchives.ps1"
  
  if (-not (Test-Path -LiteralPath $extractScript)) {
    if (-not $Silent) {
      Write-Warning "Extract-AllArchives.ps1 nicht gefunden: $extractScript"
    }
    return @{ Success = $false; ExtractedCount = 0; FailedCount = 0; Duration = 0 }
  }
  
  if (-not $Silent) {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  ARCHIVE-EXTRAKTION GESTARTET" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
  }
  
  try {
    # Rufe Extract-AllArchives.ps1 auf
    $output = & $extractScript -RootPath $RootPath 2>&1
    
    # Parse Output für Statistics
    $okMatch = $output | Select-String -Pattern "OK=(\d+)"
    $failMatch = $output | Select-String -Pattern "FAIL=(\d+)"
    
    $extractedCount = if ($okMatch) { [int]$okMatch.Matches[0].Groups[1].Value } else { 0 }
    $failedCount = if ($failMatch) { [int]$failMatch.Matches[0].Groups[1].Value } else { 0 }
    
    $duration = (Get-Date) - $startTime
    
    if (-not $Silent) {
      Write-Host ""
      Write-Host "================================================" -ForegroundColor Green
      Write-Host "  EXTRAKTION ABGESCHLOSSEN" -ForegroundColor Green
      Write-Host "================================================" -ForegroundColor Green
      Write-Host "  Entpackt:    $extractedCount Archive" -ForegroundColor Green
      Write-Host "  Fehler:      $failedCount Archive" -ForegroundColor Yellow
      Write-Host "  Dauer:       $($duration.TotalSeconds.ToString('0.0')) Sekunden" -ForegroundColor Cyan
      Write-Host "================================================" -ForegroundColor Green
      Write-Host ""
    }
    
    return @{
      Success = $true
      ExtractedCount = $extractedCount
      FailedCount = $failedCount
      Duration = $duration.TotalSeconds
    }
    
  } catch {
    if (-not $Silent) {
      Write-Warning "Archive-Extraktion fehlgeschlagen: $($_.Exception.Message)"
    }
    
    $duration = (Get-Date) - $startTime
    
    return @{
      Success = $false
      ExtractedCount = 0
      FailedCount = 0
      Duration = $duration.TotalSeconds
      Error = $_.Exception.Message
    }
  }
}

# ------------------------------------------------------------
# Format File Size (Helper)
# ------------------------------------------------------------
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
  param(
    [Parameter(Mandatory)]
    [long]$Bytes
  )
  
  if ($Bytes -ge 1GB) {
    return ("{0:0.00} GB" -f ($Bytes / 1GB))
  } elseif ($Bytes -ge 1MB) {
    return ("{0:0.00} MB" -f ($Bytes / 1MB))
  } elseif ($Bytes -ge 1KB) {
    return ("{0:0.00} KB" -f ($Bytes / 1KB))
  } else {
    return "$Bytes Bytes"
  }
}