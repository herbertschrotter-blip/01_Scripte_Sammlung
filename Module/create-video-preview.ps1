<#
ManifestHint:
  ExportFunctions = @()
  Description     = "Erstellt im Root den Ordner '00_VidPreview' und erzeugt je Video 3 Previews bei 50%, 70% und 90% der Laufzeit."
  Category        = "Media"
  Tags            = @("Videos","Preview","Thumbnail","FFmpeg","Percent","50","70","90","Recursive")
  Dependencies    = @("ffmpeg.exe")

Fehlercodes:
  E010 Abbruch durch User
  E020 Root-Ordner existiert nicht
  E030 ffmpeg.exe nicht gefunden
  E040 Videodauer konnte nicht ermittelt werden
  E100 Preview-Erzeugung fehlgeschlagen
#>

param (
    [string]$RootPath
)

# ------------------------------------------------------------
# Root-Ordner bestimmen
# ------------------------------------------------------------
if (-not $RootPath) {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Root-Ordner auswählen"

    if ($dlg.ShowDialog() -ne "OK") {
        Write-Host "E010 Abgebrochen"
        return
    }
    $root = $dlg.SelectedPath
}
else {
    $root = $RootPath
}

if (-not (Test-Path -LiteralPath $root)) {
    Write-Host ("E020 Root-Ordner existiert nicht: {0}" -f $root)
    return
}

Write-Host "`nRoot-Ordner:`n$root"

# ------------------------------------------------------------
# ffmpeg finden
# ------------------------------------------------------------
$ffmpeg = $null

$cmd = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
if ($cmd) { $ffmpeg = $cmd.Source }

if (-not $ffmpeg) {
    $local = Join-Path $PSScriptRoot "ffmpeg.exe"
    if (Test-Path -LiteralPath $local) {
        $ffmpeg = $local
    }
}

if (-not $ffmpeg) {
    Write-Host "E030 ffmpeg.exe nicht gefunden"
    return
}

Write-Host "[INFO] ffmpeg: $ffmpeg"

# ------------------------------------------------------------
# Preview-Ordner vorbereiten
# ------------------------------------------------------------
$previewFolder = Join-Path $root "00_VidPreview"

if (Test-Path -LiteralPath $previewFolder) {
    Write-Host "Video-Preview-Ordner existiert – wird geleert."
    Get-ChildItem -LiteralPath $previewFolder -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}
else {
    New-Item -ItemType Directory -Path $previewFolder -Force | Out-Null
    Write-Host "Video-Preview-Ordner erstellt: 00_VidPreview"
}

# ------------------------------------------------------------
# Hilfsfunktionen
# ------------------------------------------------------------
function Get-VideoDurationSeconds {
    param([string]$VideoPath)

    $out = & $ffmpeg -hide_banner -i $VideoPath 2>&1
    $m = [regex]::Match($out, 'Duration:\s*(\d{2}):(\d{2}):(\d{2})\.(\d+)')
    if (-not $m.Success) { return $null }

    $h = [int]$m.Groups[1].Value
    $m2 = [int]$m.Groups[2].Value
    $s = [int]$m.Groups[3].Value
    return ($h * 3600) + ($m2 * 60) + $s
}

function Format-Timestamp {
    param([double]$Seconds)
    $ts = [TimeSpan]::FromSeconds($Seconds)
    "{0:00}:{1:00}:{2:00}.{3:000}" -f $ts.Hours, $ts.Minutes, $ts.Seconds, $ts.Milliseconds
}

function SafeName([string]$s) {
    foreach ($c in [IO.Path]::GetInvalidFileNameChars()) {
        $s = $s.Replace($c, '_')
    }
    return $s
}

# ------------------------------------------------------------
# Videos finden
# ------------------------------------------------------------
$videoExt = @(".mp4",".mov",".mkv",".avi",".wmv",".m4v",".webm")

$videos = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Extension -and
        ($videoExt -contains $_.Extension.ToLowerInvariant()) -and
        ($_.Directory.FullName -ne $previewFolder)
    }

Write-Host "Gefundene Videos: $($videos.Count)"

# ------------------------------------------------------------
# Previews erzeugen (50 / 70 / 90 %)
# ------------------------------------------------------------
$ok = 0
$fail = 0

foreach ($v in $videos) {

    Write-Host "`n[VIDEO] $($v.FullName)"

    $dur = Get-VideoDurationSeconds $v.FullName
    if (-not $dur -or $dur -le 1) {
        Write-Host "E040 Dauer nicht ermittelbar"
        $fail++
        continue
    }

    $rel = $v.DirectoryName.Substring($root.Length).Trim('\')
    if (-not $rel) { $rel = "ROOT" }
    $rel = SafeName ($rel -replace '\\','_')

    $base = SafeName ([IO.Path]::GetFileNameWithoutExtension($v.Name))

    foreach ($p in @(50,60,70,80,90,95)) {

        $sec = $dur * ($p / 100)
        $ts = Format-Timestamp $sec

        $outFile = "{0}__{1}__P{2}.jpg" -f $rel, $base, $p
        $outPath = Join-Path $previewFolder $outFile

        $args = @(
            "-hide_banner","-loglevel","error",
            "-ss",$ts,
            "-i",$v.FullName,
            "-frames:v","1",
            "-q:v","2",
            $outPath
        )

        # ffmpeg direkt ausführen: korrektes Handling von Leerzeichen in Pfaden
        $null = & $ffmpeg @args 2>&1
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $outPath)) {
            $ok++
        }
        else {
            Write-Host "E100 Fehler bei Preview $p%"
            Write-Host ("[DBG] Input:  {0}" -f $v.FullName)
            Write-Host ("[DBG] Output: {0}" -f $outPath)
            $fail++
        }
    }
}

Write-Host "`nFertig."
Write-Host "Erstellte Previews: $ok"
Write-Host "Fehler: $fail"
