<#
ManifestHint:
  ExportFunctions = @()
  Description     = "Root per Dialog wählen, Archive rekursiv finden, im selben Ordner entpacken (inkl. Unterarchive) und Archiv nach erfolgreichem Entpacken löschen."
  Category        = "Media"
  Tags            = @("Archives","Extract","Zip","Rar","7z","Recursive","DeleteAfterExtract","FolderBrowserDialog","NestedArchives")
  Dependencies    = @("System.Windows.Forms")

Fehlercodes:
  E010 Abbruch durch User
  E020 Root-Ordner existiert nicht
  E030 Kein Entpacker gefunden / Entpacker-Datei nicht gefunden
  E100 Entpacken fehlgeschlagen
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Add-Type -AssemblyName System.Windows.Forms | Out-Null

# -----------------------------------------------------
# Einstellungen
# -----------------------------------------------------
$archiveExtensions = @(".zip",".rar",".7z",".tar",".gz",".bz2",".xz")
$maxRounds = 9999

# -----------------------------------------------------
# Entpacker ermitteln (7-Zip bevorzugt, sonst WinRAR rar.exe)
# -----------------------------------------------------
function Get-Extractor {
    # Zweck: bevorzugt 7-Zip, sonst WinRAR (rar.exe). Liefert immer vollständigen Pfad.

    $candidates = @(
        @{ Type="7ZIP"; Path=(Join-Path $env:ProgramFiles "7-Zip\7z.exe") },
        @{ Type="7ZIP"; Path=(Join-Path ${env:ProgramFiles(x86)} "7-Zip\7z.exe") },
        @{ Type="RAR";  Path=(Join-Path $env:ProgramFiles "WinRAR\rar.exe") },
        @{ Type="RAR";  Path=(Join-Path ${env:ProgramFiles(x86)} "WinRAR\rar.exe") }
    )

    foreach ($c in $candidates) {
        if ($c.Path -and (Test-Path -LiteralPath $c.Path)) {
            return @{ Type = $c.Type; Path = $c.Path }
        }
    }

    # Fallback über PATH (falls installiert und im PATH)
    $cmd7z = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($cmd7z -and (Test-Path -LiteralPath $cmd7z.Source)) {
        return @{ Type="7ZIP"; Path=$cmd7z.Source }
    }

    $cmdRar = Get-Command rar.exe -ErrorAction SilentlyContinue
    if ($cmdRar -and (Test-Path -LiteralPath $cmdRar.Source)) {
        return @{ Type="RAR"; Path=$cmdRar.Source }
    }

    return $null
}

# -----------------------------------------------------
# Archive suchen (robust, ohne -Filter; mit -LiteralPath wegen [])
# -----------------------------------------------------
function Get-Archives {
    param([string]$RootPath)

    Get-ChildItem -LiteralPath $RootPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $archiveExtensions -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object FullName
}

# -----------------------------------------------------
# Einzelnes Archiv entpacken
# -----------------------------------------------------
function Expand-OneArchive {
    param(
        [string]$ArchivePath,
        [hashtable]$Extractor
    )

    $ext = [IO.Path]::GetExtension($ArchivePath).ToLowerInvariant()
    $dir = Split-Path -Parent $ArchivePath

    Write-Host ("[INFO] Archive : {0}" -f $ArchivePath)
    Write-Host ("[INFO] Ziel    : {0}" -f $dir)

    # ZIP mit Bordmitteln
    if ($ext -eq ".zip") {
        try {
            if ($PSCmdlet.ShouldProcess($ArchivePath, "ZIP entpacken")) {
                Expand-Archive -LiteralPath $ArchivePath -DestinationPath $dir -Force
            }
            return $true
        }
        catch {
            Write-Host ("E100 ZIP fehlgeschlagen: {0}" -f $_.Exception.Message)
            return $false
        }
    }

    if (-not $Extractor) {
        Write-Host "E030 Kein Entpacker (7-Zip/WinRAR) gefunden"
        return $false
    }

    if (-not (Test-Path -LiteralPath $Extractor.Path)) {
        Write-Host ("E030 Entpacker-Datei nicht gefunden: {0}" -f $Extractor.Path)
        return $false
    }

    if ($Extractor.Type -eq "7ZIP") {
        $args = @("x","-y","-aoa",("-o{0}" -f $dir),$ArchivePath)
        Write-Host ("[DBG] 7z.exe {0}" -f ($args -join " "))

        if ($PSCmdlet.ShouldProcess($ArchivePath, "7-Zip entpacken")) {
            $p = Start-Process -FilePath $Extractor.Path -ArgumentList $args -Wait -PassThru -NoNewWindow
            if ($p.ExitCode -ne 0) {
                Write-Host ("E100 7-Zip fehlgeschlagen. ExitCode={0}" -f $p.ExitCode)
                return $false
            }
        }
        return $true
    }

if ($Extractor.Type -eq "RAR") {
    # Wichtig: Zielpfad ohne trailing "\" (Quote-Falle bei Leerzeichen + Backslash)
    $outDir = $dir.TrimEnd('\')

    # rar.exe Syntax: x -y -o+ "ARCHIV" "ZIELORDNER"
    # ArgumentList als EIN String -> robustes Quoting
    $argLine = ('x -y -o+ "{0}" "{1}"' -f $ArchivePath, $outDir)

    Write-Host ("[DBG] rar.exe {0}" -f $argLine)

    if ($PSCmdlet.ShouldProcess($ArchivePath, "rar.exe entpacken")) {
        $p = Start-Process -FilePath $Extractor.Path -ArgumentList $argLine -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -ne 0) {
            Write-Host ("E100 rar.exe fehlgeschlagen. ExitCode={0}" -f $p.ExitCode)
            return $false
        }
    }
    return $true
}

    Write-Host ("E030 Unbekannter Entpacker-Typ: {0}" -f $Extractor.Type)
    return $false
}

# -----------------------------------------------------
# Ordnerauswahl
# -----------------------------------------------------
$dlg = New-Object System.Windows.Forms.FolderBrowserDialog
$dlg.Description = "Root-Ordner auswählen"

if ($dlg.ShowDialog() -ne "OK") {
    Write-Host "E010 Abgebrochen"
    return
}

$rootPath = $dlg.SelectedPath
if (-not (Test-Path -LiteralPath $rootPath)) {
    Write-Host ("E020 Root-Ordner existiert nicht: {0}" -f $rootPath)
    return
}

Write-Host ("[INFO] Root: {0}" -f $rootPath)

$extractor = Get-Extractor
if ($extractor) {
    Write-Host ("[INFO] Entpacker: {0} ({1})" -f $extractor.Type, $extractor.Path)
} else {
    Write-Host "[INFO] Entpacker: keiner (nur ZIP möglich)"
}

# -----------------------------------------------------
# Hauptloop – Unterarchive inklusive (Tracking gegen Endlosschleife)
# -----------------------------------------------------
$processed = New-Object 'System.Collections.Generic.HashSet[string]'
$round = 0
$ok = 0
$fail = 0

while ($round -lt $maxRounds) {
    $round++
    Write-Host ""
    Write-Host ("========== Runde {0} ==========" -f $round)

    $archives = Get-Archives -RootPath $rootPath |
        Where-Object { -not $processed.Contains($_.FullName) }

    if (-not $archives -or $archives.Count -eq 0) {
        Write-Host "[INFO] Keine weiteren Archive gefunden"
        break
    }

    foreach ($a in $archives) {
        $null = $processed.Add($a.FullName)

        $success = Expand-OneArchive -ArchivePath $a.FullName -Extractor $extractor

        if ($success) {
            if ($PSCmdlet.ShouldProcess($a.FullName, "Archiv löschen")) {
                Remove-Item -LiteralPath $a.FullName -Force
            }
            Write-Host ("[OK] Gelöscht: {0}" -f $a.FullName)
            $ok++
        }
        else {
            Write-Host ("[FAIL] Fehler: {0}" -f $a.FullName)
            $fail++
        }
    }
}

Write-Host ""
Write-Host ("[INFO] Fertig | OK={0} | FAIL={1} | Runden={2}" -f $ok, $fail, $round)
