# ============================================================
# LIB_Utils.ps1
# Version: LIB_V1.0.0
# Zweck:   Grundlegende Hilfsfunktionen (Pfadwahl, Exit, Pfadermittlung)
# Autor:   Herbert Schrotter
# Datum:   26.10.2025
# ============================================================

<#
.SYNOPSIS
    Stellt universelle Hilfsfunktionen für alle Module bereit.
.DESCRIPTION
    Enthält Basisfunktionen wie:
      - Select-Folder → Windows-Dialog zur Auswahl eines Ordners
      - Check-Exit    → Benutzerabbruch bei Eingabe von X
      - Get-ScriptRoot→ Rückgabe des Skriptverzeichnisses
#>

# ============================================================
# ManifestHint
# ExportFunctions : Select-Folder, Check-Exit, Get-ScriptRoot
# Description     : Basisfunktionen für Benutzerinteraktion und Pfadermittlung
# Category        : Library
# Tags            : Utility, FolderDialog, ExitCheck, Path
# Dependencies    : none
# ============================================================

# ============================================================
# Einstellungen
# ============================================================

param([switch]$DebugMode)

# ============================================================
# Funktionen
# ============================================================

function Select-Folder {
    <#
    .SYNOPSIS
        Öffnet einen Windows-Dialog zur Ordnerauswahl.
    .DESCRIPTION
        Der Benutzer kann einen Ordner auswählen oder den Vorgang abbrechen.
        Bei Abbruch wird das Skript sauber beendet.
    .OUTPUTS
        String – Pfad des ausgewählten Ordners.
    .EXAMPLE
        $pfad = Select-Folder
    #>
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = "Bitte Zielordner auswählen (X zum Abbrechen):"
        $dlg.ShowNewFolderButton = $false
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::Cancel) {
            Write-Host "`n[Vorgang abgebrochen durch Benutzer]`n" -ForegroundColor Yellow
            exit 1001  # Fehlercode 1001 → Benutzerabbruch
        }
        if ([string]::IsNullOrWhiteSpace($dlg.SelectedPath)) {
            Write-Warning "Kein Pfad ausgewählt. Vorgang abgebrochen."
            exit 1002
        }
        return $dlg.SelectedPath
    }
    catch {
        Write-Host "❌ Fehler in Select-Folder: $($_.Exception.Message)" -ForegroundColor Red
        exit 1999
    }
}

function Check-Exit {
    <#
    .SYNOPSIS
        Prüft Eingabe auf 'X' und beendet ggf. den Prozess.
    .DESCRIPTION
        Wenn der Benutzer 'X' oder 'x' eingibt, wird der aktuelle Vorgang
        mit einer klaren Meldung beendet.
    .PARAMETER Input
        Zeichenfolge, die auf 'X' geprüft wird.
    .EXAMPLE
        Check-Exit $userInput
    #>
    param([string]$Input)
    if ($Input -match '^(X|x)$') {
        Write-Host "`n[Vorgang auf Benutzerwunsch beendet]`n" -ForegroundColor Yellow
        exit 1000
    }
}

function Get-ScriptRoot {
    <#
    .SYNOPSIS
        Ermittelt den physischen Speicherort des Skripts.
    .DESCRIPTION
        Gibt den Ordnerpfad des aktuell ausgeführten Skripts zurück.
    .OUTPUTS
        String – Verzeichnis, in dem das Skript liegt.
    .EXAMPLE
        $root = Get-ScriptRoot
    #>
    try {
        if ($PSScriptRoot) { return $PSScriptRoot }
        return Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    catch {
        Write-Host "❌ Fehler in Get-ScriptRoot: $($_.Exception.Message)" -ForegroundColor Red
        exit 1998
    }
}

# ============================================================
# Modul-Ende
# ============================================================
Write-Host "[Lib_Utils.ps1 geladen]" -ForegroundColor DarkGray
