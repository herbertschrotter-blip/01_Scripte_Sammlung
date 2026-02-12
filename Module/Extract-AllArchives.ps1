#Requires -Version 5.1

<#
.SYNOPSIS
    Rekursive Archive-Extraktion mit automatischer Löschung nach erfolgreichem Entpacken

.DESCRIPTION
    Findet alle Archive (.zip, .rar, .7z, .tar, .gz, .bz2, .xz) rekursiv in einem
    Root-Ordner, entpackt sie im selben Verzeichnis und löscht das Archiv nach
    erfolgreichem Entpacken. Unterstützt verschachtelte Archive (Archive in Archiven)
    durch mehrere Durchläufe.
    
    Unterstützte Entpacker:
    - 7-Zip (bevorzugt)
    - WinRAR (rar.exe)
    - PowerShell Expand-Archive (nur .zip)
    
    Bei verschachtelten Archiven werden bis zu 9999 Runden durchlaufen,
    bis keine neuen Archive mehr gefunden werden.

.PARAMETER RootPath
    Root-Ordner zum Scannen nach Archiven. Wenn nicht angegeben, wird ein
    Ordner-Auswahl-Dialog angezeigt.

.EXAMPLE
    PS> .\Extract-AllArchives.ps1
    Zeigt Dialog zur Ordnerauswahl, scannt rekursiv und entpackt alle Archive

.EXAMPLE
    PS> .\Extract-AllArchives.ps1 -RootPath "C:\Downloads"
    Entpackt alle Archive in C:\Downloads (inkl. Unterordner)

.NOTES
    Autor: Herbert Schrotter
    Version: 2.0.0
    Erstellt: 2025-02-12
    
    Fehlercodes:
    - E010: Abbruch durch User
    - E020: Root-Ordner existiert nicht
    - E030: Kein Entpacker gefunden / Entpacker-Datei nicht gefunden
    - E100: Entpacken fehlgeschlagen
    
    Abhängigkeiten:
    - System.Windows.Forms (für Ordner-Dialog)
    - 7-Zip oder WinRAR (optional, für .rar/.7z)

.LINK
    https://github.com/herbertschrotter-blip/01_Scripte_Sammlung
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$RootPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# ============================================================================
# Konfiguration
# ============================================================================

# Unterstützte Archiv-Erweiterungen
$script:archiveExtensions = @('.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz')

# Maximale Anzahl Durchläufe (Schutz vor Endlosschleifen)
$script:maxRounds = 9999

# ============================================================================
# Get-Extractor - Ermittelt verfügbaren Entpacker
# ============================================================================
function Get-Extractor {
    <#
    .SYNOPSIS
        Ermittelt verfügbaren Entpacker (7-Zip bevorzugt, dann WinRAR)
    
    .DESCRIPTION
        Sucht nach installierten Entpackern in Standard-Installationspfaden
        und im System-PATH. Bevorzugt 7-Zip, falls nicht vorhanden wird
        WinRAR (rar.exe) verwendet.
    
    .OUTPUTS
        PSCustomObject mit Type und Path, oder $null wenn kein Entpacker gefunden
    
    .NOTES
        Autor: Herbert Schrotter
        Version: 1.0.0
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    # Standard-Installationspfade durchsuchen
    $candidates = @(
        @{ Type = '7ZIP'; Path = (Join-Path $env:ProgramFiles '7-Zip\7z.exe') },
        @{ Type = '7ZIP'; Path = (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe') },
        @{ Type = 'RAR';  Path = (Join-Path $env:ProgramFiles 'WinRAR\rar.exe') },
        @{ Type = 'RAR';  Path = (Join-Path ${env:ProgramFiles(x86)} 'WinRAR\rar.exe') }
    )
    
    foreach ($c in $candidates) {
        if ($c.Path -and (Test-Path -LiteralPath $c.Path)) {
            return [PSCustomObject]@{
                PSTypeName = 'Archive.Extractor'
                Type       = $c.Type
                Path       = $c.Path
            }
        }
    }
    
    # Fallback: Suche in System-PATH
    $cmd7z = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($cmd7z -and (Test-Path -LiteralPath $cmd7z.Source)) {
        return [PSCustomObject]@{
            PSTypeName = 'Archive.Extractor'
            Type       = '7ZIP'
            Path       = $cmd7z.Source
        }
    }
    
    $cmdRar = Get-Command rar.exe -ErrorAction SilentlyContinue
    if ($cmdRar -and (Test-Path -LiteralPath $cmdRar.Source)) {
        return [PSCustomObject]@{
            PSTypeName = 'Archive.Extractor'
            Type       = 'RAR'
            Path       = $cmdRar.Source
        }
    }
    
    # Kein Entpacker gefunden → nur ZIP via Expand-Archive möglich
    return $null
}

# ============================================================================
# Get-Archives - Findet alle Archive rekursiv
# ============================================================================
function Get-Archives {
    <#
    .SYNOPSIS
        Findet alle Archive rekursiv in einem Ordner
    
    .DESCRIPTION
        Scannt einen Ordner rekursiv nach Dateien mit Archiv-Erweiterungen
        und gibt die Dateien sortiert nach FullName zurück.
    
    .PARAMETER RootPath
        Zu durchsuchender Root-Ordner
    
    .OUTPUTS
        Array von FileInfo-Objekten (Archive), sortiert nach FullName
    
    .NOTES
        Autor: Herbert Schrotter
        Version: 1.0.0
        Verwendet -LiteralPath wegen möglichen Sonderzeichen wie []
    #>
    
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo[]])]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )
    
    # Rekursiv alle Dateien mit Archiv-Erweiterung finden
    Get-ChildItem -LiteralPath $RootPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $script:archiveExtensions -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object FullName
}

# ============================================================================
# Expand-OneArchive - Entpackt ein einzelnes Archiv
# ============================================================================
function Expand-OneArchive {
    <#
    .SYNOPSIS
        Entpackt ein einzelnes Archiv im selben Verzeichnis
    
    .DESCRIPTION
        Entpackt ein Archiv abhängig von Extension und verfügbarem Entpacker:
        - .zip: PowerShell Expand-Archive
        - Andere: 7-Zip oder WinRAR (je nach Extractor-Parameter)
    
    .PARAMETER ArchivePath
        Vollständiger Pfad zum Archiv
    
    .PARAMETER Extractor
        Extractor-Objekt von Get-Extractor (PSCustomObject mit Type und Path)
    
    .OUTPUTS
        Boolean - $true wenn erfolgreich entpackt, $false bei Fehler
    
    .NOTES
        Autor: Herbert Schrotter
        Version: 1.0.0
    #>
    
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ArchivePath,
        
        [Parameter()]
        [PSCustomObject]$Extractor
    )
    
    $ext = [IO.Path]::GetExtension($ArchivePath).ToLowerInvariant()
    $dir = Split-Path -Parent $ArchivePath
    
    Write-Host ('[INFO] Archive : {0}' -f $ArchivePath)
    Write-Host ('[INFO] Ziel    : {0}' -f $dir)
    
    # ZIP mit PowerShell Bordmitteln entpacken
    if ($ext -eq '.zip') {
        try {
            Expand-Archive -LiteralPath $ArchivePath -DestinationPath $dir -Force
            return $true
        }
        catch {
            Write-Host ('E100 ZIP fehlgeschlagen: {0}' -f $_.Exception.Message)
            return $false
        }
    }
    
    # Für andere Archive: Externer Entpacker benötigt
    if (-not $Extractor) {
        Write-Host 'E030 Kein Entpacker (7-Zip/WinRAR) gefunden'
        return $false
    }
    
    if (-not (Test-Path -LiteralPath $Extractor.Path)) {
        Write-Host ('E030 Entpacker-Datei nicht gefunden: {0}' -f $Extractor.Path)
        return $false
    }
    
    # 7-Zip Entpacker
    if ($Extractor.Type -eq '7ZIP') {
        $args = @('x', '-y', '-aoa', ('-o{0}' -f $dir), $ArchivePath)
        Write-Host ('[DBG] 7z.exe {0}' -f ($args -join ' '))
        
        $p = Start-Process -FilePath $Extractor.Path -ArgumentList $args -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -ne 0) {
            Write-Host ('E100 7-Zip fehlgeschlagen. ExitCode={0}' -f $p.ExitCode)
            return $false
        }
        return $true
    }
    
    # WinRAR Entpacker
    if ($Extractor.Type -eq 'RAR') {
        # Wichtig: Trailing Backslash entfernen (Quote-Falle bei Leerzeichen + \)
        $outDir = $dir.TrimEnd('\')
        
        # rar.exe Syntax: x -y -o+ "ARCHIV" "ZIELORDNER"
        # ArgumentList als String → robustes Quoting bei Leerzeichen
        $argLine = ('x -y -o+ "{0}" "{1}"' -f $ArchivePath, $outDir)
        
        Write-Host ('[DBG] rar.exe {0}' -f $argLine)
        
        $p = Start-Process -FilePath $Extractor.Path -ArgumentList $argLine -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -ne 0) {
            Write-Host ('E100 rar.exe fehlgeschlagen. ExitCode={0}' -f $p.ExitCode)
            return $false
        }
        return $true
    }
    
    # Unbekannter Entpacker-Typ
    Write-Host ('E030 Unbekannter Entpacker-Typ: {0}' -f $Extractor.Type)
    return $false
}

# ============================================================================
# Hauptlogik
# ============================================================================

# Ordnerauswahl: Dialog wenn kein RootPath übergeben
if (-not $RootPath) {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Root-Ordner für Archive-Extraktion auswählen'
    
    if ($dlg.ShowDialog() -ne 'OK') {
        Write-Host 'E010 Abbruch durch User'
        return
    }
    
    $rootPath = $dlg.SelectedPath
}
else {
    $rootPath = $RootPath
}

# Root-Ordner validieren
if (-not (Test-Path -LiteralPath $rootPath)) {
    Write-Host ('E020 Root-Ordner existiert nicht: {0}' -f $rootPath)
    return
}

Write-Host ('[INFO] Root: {0}' -f $rootPath)

# Entpacker ermitteln
$extractor = Get-Extractor
if ($extractor) {
    Write-Host ('[INFO] Entpacker: {0} ({1})' -f $extractor.Type, $extractor.Path)
}
else {
    Write-Host '[INFO] Entpacker: keiner gefunden (nur ZIP via Expand-Archive möglich)'
}

# ============================================================================
# Hauptloop - Verschachtelte Archive durch mehrere Runden
# ============================================================================

# Tracking bereits verarbeiteter Archive (verhindert Endlosschleifen)
$processed = New-Object 'System.Collections.Generic.HashSet[string]'
$round = 0
$ok = 0
$fail = 0

while ($round -lt $script:maxRounds) {
    $round++
    Write-Host ''
    Write-Host ('========== Runde {0} ==========' -f $round)
    
    # WICHTIG: @() erzwingt Array (auch bei nur 1 Ergebnis) → verhindert .Count Fehler
    $archives = @(Get-Archives -RootPath $rootPath |
        Where-Object { -not $processed.Contains($_.FullName) })
    
    # Keine neuen Archive gefunden → Fertig
    if ($archives.Count -eq 0) {
        Write-Host '[INFO] Keine weiteren Archive gefunden'
        break
    }
    
    # Alle gefundenen Archive verarbeiten
    foreach ($a in $archives) {
        # Als verarbeitet markieren (auch bei Fehler, verhindert Wiederholung)
        $null = $processed.Add($a.FullName)
        
        # Archiv entpacken
        $success = Expand-OneArchive -ArchivePath $a.FullName -Extractor $extractor
        
        if ($success) {
            # Erfolgreich entpackt → Archiv löschen
            try {
                Remove-Item -LiteralPath $a.FullName -Force -ErrorAction Stop
                Write-Host ('[OK] Gelöscht: {0}' -f $a.FullName)
                $ok++
            }
            catch {
                Write-Host ('[WARN] Löschen fehlgeschlagen: {0} | {1}' -f $a.FullName, $_.Exception.Message) -ForegroundColor Yellow
                $ok++  # Trotzdem als OK zählen (Entpacken war erfolgreich)
            }
        }
        else {
            # Entpacken fehlgeschlagen
            Write-Host ('[FAIL] Fehler: {0}' -f $a.FullName)
            $fail++
        }
    }
}

# ============================================================================
# Abschluss-Statistik
# ============================================================================

Write-Host ''
Write-Host ('[INFO] Fertig | OK={0} | FAIL={1} | Runden={2}' -f $ok, $fail, $round)