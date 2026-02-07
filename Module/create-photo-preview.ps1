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
# Unterordner durchsuchen (Preview ausschließen) – LiteralPath!
# ------------------------------------------------------------
$allDirs = Get-ChildItem -LiteralPath $root -Directory -Recurse -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -ne $previewFolder }

Write-Host "Gefundene Unterordner: $($allDirs.Count)"

$copiedFiles = @()
$hitDirs = 0
$copyErrors = 0

foreach ($dir in $allDirs) {

    # Bilddateien im aktuellen Ordner – LiteralPath!
    $images = Get-ChildItem -LiteralPath $dir.FullName -File -ErrorAction SilentlyContinue |
              Where-Object {
                  $_.Extension -and
                  @(".jpg", ".jpeg", ".png") -contains $_.Extension.ToLowerInvariant()
              }

    if ($images.Count -eq 0) {
        continue
    }

    $hitDirs++

    # letzte 5 Bilder nach Dateiname (absteigend)
    $lastFive = $images | Sort-Object Name -Descending | Select-Object -First 5
    $selected = Get-Random -InputObject $lastFive

    # Zielname eindeutig machen
    $targetName = "{0}_{1}" -f $dir.Name, $selected.Name
    $targetPath = Join-Path $previewFolder $targetName

    # Kopieren – LiteralPath für Quelle; Ziel ist ein normaler Pfadstring
    try {
        Copy-Item -LiteralPath $selected.FullName -Destination $targetPath -Force -ErrorAction Stop

        # Nur zählen, wenn wirklich vorhanden
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
