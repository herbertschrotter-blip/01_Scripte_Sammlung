# create-photo-preview.ps1
# Zweck: Erstellt einen 00_Preview-Ordner mit je einem Zufallsfoto
#        aus den letzten 5 Bildern (nach Dateiname sortiert) jedes Bild-Ordners
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
# Preview-Ordner vorbereiten
# ------------------------------------------------------------
$previewFolder = Join-Path $root "00_Preview"

if (Test-Path $previewFolder) {
    Write-Host "Preview-Ordner existiert – wird geleert."
    Get-ChildItem -Path $previewFolder -File | Remove-Item -Force
}
else {
    New-Item -ItemType Directory -Path $previewFolder | Out-Null
    Write-Host "Preview-Ordner erstellt: 00_Preview"
}

# ------------------------------------------------------------
# Unterordner durchsuchen (Preview ausschließen)
# ------------------------------------------------------------
$allDirs = Get-ChildItem -Path $root -Directory -Recurse |
           Where-Object { $_.FullName -ne $previewFolder }

$copiedFiles = @()

foreach ($dir in $allDirs) {

    # Bilddateien im aktuellen Ordner
    $images = Get-ChildItem -Path $dir.FullName -File |
              Where-Object { $_.Extension -match '\.(jpg|jpeg|png)$' }

    if ($images.Count -eq 0) {
        continue
    }

    # letzte 5 Bilder nach DATEINAME (absteigend)
    $lastFive = $images |
                Sort-Object Name -Descending |
                Select-Object -First 5

    # zufälliges Bild auswählen
    $selected = Get-Random -InputObject $lastFive

    # Zielname eindeutig machen
    $targetName = "{0}_{1}" -f $dir.Name, $selected.Name
    $targetPath = Join-Path $previewFolder $targetName

    # NUR KOPIEREN (Original bleibt unverändert)
    Copy-Item -Path $selected.FullName -Destination $targetPath -Force

    $copiedFiles += $targetName
}

# ------------------------------------------------------------
# Zusammenfassung
# ------------------------------------------------------------
Write-Host "`nFertig."
Write-Host "Anzahl kopierter Bilder: $($copiedFiles.Count)"

if ($copiedFiles.Count -gt 0) {
    Write-Host "`nPreview-Dateien:"
    $copiedFiles | Sort-Object | ForEach-Object {
        Write-Host " - $_"
    }
}
