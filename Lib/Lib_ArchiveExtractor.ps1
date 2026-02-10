<#
ManifestHint:
  ExportFunctions = @("Invoke-ArchiveExtraction","Test-HasArchives")
  Description     = "Performance-optimierte rekursive Archive-Extraktion"
  Category        = "Media"
  Tags            = @("Archives","Extract","Performance","Recursive","Parallel")
  Dependencies    = @()

Zweck:
  - Schneller rekursiver Scan nach Archiven
  - Performance-optimiert für große Ordnerstrukturen
  - Integration in PhotoFolder
  - Parallel-Verarbeitung wenn PowerShell 7+
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Quick-Check: Archive vorhanden? (Rekursiv, aber fast)
# ------------------------------------------------------------
function Test-HasArchives {
  <#
  .SYNOPSIS
  Schneller rekursiver Check ob Archive vorhanden sind
  
  .PARAMETER RootPath
  Zu prüfender Ordner
  
  .PARAMETER QuickCheck
  Wenn $true, stoppt nach erstem Fund (schneller)
  
  .OUTPUTS
  PSCustomObject mit Count, HasArchives, TotalSize
  #>
  
  param(
    [Parameter(Mandatory)]
    [string]$RootPath,
    
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
  
  .PARAMETER RootPath
  Root-Ordner mit Archiven
  
  .PARAMETER Silent
  Wenn $true, keine Ausgaben
  
  .OUTPUTS
  PSCustomObject mit Success, ExtractedCount, FailedCount, Duration
  #>
  
  param(
    [Parameter(Mandatory)]
    [string]$RootPath,
    
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
  param([long]$Bytes)
  
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