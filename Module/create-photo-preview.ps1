# create-photo-preview.ps1
# Zweck: Erstellt einen 00_Preview-Ordner und kopiert je Unterordner 1 Zufallsbild
#        aus den letzten 5 Bildern (nach Dateiname sortiert)
# Hinweis: Preview-Ordner wird vorab geleert, Originale bleiben unverändert
# Param:   -RootPath (optional) → Root-Ordner ohne Dialog verwenden

param (
    [string]$RootPath
)

# ------------------------------------------------------------
# Root-Ordner bestimmen (Dialog nur wenn nicht übergeben)
# ------------------------------------------------------------
if (-not $RootPath) {
    Add-Type -AssemblyName System.Windows.Forms

    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Root-Ordner auswählen"

    if ($dlg.ShowDialog() -ne "OK") {
        Write-Host "Abgebrochen."
        return
    }

    $root = $dlg.SelectedPath
}
else {
    $root = $RootPath
}

Write-Host "`nRoot-Ordner:`n$root"

# ------------------------------------------------------------
# Preview-Ordner vorbereiten (LiteralPath wegen [PHOTOS])
# ------------------------------------------------------------
$previewFolder = Join-Path $root "00_Preview"

if (Test-Path -LiteralPath $previewFolder) {
    Write-Host "Preview-Ordner existiert – wird geleert."
    Get-ChildItem -LiteralPath $previewFolder -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}
else {
    New-Item -ItemType Directory -Path $previewFolder -Force | Out-Null
    Write-Host "Preview-Ordner erstellt: 00_Preview"
}

# ------------------------------------------------------------
# Unterordner durchsuchen: pro Hauptordner nur tiefste Ebene mit Bildern
# ------------------------------------------------------------
$topDirs = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -ne $previewFolder }

Write-Host "Gefundene Hauptordner: $($topDirs.Count)"

$copiedFiles = @()
$hitDirs = 0
$copyErrors = 0

foreach ($top in $topDirs) {

    # Alle Unterordner inkl. Hauptordner selbst
    $dirs = @($top) + @(Get-ChildItem -LiteralPath $top.FullName -Directory -Recurse -ErrorAction SilentlyContinue)

    # Kandidaten: Ordner, die Bilder enthalten
    $candidates = foreach ($d in $dirs) {
        $imgs = Get-ChildItem -LiteralPath $d.FullName -File -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Extension -and
                    @(".jpg", ".jpeg", ".png") -contains $_.Extension.ToLowerInvariant()
                }

        if ($imgs -and $imgs.Count -gt 0) {
            # Tiefe relativ zum Hauptordner bestimmen
            $rel = $d.FullName.Substring($top.FullName.Length).Trim('\')
            $depth = 0
            if ($rel) { $depth = ($rel -split '\\').Count }

            [pscustomobject]@{
                Dir    = $d
                Depth  = $depth
                Images = $imgs
            }
        }
    }

    if (-not $candidates -or $candidates.Count -eq 0) {
        continue
    }

    # Tiefste Ebene (max Depth)
    $maxDepth = ($candidates | Measure-Object -Property Depth -Maximum).Maximum
    $deepest  = $candidates | Where-Object { $_.Depth -eq $maxDepth }

    # Aus tiefsten Ordnern zufällig einen wählen
    $pickDirObj = Get-Random -InputObject $deepest
    $images = $pickDirObj.Images
    $dir    = $pickDirObj.Dir

    $hitDirs++

    # letzte 5 Bilder nach Dateiname (absteigend)
    $lastFive = $images | Sort-Object Name -Descending | Select-Object -First 5
    $selected = Get-Random -InputObject $lastFive

    # Zielname eindeutig machen (TopOrdner + TiefOrdner + Datei)
    $targetName = "{0}_{1}_{2}" -f $top.Name, $dir.Name, $selected.Name
    $targetPath = Join-Path $previewFolder $targetName

    try {
        Copy-Item -LiteralPath $selected.FullName -Destination $targetPath -Force -ErrorAction Stop

        if (Test-Path -LiteralPath $targetPath) {
            $copiedFiles += $targetName
        }
        else {
            $copyErrors++
            Write-Host "WARN: Kopie nicht auffindbar: $targetPath"
        }
    }
    catch {
        $copyErrors++
        Write-Host "FEHLER beim Kopieren: $($_.Exception.Message)"
        Write-Host "Quelle: $($selected.FullName)"
        Write-Host "Ziel:   $targetPath"
    }
}

# ------------------------------------------------------------
# Reale Kontrolle: Was liegt wirklich im Preview-Ordner?
# ------------------------------------------------------------
$actualPreviewFiles = Get-ChildItem -LiteralPath $previewFolder -File -ErrorAction SilentlyContinue

# ------------------------------------------------------------
# Zusammenfassung
# ------------------------------------------------------------
Write-Host "`nFertig."
Write-Host "Ordner mit Bildern: $hitDirs"
Write-Host "Anzahl kopierter Bilder (gezählt): $($copiedFiles.Count)"
Write-Host "Anzahl Dateien im Preview-Ordner (real): $($actualPreviewFiles.Count)"
Write-Host "Kopierfehler: $copyErrors"

if ($actualPreviewFiles.Count -gt 0) {
    Write-Host "`nPreview-Dateien (real):"
    $actualPreviewFiles | Sort-Object Name | ForEach-Object { Write-Host " - $($_.Name)" }
}
