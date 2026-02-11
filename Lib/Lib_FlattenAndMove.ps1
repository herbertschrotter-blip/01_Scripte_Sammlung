<#
ManifestHint:
  ExportFunctions = @("Invoke-FlattenAndMove")
  Description     = "Flatten verschachtelte Ordner-Strukturen und verschiebe zu neuem Ziel"
  Category        = "FileManagement"
  Tags            = @("Flatten","Move","Simplify","Structure")
  Dependencies    = @()

Zweck:
  - Vereinfacht verschachtelte Ordner-Strukturen
  - Root/Ebene1/Ebene2/Ebene3/*.jpg -> Ziel/Ebene3/*.jpg
  - Findet automatisch die tiefste Ebene mit Medien
  - Verschieben mit Duplikat-Handling und User-Confirmation
  
Workflow:
  1. Root-Ordner scannen nach Media-Ordnern (tiefste Ebene)
  2. Ziel-Ordner wählen via Dialog
  3. Flatten-Plan erstellen und Vorschau zeigen
  4. User Bestätigung einholen
  5. Verschieben mit Progress-Bar
  6. Duplikate: User fragen (Überschreiben/Umbenennen/Überspringen)
  7. Nach Verschieben: User fragen ob Root-Ordner löschen
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Extract-NumbersFromPath {
  param(
    [Parameter(Mandatory)]
    [string]$Path,
    
    [Parameter(Mandatory)]
    [string]$RootPath
  )
  
  # Relativen Pfad vom Root aus erstellen
  $relativePath = $Path.Substring($RootPath.Length).TrimStart('\')
  
  # Pfad in Ebenen aufteilen
  $levels = $relativePath -split '\\'
  
  # Alle Nummern sammeln (2-stellig mit führenden Nullen)
  $numbers = @()
  
  foreach ($level in $levels) {
    # Regex: Findet 2-stellige Zahlen (01, 02, 12, etc.)
    if ($level -match '\b(\d{2})\b') {
      $numbers += $matches[1]
    }
  }
  
  return $numbers
}

function Build-FlattenedName {
  param(
    [Parameter(Mandatory)]
    [string]$OriginalPath,
    
    [Parameter(Mandatory)]
    [string]$RootPath,
    
    [Parameter(Mandatory)]
    [string]$LeafName
  )
  
  # Nummern aus dem Pfad extrahieren
  $numbers = Extract-NumbersFromPath -Path $OriginalPath -RootPath $RootPath
  
  if ($numbers.Count -gt 0) {
    # Mit Nummern: 01_03_05_LeafName
    return ($numbers -join '_') + '_' + $LeafName
  } else {
    # Ohne Nummern: LeafName
    return $LeafName
  }
}

function Invoke-FlattenAndMove {
  param(
    [Parameter(Mandatory)]
    [string]$RootPath
  )
  
  if (-not (Test-Path $RootPath)) {
    Write-Error "Root-Pfad existiert nicht: $RootPath"
    return $null
  }
  
  Write-Host "`n════════════════════════════════════════" -ForegroundColor Cyan
  Write-Host " FLATTEN & MOVE - Ordner-Struktur vereinfachen" -ForegroundColor Cyan
  Write-Host "════════════════════════════════════════`n" -ForegroundColor Cyan
  
  Write-Host "Root: $RootPath" -ForegroundColor Yellow
  Write-Host "`nScanne nach Media-Ordnern (tiefste Ebene)...`n"
  
  # --- SCHRITT 1: Media-Ordner finden ---
  $mediaExtensions = @(
    # Bilder
    "*.jpg", "*.jpeg", "*.png", "*.gif", "*.bmp", "*.webp", "*.tiff", "*.tif",
    # Videos
    "*.mp4", "*.avi", "*.wmv", "*.mov", "*.mkv", "*.flv", "*.m4v", "*.mpg", "*.mpeg", "*.webm"
  )
  
  $mediaFolders = @()
  
  # Rekursiv alle Ordner durchgehen
  Get-ChildItem -Path $RootPath -Directory -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $folder = $_
    
    # Prüfe ob Ordner Medien enthält
    $hasMedia = $false
    foreach ($ext in $mediaExtensions) {
      if (Get-ChildItem -Path $folder.FullName -Filter $ext -File -ErrorAction SilentlyContinue | Select-Object -First 1) {
        $hasMedia = $true
        break
      }
    }
    
    # Prüfe ob .thumbs Ordner existiert
    $thumbsPath = Join-Path $folder.FullName ".thumbs"
    $hasThumbs = Test-Path $thumbsPath
    
    if ($hasMedia -or $hasThumbs) {
      # Prüfe ob Unterordner auch Medien haben
      $hasSubfolderWithMedia = $false
      Get-ChildItem -Path $folder.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $subfolder = $_
        foreach ($ext in $mediaExtensions) {
          if (Get-ChildItem -Path $subfolder.FullName -Filter $ext -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1) {
            $hasSubfolderWithMedia = $true
            break
          }
        }
      }
      
      # Nur wenn KEINE Unterordner mit Medien -> Das ist die tiefste Ebene
      if (-not $hasSubfolderWithMedia) {
        $relativePath = $folder.FullName.Substring($RootPath.Length).TrimStart('\')
        
        $mediaFolders += [PSCustomObject]@{
          FullPath = $folder.FullName
          FolderName = $folder.Name
          RelativePath = $relativePath
          Level = ($relativePath -split '\\').Count
        }
        
        Write-Host "  ✓ $relativePath" -ForegroundColor Green
      }
    }
  }
  
  if ($mediaFolders.Count -eq 0) {
    Write-Host "`n⚠️  Keine Media-Ordner gefunden!" -ForegroundColor Yellow
    return $null
  }
  
  Write-Host "`nGefunden: $($mediaFolders.Count) Media-Ordner" -ForegroundColor Cyan
  
  # --- SCHRITT 2: Ziel-Ordner wählen ---
  Write-Host "`nZiel-Ordner wählen...`n"
  
  Add-Type -AssemblyName System.Windows.Forms
  $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
  $dialog.Description = "Ziel-Ordner für geflattete Struktur wählen"
  $dialog.ShowNewFolderButton = $true
  
  if ($dialog.ShowDialog() -ne "OK") {
    Write-Host "Abgebrochen." -ForegroundColor Yellow
    return $null
  }
  
  $targetRoot = $dialog.SelectedPath
  Write-Host "Ziel: $targetRoot`n" -ForegroundColor Yellow
  
  # --- SCHRITT 3: Plan erstellen & Vorschau ---
  Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
  Write-Host " VORSCHAU: Verschiebe-Plan" -ForegroundColor Cyan
  Write-Host "════════════════════════════════════════`n" -ForegroundColor Cyan
  
  $moveOperations = @()
  
  foreach ($folder in $mediaFolders) {
    # Root-Name (gewählter Ordner)
    $rootName = Split-Path -Leaf $RootPath
    
    # Neuer Ordnername mit extrahierten Nummern
    $flattenedName = Build-FlattenedName -OriginalPath $folder.FullPath -RootPath $RootPath -LeafName $folder.FolderName
    
    # Ziel: Archive\RootName\FlattenedName
    $targetRootFolder = Join-Path $targetRoot $rootName
    $targetPath = Join-Path $targetRootFolder $flattenedName
    
    $moveOperations += [PSCustomObject]@{
      Source = $folder.FullPath
      Target = $targetPath
      FolderName = $flattenedName
      Exists = Test-Path $targetPath
    }
    
    $statusIcon = if (Test-Path $targetPath) { "⚠️ " } else { "✓ " }
    $statusColor = if (Test-Path $targetPath) { "Yellow" } else { "Green" }
    
    Write-Host "$statusIcon $($folder.RelativePath)" -ForegroundColor $statusColor
    Write-Host "   → $targetPath`n" -ForegroundColor Gray
  }
  
  # --- SCHRITT 4: User Bestätigung ---
  Write-Host "════════════════════════════════════════`n" -ForegroundColor Cyan
  
  $duplicates = ($moveOperations | Where-Object { $_.Exists }).Count
  if ($duplicates -gt 0) {
    Write-Host "⚠️  $duplicates Duplikate gefunden - Sie werden beim Verschieben gefragt!" -ForegroundColor Yellow
  }
  
  $confirm = Read-Host "`n$($moveOperations.Count) Ordner verschieben? (J/N)"
  if ($confirm -ne "J") {
    Write-Host "Abgebrochen." -ForegroundColor Yellow
    return $null
  }
  
  # Root-Ordner im Ziel erstellen
  $rootName = Split-Path -Leaf $RootPath
  $targetRootFolder = Join-Path $targetRoot $rootName
  
  if (-not (Test-Path -LiteralPath $targetRootFolder)) {
    New-Item -Path $targetRootFolder -ItemType Directory -Force | Out-Null
    Write-Host "Erstellt: $targetRootFolder`n" -ForegroundColor Green
  }
  
  # --- SCHRITT 5: Verschieben mit Progress ---
  Write-Host "`n════════════════════════════════════════" -ForegroundColor Cyan
  Write-Host " VERSCHIEBE..." -ForegroundColor Cyan
  Write-Host "════════════════════════════════════════`n" -ForegroundColor Cyan
  
  $current = 0
  $total = $moveOperations.Count
  $movedCount = 0
  $skippedCount = 0
  
  foreach ($op in $moveOperations) {
    $current++
    $percent = [math]::Round(($current / $total) * 100)
    
    Write-Host "[$current/$total] $($op.FolderName)..." -NoNewline
    
    # Duplikat-Handling
    if ($op.Exists) {
      Write-Host " [DUPLIKAT]" -ForegroundColor Yellow
      Write-Host "`nOrdner existiert bereits: $($op.Target)" -ForegroundColor Yellow
      Write-Host "1) Überschreiben (Ziel löschen, dann verschieben)"
      Write-Host "2) Umbenennen (zu '$($op.FolderName)_2')"
      Write-Host "3) Überspringen"
      
      $choice = Read-Host "`nAuswahl (1/2/3)"
      
      switch ($choice) {
        "1" {
          # Überschreiben
          Remove-Item -Path $op.Target -Recurse -Force -ErrorAction Stop
          Move-Item -Path $op.Source -Destination $op.Target -Force -ErrorAction Stop
          Write-Host "  ✓ Überschrieben" -ForegroundColor Green
          $movedCount++
        }
        "2" {
          # Umbenennen
          $newName = $op.FolderName
          $counter = 2
          $targetRootFolder = Split-Path -Parent $op.Target
          while (Test-Path (Join-Path $targetRootFolder "${newName}_${counter}")) {
            $counter++
          }
          $newTarget = Join-Path $targetRootFolder "${newName}_${counter}"
          Move-Item -Path $op.Source -Destination $newTarget -Force -ErrorAction Stop
          Write-Host "  ✓ Umbenannt zu: ${newName}_${counter}" -ForegroundColor Green
          $movedCount++
        }
        "3" {
          # Überspringen
          Write-Host "  ⊘ Übersprungen" -ForegroundColor Gray
          $skippedCount++
        }
        default {
          Write-Host "  ⊘ Ungültige Eingabe - Übersprungen" -ForegroundColor Gray
          $skippedCount++
        }
      }
    } else {
      # Kein Duplikat - Normal verschieben
      Move-Item -Path $op.Source -Destination $op.Target -Force -ErrorAction Stop
      Write-Host " ✓" -ForegroundColor Green
      $movedCount++
    }
  }
  
  # --- SCHRITT 6: Zusammenfassung ---
  Write-Host "`n════════════════════════════════════════" -ForegroundColor Cyan
  Write-Host " FERTIG!" -ForegroundColor Cyan
  Write-Host "════════════════════════════════════════`n" -ForegroundColor Cyan
  
  Write-Host "Verschoben: $movedCount" -ForegroundColor Green
  if ($skippedCount -gt 0) {
    Write-Host "Übersprungen: $skippedCount" -ForegroundColor Yellow
  }
  
  # --- SCHRITT 7: Root-Ordner löschen? ---
  Write-Host ""
  $deleteRoot = Read-Host "Root-Ordner '$RootPath' jetzt löschen? (J/N)"
  
  if ($deleteRoot -eq "J") {
    Write-Host "`nLösche Root-Ordner..." -NoNewline
    Remove-Item -Path $RootPath -Recurse -Force -ErrorAction Stop
    Write-Host " ✓" -ForegroundColor Green
    Write-Host "`n✅ Root-Ordner gelöscht!" -ForegroundColor Green
  } else {
    Write-Host "`n⚠️  Root-Ordner wurde NICHT gelöscht." -ForegroundColor Yellow
    Write-Host "Pfad: $RootPath" -ForegroundColor Gray
  }
  
  Write-Host "`n✅ Flatten & Move abgeschlossen!`n" -ForegroundColor Green
  
  # Return-Wert für API
  return [PSCustomObject]@{
    MovedCount = $movedCount
    SkippedCount = $skippedCount
    RootDeleted = ($deleteRoot -eq "J")
  }
}