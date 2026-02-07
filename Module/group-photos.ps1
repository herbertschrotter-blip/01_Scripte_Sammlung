# group-photos.ps1
# Zweck: Fotos nach erkanntem Namens- oder Sequenzmuster gruppieren
# Ablauf: Ordner wählen → Muster analysieren → Vorschau → Bestätigung → Ordner + Verschieben → Zusammenfassung
# Output: Bei Erfolg wird der Root-Pfad zurückgegeben (für Folgeaktionen im Menü)

Add-Type -AssemblyName System.Windows.Forms

# ------------------------------------------------------------
# Ordnerauswahl
# ------------------------------------------------------------
$dlg = New-Object System.Windows.Forms.FolderBrowserDialog
$dlg.Description = "Ordner mit Fotos auswählen"

if ($dlg.ShowDialog() -ne "OK") {
    Write-Host "Abgebrochen."
    return
}

$root = $dlg.SelectedPath
Write-Host "`nAusgewählter Ordner:`n$root"

# Liste der erstellten Ordner
$createdFolders = @()

# ------------------------------------------------------------
# Dateien einlesen (Variante A – korrekt)
# ------------------------------------------------------------
$files = Get-ChildItem -Path $root -File |
         Where-Object { $_.Extension -match '\.(jpg|jpeg|png)$' }

if ($files.Count -lt 2) {
    Write-Host "Zu wenige Bilddateien gefunden."
    return
}

# ------------------------------------------------------------
# Analyse – NAMENSLOGIK (Text vor _ oder -)
# ------------------------------------------------------------
$prefixMap = @{}

foreach ($f in $files) {
    if ($f.BaseName -match '^([^_-]+)[_-]') {
        $prefix = $matches[1]
        if (-not $prefixMap.ContainsKey($prefix)) {
            $prefixMap[$prefix] = @()
        }
        $prefixMap[$prefix] += $f
    }
}

$validPrefixGroups = $prefixMap.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }

# ------------------------------------------------------------
# Analyse – SEQUENZLOGIK (Nummernsprünge)
# ------------------------------------------------------------
$numbered = @()

foreach ($f in $files) {
    if ($f.BaseName -match '(\d+)') {
        $numbered += [PSCustomObject]@{
            File   = $f
            Number = [int]$matches[1]
        }
    }
}

$numbered = $numbered | Sort-Object Number

$sequenceGroups = @()
$current = @($numbered[0])

for ($i = 1; $i -lt $numbered.Count; $i++) {
    $prev = $numbered[$i - 1].Number
    $curr = $numbered[$i].Number

    if (($curr - $prev) -gt 5) {
        $sequenceGroups += ,$current
        $current = @()
    }
    $current += $numbered[$i]
}
$sequenceGroups += ,$current

$validSequenceGroups = $sequenceGroups | Where-Object { $_.Count -gt 1 }

# ------------------------------------------------------------
# ENTSCHEIDUNG + VORSCHAU
# ------------------------------------------------------------
$didWork = $false

# === NAMENSLOGIK hat Vorrang
if ($validPrefixGroups.Count -gt 0) {

    Write-Host "`nMUSTER ERKANNT: NAMENSLOGIK"
    Write-Host "Vorschau:"

    foreach ($grp in $validPrefixGroups) {
        Write-Host "`nOrdner: $($grp.Key)"
        $grp.Value | ForEach-Object { Write-Host "  - $($_.Name)" }
    }

    $ans = Read-Host "`nOrdner erstellen und Dateien verschieben? (J/N)"
    if ($ans -ne "J") {
        Write-Host "Abgebrochen. Keine Änderungen."
        return
    }

    foreach ($grp in $validPrefixGroups) {
        $target = Join-Path $root $grp.Key

        if (-not (Test-Path $target)) {
            New-Item -ItemType Directory -Path $target | Out-Null
            $createdFolders += (Split-Path $target -Leaf)
        }

        $grp.Value | Move-Item -Destination $target
    }

    Write-Host "`nFertig."
    $didWork = $true
}

# === SEQUENZLOGIK
elseif ($validSequenceGroups.Count -ge 1) {

    Write-Host "`nMUSTER ERKANNT: SEQUENZLOGIK"
    Write-Host "Vorschau:"

    $idx = 1
    foreach ($grp in $validSequenceGroups) {
        $folder = "{0:D3}" -f $idx
        Write-Host "`nOrdner: $folder"
        $grp | ForEach-Object { Write-Host "  - $($_.File.Name)" }
        $idx++
    }

    $ans = Read-Host "`nOrdner erstellen und Dateien verschieben? (J/N)"
    if ($ans -ne "J") {
        Write-Host "Abgebrochen. Keine Änderungen."
        return
    }

    $idx = 1
    foreach ($grp in $validSequenceGroups) {
        $folder = "{0:D3}" -f $idx
        $target = Join-Path $root $folder

        if (-not (Test-Path $target)) {
            New-Item -ItemType Directory -Path $target | Out-Null
            $createdFolders += (Split-Path $target -Leaf)
        }

        $grp | ForEach-Object { Move-Item $_.File -Destination $target }
        $idx++
    }

    Write-Host "`nFertig."
    $didWork = $true
}
else {
    Write-Host "`nKein eindeutiges Muster erkannt."
    Write-Host "Keine Änderungen durchgeführt."
    return
}

# ------------------------------------------------------------
# ZUSAMMENFASSUNG
# ------------------------------------------------------------
if ($createdFolders.Count -gt 0) {
    Write-Host "`nErstellte Ordner:"
    $createdFolders | Sort-Object | ForEach-Object {
        Write-Host " - $_"
    }
}
else {
    Write-Host "`nKeine neuen Ordner erstellt."
}

# ------------------------------------------------------------
# Output für Start-Menü (nur bei Erfolg)
# ------------------------------------------------------------
if ($didWork) {
    $root
}
