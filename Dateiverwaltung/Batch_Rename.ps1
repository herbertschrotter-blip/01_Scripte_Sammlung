# ============================================================
# TOOL_BatchRename.ps1
# Version: TOOL_V1.3.0
# Zweck:   Interaktives Massen-Umbenennen mit Kollisionserkennung,
#          JSON-Logging, Restore-Menü, Analyse und Nummern-Suffix (_1,_2,_3)
# Autor:   Herbert Schrotter
# Datum:   25.10.2025
# ============================================================

<#
.SYNOPSIS
    Interaktives, sicheres Massen-Umbenennen mit Logging, Restore,
    Nummern-Analyse und automatischem Suffix bei Duplikaten.

.DESCRIPTION
    Funktionen:
      - Menü: Dateien / Ordner / Beides / Wiederherstellen / Analyse
      - Keine Rekursion (nur oberste Ebene)
      - Dreistellige Nummern (001 – 999)
      - Automatische Suffixe (_1,_2,...) bei gleichen Nummern
      - Kollisionserkennung + eindeutige Zielnamen
      - Sitzungs-Logging (JSON, max. 10 Sitzungen)
      - Restore einzelner Sitzungen
      - Analyse von Nummernbereichen & Lücken
      - Abbruch jederzeit durch „X“
#>

# ============================================================
# ManifestHint
# ExportFunctions : none
# Description     : Massen-Umbenennen mit JSON-Logging, Restore, Analyse & Suffix
# Category        : FileTools
# Tags            : Rename, Batch, Preview, Logging, Restore, Analyse, Collision
# Dependencies    : none
# ============================================================

[CmdletBinding()]
param([switch]$DebugMode)

# ============================================================
# Hilfsfunktionen
# ============================================================

function Write-DebugLog {
    param([string]$Message)
    if ($DebugMode) { Write-Host "[DEBUG] $Message" -ForegroundColor DarkGray }
}

function Check-Exit {
    param([string]$Input)
    if ($Input -match '^(X|x)$') {
        Write-Host "`nVorgang auf Benutzerwunsch beendet.`n"
        exit
    }
}

function Select-Folder {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Bitte Zielordner auswählen (X zum Abbrechen):"
    $dlg.ShowNewFolderButton = $false
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::Cancel) {
        Write-Host "`nVorgang abgebrochen.`n"
        exit
    }
    return $dlg.SelectedPath
}

function Show-Menu {
    Write-Host "`n──────────────────────────────────────────────"
    Write-Host "TOOL_BatchRename – Auswahlmodus"
    Write-Host "──────────────────────────────────────────────"
    Write-Host "1 → Nur Dateien umbenennen"
    Write-Host "2 → Nur Ordner umbenennen"
    Write-Host "3 → Dateien + Ordner umbenennen"
    Write-Host "4 → Wiederherstellen (eine der letzten 10 Sitzungen)"
    Write-Host "5 → Analyse: Nummernbereich & Lücken anzeigen"
    Write-Host "──────────────────────────────────────────────"
    Write-Host "X → Abbrechen"
    Write-Host "──────────────────────────────────────────────"
    $choice = Read-Host "Bitte Auswahl eingeben (1-5 oder X)"
    Check-Exit $choice
    switch ($choice) {
        '1' { return 'Files' }
        '2' { return 'Folders' }
        '3' { return 'Both' }
        '4' { return 'Restore' }
        '5' { return 'Analyse' }
        default { Write-Host "Ungültige Eingabe. Vorgang beendet."; exit }
    }
}

function Get-ScriptRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    return Split-Path -Parent $MyInvocation.MyCommand.Path
}

# ============================================================
# Logging
# ============================================================

function Get-LogPath { return (Join-Path (Get-ScriptRoot) "BatchRename_Log.json") }

function Load-Log {
    $path = Get-LogPath
    if (-not (Test-Path $path)) { return [pscustomobject]@{ Sessions = @() } }
    try {
        $json = Get-Content -Path $path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($json)) { return [pscustomobject]@{ Sessions = @() } }
        $obj = $json | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $obj -or -not ($obj.PSObject.Properties.Name -contains 'Sessions')) {
            return [pscustomobject]@{ Sessions = @() }
        }
        return $obj
    }
    catch {
        Write-Warning "Fehler beim Lesen des Logs. Datei wird neu erstellt."
        return [pscustomobject]@{ Sessions = @() }
    }
}

function Save-Log { param($Log) $Log | ConvertTo-Json -Depth 6 | Out-File (Get-LogPath) -Encoding UTF8 -Force }

function New-SessionObject {
    param([string]$Path,[string]$NewName,[string]$Mode)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $id = "Session_" + (Get-Date -Format "yyyyMMdd_HHmmss")
    return [pscustomobject]@{
        ID=$id;Date=$timestamp;Path=$Path;NewName=$NewName;Mode=$Mode;Items=@()
    }
}

function Append-Session {
    param($Log,$Session)
    if ($null -eq $Log) { $Log=[pscustomobject]@{Sessions=@()} }
    if (-not ($Log.PSObject.Properties.Name -contains 'Sessions')) {
        $Log | Add-Member -NotePropertyName Sessions -NotePropertyValue @() -Force
    }
    $sessions=@($Log.Sessions)+$Session
    if ($sessions.Count -gt 10) { $sessions=$sessions[($sessions.Count-10)..($sessions.Count-1)] }
    $Log.Sessions=$sessions
    Save-Log $Log
}

# ============================================================
# Wiederherstellung
# ============================================================

function Choose-SessionForRestore {
    $log=Load-Log
    if($log.Sessions.Count -eq 0){Write-Host "Kein Sitzungslog vorhanden.";return $null}
    Write-Host "`nVerfügbare Sitzungen:";Write-Host "──────────────────────────────────────────────"
    for($i=0;$i -lt $log.Sessions.Count;$i++){
        $s=$log.Sessions[$i]
        Write-Host ("{0}. {1} | {2} | {3}" -f ($i+1),$s.Path,$s.NewName,$s.Date)
    }
    $inp=Read-Host "Sitzungsnummer wählen (1-{0}) oder X" -f $log.Sessions.Count
    Check-Exit $inp
    if($inp -notmatch '^\d+$'){return $null}
    $idx=[int]$inp;if($idx -lt 1 -or $idx -gt $log.Sessions.Count){return $null}
    return $log.Sessions[$idx-1]
}

function Restore-Session {
    $s=Choose-SessionForRestore;if($null -eq $s){return}
    Write-Host "`nWiederherstellung für $($s.Path)`n";$count=0
    foreach($it in $s.Items){
        try{
            $d=$it.Dir;$current=Join-Path $d $it.NeuName;$target=Join-Path $d $it.AltName
            if(-not(Test-Path $current)){Write-Warning "Übersprungen (nicht gefunden): $current";continue}
            $c=1;$cand=$target
            while(Test-Path $cand){
                $c++;$b=[IO.Path]::GetFileNameWithoutExtension($it.AltName)
                $e=[IO.Path]::GetExtension($it.AltName)
                $a="{0}_restored_{1}{2}"-f$b,$c,$e
                $cand=Join-Path $d $a
            }
            Rename-Item -Path $current -NewName (Split-Path $cand -Leaf) -ErrorAction Stop
            Write-Host ("OK: {0} → {1}" -f $it.NeuName,(Split-Path $cand -Leaf));$count++
        }catch{Write-Warning "Fehler bei Wiederherstellung: $($_.Exception.Message)"}
    }
    Write-Host "`nFertig. $count Elemente wiederhergestellt.`n"
}

# ============================================================
# Analyse-Funktion (nur fehlende Nummern)
# ============================================================

function Analyse-Numbers {
    Write-Host "`nStarte Nummern-Analyse..."
    $Path=Select-Folder
    if(-not(Test-Path $Path)){throw "Pfad '$Path' nicht gefunden."}
    $regex='\d+'
    $items=Get-ChildItem -Path $Path -Force
    if($items.Count -eq 0){Write-Warning "Keine Dateien oder Ordner gefunden.";return}
    $numbers=@()
    foreach($item in $items){
        $m=[regex]::Match($item.Name,$regex)
        if($m.Success){try{$numbers+=[int]$m.Value}catch{}}
    }
    if($numbers.Count -eq 0){Write-Host "Keine nummerierten Namen gefunden.";return}
    $nums=$numbers|Sort-Object -Unique
    $min=($nums|Measure-Object -Minimum).Minimum
    $max=($nums|Measure-Object -Maximum).Maximum
    $missing=($min..$max)|Where-Object{$_ -notin $nums}
    $folderName=Split-Path $Path -Leaf
    $base=($folderName -replace '[^A-Za-zÄÖÜäöüß]','').Trim()
    if([string]::IsNullOrWhiteSpace($base)){$base=$min.ToString("000")}
    $ts=Get-Date -Format "yyyyMMdd_HHmm"
    $target=Join-Path $Path ("{0}_{1}.txt" -f $base,$ts)
    $out=@()
    $out+="Pfad: $Path"
    $out+="Niedrigste Nummer: {0}" -f ($min.ToString("000"))
    $out+="Höchste Nummer:    {0}" -f ($max.ToString("000"))
    $out+="`nGefunden: {0}" -f ($nums.Count)
    $out+="Fehlend : {0}" -f ($missing.Count)
    $out+="`nFehlende Nummern:"
    if($missing.Count -eq 0){
        $out+="(Keine fehlenden Nummern)"
    }else{
        foreach($m in $missing){$out+=$m.ToString("000")}
    }
    $out|Out-File -FilePath $target -Encoding UTF8
    Write-Host ("`nAnalyse gespeichert: {0}" -f $target)
    Write-Host ("Gefunden: {0} | Fehlend: {1}`n" -f $nums.Count,$missing.Count)
}

# ============================================================
# Hauptlogik
# ============================================================

try {
    $mode = Show-Menu
    if ($mode -eq 'Analyse') { Analyse-Numbers; return }
    if ($mode -eq 'Restore') { Restore-Session; return }

    $Path = Select-Folder
    if (-not (Test-Path $Path)) { throw "Der Pfad '$Path' wurde nicht gefunden." }

    $NewName = Read-Host "Bitte neuen Standardnamen eingeben (z. B. 'Standard' oder X zum Abbrechen)"
    Check-Exit $NewName
    if ([string]::IsNullOrWhiteSpace($NewName)) { Write-Host "Kein Name eingegeben."; exit }

    $regex = '(?<prefix>.*?)(?<num>\d{1,})(?<suffix>.*)'
    switch ($mode) {
        'Files'   { $items = Get-ChildItem -Path $Path -File -Force }
        'Folders' { $items = Get-ChildItem -Path $Path -Directory -Force }
        'Both'    { $items = Get-ChildItem -Path $Path -Force }
    }
    if ($items.Count -eq 0) { Write-Warning "Keine Elemente gefunden."; return }

    # ============================================================
    # Vorschau erzeugen mit Suffix-Logik (_1,_2,_3)
    # ============================================================

    Write-Host "`n──────────────────────────────────────────────"
    Write-Host "Vorschau der geplanten Änderungen:"
    Write-Host "──────────────────────────────────────────────`n"

    $list = @()
    foreach ($item in $items) {
        if ($item.Name -match $regex) {
            $num = [int]$Matches['num']
            $numPadded = $num.ToString("000")
            $ext = if ($item.PSIsContainer) { "" } else { $item.Extension }
            $dir = if ($item.DirectoryName) { $item.DirectoryName } else { $Path }

            $list += [PSCustomObject]@{
                Typ     = if ($item.PSIsContainer) { "Ordner" } else { "Datei" }
                AltName = $item.Name
                Nummer  = $numPadded
                Ext     = $ext
                Dir     = $dir
                Pfad    = Join-Path $dir $item.Name
            }
        }
    }

    if ($list.Count -eq 0) {
        Write-Warning "Keine passenden Elemente gefunden."
        return
    }

    # gleiche Nummern gruppieren → _1,_2,_3
    $grouped = $list | Group-Object Nummer
    $finalList = @()
    foreach ($g in $grouped) {
        $counter = 1
        foreach ($entry in $g.Group) {
            $suffixCounter = if ($g.Count -gt 1) { "_$counter" } else { "" }
            $newBase = "$NewName $($entry.Nummer)$suffixCounter"
            $entry | Add-Member -NotePropertyName NeuName -NotePropertyValue "$newBase$($entry.Ext)" -Force
            $finalList += $entry
            $counter++
        }
    }

    $finalList = $finalList | Sort-Object Typ, AltName

    # Vorschau ausgeben
    $finalList | Format-Table Typ, AltName, NeuName -AutoSize
    Write-Host ""
    $confirm = Read-Host "Fortfahren mit dem Umbenennen? (J/N/X)"
    Check-Exit $confirm
    if ($confirm -notmatch '^(J|j|Y|y)$') {
        Write-Host "Vorgang abgebrochen."
        return
    }

    # ============================================================
    # Umbenennen
    # ============================================================

    $log = Load-Log
    $session = New-SessionObject -Path $Path -NewName $NewName -Mode $mode
    $processed = 0

    foreach ($entry in $finalList) {
        try {
            $dir = $entry.Dir
            $target = Join-Path $dir $entry.NeuName
            $counter = 1

            while (Test-Path $target) {
                $counter++
                $base = [IO.Path]::GetFileNameWithoutExtension($entry.NeuName)
                $ext  = [IO.Path]::GetExtension($entry.NeuName)
                $try  = "{0}_{1}{2}" -f $base, $counter, $ext
                $target = Join-Path $dir $try
            }

            if ($counter -gt 1) {
                $entry.NeuName = Split-Path $target -Leaf
                Write-Host ("Hinweis: Doppelter Name erkannt – verwende {0}" -f $entry.NeuName) -ForegroundColor Yellow
            }

            Rename-Item -Path $entry.Pfad -NewName $entry.NeuName -ErrorAction Stop
            Write-Host ("OK: {0} → {1}" -f $entry.AltName, $entry.NeuName)

            $session.Items += [pscustomobject]@{
                Typ     = $entry.Typ
                Dir     = $dir
                AltName = $entry.AltName
                NeuName = $entry.NeuName
            }
            $processed++
        }
        catch {
            Write-Warning "Fehler bei '$($entry.AltName)': $($_.Exception.Message)"
        }
    }

    Append-Session -Log $log -Session $session

    Write-Host "`nFertig. $processed Elemente wurden bearbeitet."
    Write-Host ("Sitzung gespeichert: {0}" -f $session.ID)
    Write-Host ("Log-Datei: {0}`n" -f (Get-LogPath))
}
catch {
    Write-Host "Unerwarteter Fehler: $($_.Exception.Message)" -ForegroundColor Red
}
