# group-photos.ps1
# Zweck: Fotos nach erkanntem Namens- oder Sequenzmuster gruppieren
# Ablauf: Ordner wählen → Muster analysieren → Logik-Auswahl (Vorschlag/Ändern/Abbruch) → Vorschau → Bestätigung → Ordner + Verschieben → Zusammenfassung
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
# Dateien einlesen
# ------------------------------------------------------------
$files = Get-ChildItem -Path $root -File |
         Where-Object { $_.Extension -match '\.(jpg|jpeg|png)$' }

if ($files.Count -lt 2) {
    Write-Host "Zu wenige Bilddateien gefunden."
    return
}

# ------------------------------------------------------------
# Analyse – NAMENSLOGIK (mehrere Schemata erkennen)
# ------------------------------------------------------------

# Schema A: "Prefix vor _ oder -" (bisheriges Verhalten)
$prefixMap = @{}

# Schema B: "Result-Variante" -> gruppiert nach result / result_1 / result_2 ...
$resultVariantMap = @{}

foreach ($f in $files) {

    # --- Schema B (Result-Variante) ---
    # Beispiele:
    # 001_1_result       -> Key: result
    # 002_1_result_1     -> Key: result_1
    # 003_1_result_2     -> Key: result_2
    if ($f.BaseName -match '^\d{3}_\d+_(result(?:_\d+)?)$') {
        $key = $matches[1]
        if (-not $resultVariantMap.ContainsKey($key)) { $resultVariantMap[$key] = @() }
        $resultVariantMap[$key] += $f
        continue
    }

    # --- Schema A (Prefix vor Separator) ---
    if ($f.BaseName -match '^([^_-]+)[_-]') {
        $prefix = $matches[1]
        if (-not $prefixMap.ContainsKey($prefix)) { $prefixMap[$prefix] = @() }
        $prefixMap[$prefix] += $f
    }
}

$validPrefixGroups        = $prefixMap.GetEnumerator()        | Where-Object { $_.Value.Count -gt 1 }
$validResultVariantGroups = $resultVariantMap.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }

# ------------------------------------------------------------
# Analyse – SEQUENZLOGIK (ALT: Nummernsprünge)
# ------------------------------------------------------------
$numbered = @()

foreach ($f in $files) {

    $num = $null

    # Sequenzlogik A (bevorzugt): Name + 3+ Ziffern direkt danach (z.B. alina054...)
    if ($f.BaseName -match '^[A-Za-z]+(\d{3,})') {
        $num = [long]$matches[1]
    }
    # Sequenzlogik B (Fallback): erstes Zahlenpaket mit 3+ Ziffern irgendwo im Namen
    elseif ($f.BaseName -match '(\d{3,})') {
        $num = [long]$matches[1]
    }

    if ($null -ne $num) {
        $numbered += [PSCustomObject]@{
            File   = $f
            Number = $num
        }
    }
}

$numbered = $numbered | Sort-Object Number

$validSequenceGroups = @()

if ($numbered.Count -gt 1) {
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
}

# ------------------------------------------------------------
# Analyse – SEQUENZLOGIK (NEU): Prefix + Nummernsprünge
# - Prefix = Text vor erster Zahl (z.B. "alina")
# - Number = erste Zahl nach Prefix (Int64)
# - Gruppenbildung je Prefix, Sprung > 5 trennt Gruppen
# ------------------------------------------------------------
$validSequencePrefixGroups = @()

$seqPrefixItems = @()
foreach ($f in $files) {
    if ($f.BaseName -match '^(.+?)(\d+)') {
        $seqPrefixItems += [PSCustomObject]@{
            File   = $f
            Prefix = $matches[1].ToLower()
            Number = [long]$matches[2]
        }
    }
}

if ($seqPrefixItems.Count -gt 1) {

    $byPrefix = $seqPrefixItems | Group-Object Prefix

    foreach ($p in $byPrefix) {

        $items = $p.Group | Sort-Object Number
        if ($items.Count -lt 2) { continue }

        $current = @()
        $prev = $null

        foreach ($it in $items) {

            if ($null -ne $prev -and (($it.Number - $prev) -gt 5)) {
                if ($current.Count -gt 0) {
                    $validSequencePrefixGroups += ,@($current)
                }
                $current = @()
            }

            $current += $it
            $prev = $it.Number
        }

        if ($current.Count -gt 0) {
            $validSequencePrefixGroups += ,@($current)
        }
    }

    # nur Gruppen mit >=2 Dateien
    $validSequencePrefixGroups = $validSequencePrefixGroups | Where-Object { $_.Count -gt 1 }
}

# ------------------------------------------------------------
# LOGIK-AUSWAHL: nur eingebaute Logiken (Result/Prefix/Sequenz/Sequenz+Prefix)
# ------------------------------------------------------------

# Vorschlag: Result-Variante > Prefix > SequenzPrefix > SequenzAlt
$suggestedMode = "SEQUENCE"
if ($validSequenceGroups.Count -gt 0)        { $suggestedMode = "SEQUENCE" }
if ($validSequencePrefixGroups.Count -gt 0)  { $suggestedMode = "SEQUENCE_PREFIX" }
if ($validPrefixGroups.Count -gt 0)          { $suggestedMode = "NAME_PREFIX" }
if ($validResultVariantGroups.Count -gt 0)   { $suggestedMode = "NAME_RESULTVARIANT" }

function Format-YesNo {
    param([int]$Count)
    if ($Count -gt 0) { "Ja" } else { "Nein" }
}

Write-Host "`nVERFÜGBARE LOGIKEN:"
Write-Host ("[1] Namenslogik: Result-Varianten (result / result_1 / ...)  | Gruppen: {0} | Gefunden: {1}{2}" -f $validResultVariantGroups.Count, (Format-YesNo $validResultVariantGroups.Count), $(if ($suggestedMode -eq "NAME_RESULTVARIANT") { " (Vorschlag)" } else { "" }))
Write-Host ("[2] Namenslogik: Prefix vor '_' oder '-'                    | Gruppen: {0} | Gefunden: {1}{2}" -f $validPrefixGroups.Count,        (Format-YesNo $validPrefixGroups.Count),        $(if ($suggestedMode -eq "NAME_PREFIX") { " (Vorschlag)" } else { "" }))
Write-Host ("[3] Sequenzlogik: Nummernfolgen (Sprung > 5 trennt)        | Gruppen: {0} | Gefunden: {1}{2}" -f $validSequenceGroups.Count,      (Format-YesNo $validSequenceGroups.Count),      $(if ($suggestedMode -eq "SEQUENCE") { " (Vorschlag)" } else { "" }))
Write-Host ("[4] Sequenzlogik: Prefix+Nummer (je Prefix, Sprung > 5)    | Gruppen: {0} | Gefunden: {1}{2}" -f $validSequencePrefixGroups.Count,(Format-YesNo $validSequencePrefixGroups.Count),$(if ($suggestedMode -eq "SEQUENCE_PREFIX") { " (Vorschlag)" } else { "" }))

Write-Host "`nEingabe:"
Write-Host " - 1 / 2 / 3 / 4 wählen"
Write-Host " - ENTER = Vorschlag verwenden"
Write-Host " - A = Abbruch"

$pick = Read-Host "Auswahl"
if ($pick -match '^[Aa]$') {
    Write-Host "Abgebrochen. Keine Änderungen."
    return
}

$mode = $null
if ([string]::IsNullOrWhiteSpace($pick)) {
    $mode = $suggestedMode
}
elseif ($pick -match '^[1234]$') {
    switch ($pick) {
        "1" { $mode = "NAME_RESULTVARIANT" }
        "2" { $mode = "NAME_PREFIX" }
        "3" { $mode = "SEQUENCE" }
        "4" { $mode = "SEQUENCE_PREFIX" }
    }
}
else {
    Write-Host "Ungültige Auswahl. Abbruch. Keine Änderungen."
    return
}

# Validierung: gewählte Logik muss auch Gruppen liefern
switch ($mode) {
    "NAME_RESULTVARIANT" {
        if ($validResultVariantGroups.Count -eq 0) {
            Write-Host "`nDiese Logik hat in diesem Ordner keine Gruppen gefunden. Abbruch."
            return
        }
        $chosen = [PSCustomObject]@{ Mode = $mode; Title = "Namenslogik: Result-Varianten (result / result_1 / ...)" }
    }
    "NAME_PREFIX" {
        if ($validPrefixGroups.Count -eq 0) {
            Write-Host "`nDiese Logik hat in diesem Ordner keine Gruppen gefunden. Abbruch."
            return
        }
        $chosen = [PSCustomObject]@{ Mode = $mode; Title = "Namenslogik: Prefix vor '_' oder '-'" }
    }
    "SEQUENCE" {
        if ($validSequenceGroups.Count -eq 0) {
            Write-Host "`nDiese Logik hat in diesem Ordner keine Gruppen gefunden. Abbruch."
            return
        }
        $chosen = [PSCustomObject]@{ Mode = $mode; Title = "Sequenzlogik: Nummernfolgen (Sprung > 5 trennt Gruppen)" }
    }
    "SEQUENCE_PREFIX" {
        if ($validSequencePrefixGroups.Count -eq 0) {
            Write-Host "`nDiese Logik hat in diesem Ordner keine Gruppen gefunden. Abbruch."
            return
        }
        $chosen = [PSCustomObject]@{ Mode = $mode; Title = "Sequenzlogik: Prefix+Nummer (je Prefix, Sprung > 5 trennt Gruppen)" }
    }
    default {
        Write-Host "`nInterner Fehler: Unbekannter Modus."
        return
    }
}

Write-Host ("`nGewählt: {0}" -f $chosen.Title)

# ------------------------------------------------------------
# ENTSCHEIDUNG + VORSCHAU (nach gewählter Logik)
# ------------------------------------------------------------
$didWork = $false

if ($chosen.Mode -eq "NAME_RESULTVARIANT") {

    Write-Host "`nMUSTER ERKANNT: NAMENSLOGIK (RESULT-VARIANTEN)"
    Write-Host "Vorschau:"

    foreach ($grp in ($validResultVariantGroups | Sort-Object Key)) {
        Write-Host "`nOrdner: $($grp.Key)"
        $grp.Value | Sort-Object Name | ForEach-Object { Write-Host "  - $($_.Name)" }
    }

    $ans = Read-Host "`nOrdner erstellen und Dateien verschieben? (J/N)"
    if ($ans -ne "J") {
        Write-Host "Abgebrochen. Keine Änderungen."
        return
    }

    foreach ($grp in ($validResultVariantGroups | Sort-Object Key)) {
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
elseif ($chosen.Mode -eq "NAME_PREFIX") {

    Write-Host "`nMUSTER ERKANNT: NAMENSLOGIK (PREFIX)"
    Write-Host "Vorschau:"

    foreach ($grp in ($validPrefixGroups | Sort-Object Key)) {
        Write-Host "`nOrdner: $($grp.Key)"
        $grp.Value | Sort-Object Name | ForEach-Object { Write-Host "  - $($_.Name)" }
    }

    $ans = Read-Host "`nOrdner erstellen und Dateien verschieben? (J/N)"
    if ($ans -ne "J") {
        Write-Host "Abgebrochen. Keine Änderungen."
        return
    }

    foreach ($grp in ($validPrefixGroups | Sort-Object Key)) {
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
elseif ($chosen.Mode -eq "SEQUENCE_PREFIX") {

    Write-Host "`nMUSTER ERKANNT: SEQUENZLOGIK (PREFIX+NUMMER)"
    Write-Host "Vorschau:"

    # Nummerierung pro Prefix
    $prefixCounters = @{}

    foreach ($grp in $validSequencePrefixGroups) {

        $prefix = $grp[0].Prefix
        $prefixSafe = ($prefix -replace '[\\\/:\*\?"<>\|]', '_').Trim()
        $start  = $grp[0].Number
        $end    = $grp[$grp.Count - 1].Number

        if (-not $prefixCounters.ContainsKey($prefix)) { $prefixCounters[$prefix] = 0 }
        $prefixCounters[$prefix]++

        $folder = "{0}_{1:D3}" -f $prefixSafe, $prefixCounters[$prefix]

        Write-Host ("`nOrdner: {0}  (Prefix: {1} | {2}–{3})" -f $folder, $prefix, $start, $end)
        $grp | ForEach-Object { Write-Host "  - $($_.File.Name)" }
    }

    $ans = Read-Host "`nOrdner erstellen und Dateien verschieben? (J/N)"
    if ($ans -ne "J") {
        Write-Host "Abgebrochen. Keine Änderungen."
        return
    }

    # Zähler beim Verschieben identisch neu aufbauen
    $prefixCounters = @{}

    foreach ($grp in $validSequencePrefixGroups) {

        $prefix = $grp[0].Prefix

        if (-not $prefixCounters.ContainsKey($prefix)) { $prefixCounters[$prefix] = 0 }
        $prefixCounters[$prefix]++

        $folder = "{0}_{1:D3}" -f $prefix, $prefixCounters[$prefix]
        $target = Join-Path $root $folder

        if (-not (Test-Path $target)) {
            New-Item -ItemType Directory -Path $target | Out-Null
            $createdFolders += (Split-Path $target -Leaf)
        }

        $grp | ForEach-Object { Move-Item $_.File -Destination $target }
    }

    Write-Host "`nFertig."
    $didWork = $true
}
elseif ($chosen.Mode -eq "SEQUENCE") {

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
    Write-Host "`nInterner Fehler: Unbekannter Modus."
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
