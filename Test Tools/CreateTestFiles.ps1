# ============================================================
# 🧩 TOOL_CreateTestFiles.ps1
# Version: TOOL_V1.2.0
# Zweck:   Erstellt Test-Dateien und -Ordner mit Zufallsnummern
#          und verschachtelter Struktur (bis 4 Ebenen) mit
#          steuerbarer Maximalanzahl pro Ebene
# Autor:   Herbert Schrotter
# Datum:   25.10.2025
# ============================================================

<#
.SYNOPSIS
    Erstellt zufällig nummerierte Dateien und verschachtelte Ordner (bis 4 Ebenen).

.DESCRIPTION
    - Ordnerauswahl über Explorer
    - Zufällige Unterordner bis zu Tiefe 4
    - Dateien in jeder Ebene
    - Begrenzung der maximalen Anzahl pro Ebene
    - Nummerierung: 1–3-stellig zufällig
    - Namen enthalten gemischte Trennzeichen (_,-, Leerzeichen)
#>

# ============================================================
# ManifestHint
# ExportFunctions : none
# Description     : Generator für Testdaten mit verschachtelter Struktur (bis 4 Ebenen)
# Category        : FileTools
# Tags            : Test, Generator, Random, Files, Folders, Recursive, MaxControl
# Dependencies    : none
# ============================================================

[CmdletBinding()]
param (
    [int]$MaxDepth = 4,
    [int]$MaxFilesPerLevel = 10,
    [int]$MaxFoldersPerLevel = 5
)

# ------------------------------------------------------------
# Funktionen
# ------------------------------------------------------------

function Select-Folder {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Bitte Zielordner auswählen, in dem Testdaten erstellt werden sollen:"
    $dialog.ShowNewFolderButton = $true
    $result = $dialog.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "`n❎ Vorgang abgebrochen.`n"
        exit
    }
    return $dialog.SelectedPath
}

function Get-RandomName {
    $prefixes = @("data", "test", "demo", "sample", "file", "temp", "auswahl", "probe")
    $separators = @("_", "-", " ", "__")
    $prefix = Get-Random -InputObject $prefixes
    $sep = Get-Random -InputObject $separators
    $numLength = Get-Random -Minimum 1 -Maximum 4     # 1–3-stellig
    $num = Get-Random -Minimum 1 -Maximum 999
    $numStr = $num.ToString().PadLeft($numLength, '0')
    return "$prefix$sep$numStr"
}

function Create-RandomStructure {
    param(
        [string]$BasePath,
        [int]$Depth = 1,
        [int]$MaxDepth = 4,
        [int]$MaxFilesPerLevel = 10,
        [int]$MaxFoldersPerLevel = 5
    )

    if ($Depth -gt $MaxDepth) { return }

    # Dateien in aktueller Ebene
    $exts = @(".txt", ".log", ".dat", ".csv")
    $fileCount = Get-Random -Minimum 1 -Maximum ($MaxFilesPerLevel + 1)

    for ($i = 1; $i -le $fileCount; $i++) {
        $name = Get-RandomName
        $ext = Get-Random -InputObject $exts
        $filePath = Join-Path $BasePath "$name$ext"
        New-Item -Path $filePath -ItemType File -Force | Out-Null
    }

    # Unterordner (zufällige Anzahl)
    $folderCount = Get-Random -Minimum 0 -Maximum ($MaxFoldersPerLevel + 1)
    for ($i = 1; $i -le $folderCount; $i++) {
        $name = Get-RandomName
        $newFolder = Join-Path $BasePath $name
        New-Item -Path $newFolder -ItemType Directory -Force | Out-Null

        # Mit zufälliger Wahrscheinlichkeit weitere Ebenen anlegen
        if ((Get-Random -Minimum 0 -Maximum 2) -eq 1) {
            Create-RandomStructure `
                -BasePath $newFolder `
                -Depth ($Depth + 1) `
                -MaxDepth $MaxDepth `
                -MaxFilesPerLevel $MaxFilesPerLevel `
                -MaxFoldersPerLevel $MaxFoldersPerLevel
        }
    }
}

# ------------------------------------------------------------
# Hauptlogik
# ------------------------------------------------------------

try {
    $Path = Select-Folder
    Write-Host "`n📂 Ziel: $Path`n"

    Write-Host ("Erstelle zufällige Teststruktur (bis {0} Ebenen, max {1} Dateien / {2} Ordner pro Ebene)..." -f $MaxDepth, $MaxFilesPerLevel, $MaxFoldersPerLevel)
    Create-RandomStructure -BasePath $Path -Depth 1 -MaxDepth $MaxDepth -MaxFilesPerLevel $MaxFilesPerLevel -MaxFoldersPerLevel $MaxFoldersPerLevel

    # Ergebnisstatistik
    $allFiles = Get-ChildItem -Path $Path -File -Recurse -Force
    $allFolders = Get-ChildItem -Path $Path -Directory -Recurse -Force

    Write-Host ""
    Write-Host "✅ Fertig: Testdaten erstellt."
    Write-Host ("📁 Ordner insgesamt : {0}" -f $allFolders.Count)
    Write-Host ("📄 Dateien insgesamt: {0}" -f $allFiles.Count)
    Write-Host ("🔝 Maximale Tiefe   : {0}" -f $MaxDepth)
    Write-Host ("📂 Hauptpfad        : {0}`n" -f $Path)
}
catch {
    Write-Host "❌ Fehler: $($_.Exception.Message)" -ForegroundColor Red
}
