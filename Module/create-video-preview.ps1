<#
ManifestHint:
  ExportFunctions = @()
  Description     = "Erstellt im Root den Ordner '00_VidPreview' und erzeugt je Video 6 Previews bei 50%, 60%, 70%, 80%, 90% und 95% der Laufzeit. Ordner wird nur erstellt, wenn Videos gefunden wurden."
  Category        = "Media"
  Tags            = @("Videos","Preview","Thumbnail","FFmpeg","Percent","50","60","70","80","90","95","Recursive")
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
# Hilfsfunktionen
# ------------------------------------------------------------
function Get-VideoDurationSeconds {
    param([string]$VideoPath)

    # ffmpeg schreibt Infos nach stderr -> alles einsammeln
    $out = & $ffmpeg -hide_banner -i $VideoPath 2>&1

    # Beispiel: Duration: 00:01:23.45,
    $m = [regex]::Match($out, 'Duration:\s*(\d{2}):(\d{2}):(\d{2})\.(\d+)')
    if (-not $m.Success) { return $null }

    $hh = [int]$m.Groups[1].Value
    $mm = [int]$m.Groups[2].Value
    $ss = [int]$m.Groups[3].Value

    $fracRaw = $m.Groups[4].Value
    $ms = 0
    if ($fracRaw.Length -ge 3) { $ms = [int]$fracRaw.Substring(0,3) }
    elseif ($fracRaw.Length -eq 2) { $ms = [int]($fracRaw + "0") }
    elseif ($fracRaw.Length -eq 1) { $ms = [int]($fracRaw + "00") }

    return ($hh * 3600) + ($mm * 60) + $ss + ($ms / 1000.0)
}

function Format-Timestamp {
    param([double]$Seconds)

    if ($Seconds -lt 0) { $Seconds = 0 }
    $ts = [TimeSpan]::FromSeconds($Seconds)

    # ffmpeg akzeptiert HH:MM:SS.mmm
    "{0:00}:{1:00}:{2:00}.{3:000}" -f $ts.Hours, $ts.Minutes, $ts.Seconds, $ts.Milliseconds
}

function SafeName {
    param([string]$Text)

    $invalid = [IO.Path]::GetInvalidFileNameChars()
    foreach ($ch in $invalid) {
        $Text = $Text.Replace($ch, '_')
    }
    return $Text
}

# ------------------------------------------------------------
# Videos finden (rekursiv) – Preview-Ordner wird später ggf. erstellt
# ------------------------------------------------------------
$previewFolder = Join-Path $root "00_VidPreview"
$videoExt = @(".mp4",".mov",".mkv",".avi",".wmv",".m4v",".webm")

$videos = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Extension -and
        ($videoExt -contains $_.Extension.ToLowerInvariant()) -and
        # objektbasiert, kein -like/-notlike -> sicher bei [] im Pfad
        ($_.Directory.FullName -ne $previewFolder)
    } |
    Sort-Object FullName

Write-Host "Gefundene Videos: $($videos.Count)"

# Ordner nur anlegen, wenn tatsächlich Videos existieren
if (-not $videos -or $videos.Count -eq 0) {
    Write-Host "Keine Videos gefunden – kein Video-Preview-Ordner erstellt."
    return
}

# ------------------------------------------------------------
# Preview-Ordner jetzt erst vorbereiten
# ------------------------------------------------------------
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
# Previews erzeugen (50 / 60 / 70 / 80 / 90 / 95 %)
# ------------------------------------------------------------
$ok = 0
$fail = 0

foreach ($v in $videos) {

    Write-Host "`n[VIDEO] $($v.FullName)"

    $dur = Get-VideoDurationSeconds $v.FullName
    if (-not $dur -or $dur -le 0.5) {
        Write-Host "E040 Dauer nicht ermittelbar"
        $fail++
        continue
    }

    $rel = $v.DirectoryName.Substring($root.Length).Trim('\')
    if (-not $rel) { $rel = "ROOT" }
    $relSafe = SafeName ($rel -replace '\\','_')

    $base = SafeName ([IO.Path]::GetFileNameWithoutExtension($v.Name))

    foreach ($p in @(50,60,70,80,90,95)) {

        $sec = [double]$dur * ([double]$p / 100.0)
        $ts = Format-Timestamp $sec

        $outFile = "{0}__{1}__P{2}.jpg" -f $relSafe, $base, $p
        $outPath = Join-Path $previewFolder $outFile

        $args = @(
            "-hide_banner","-loglevel","error",
            "-ss",$ts,
            "-i",$v.FullName,
            "-frames:v","1",
            "-q:v","2",
            $outPath
        )

        # Direktaufruf: korrekt bei Leerzeichen in Pfaden
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
