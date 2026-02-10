<#
ManifestHint:
  ExportFunctions = @("New-VideoThumbnail","Get-VideoThumbnailPath","Test-IsVideoFile","Get-VideoMetadata")
  Description     = "Video-Thumbnail-Generierung mit FFmpeg und Metadata-Analyse"
  Category        = "Media"
  Tags            = @("Video","Thumbnail","FFmpeg","Metadata","Codec","BrowserCompatibility")
  Dependencies    = @("FFmpeg")

Zweck:
  - Video-Thumbnails generieren (140x140px JPG)
  - Thumbnails in .thumbs Ordner speichern (versteckt)
  - Video-Metadaten auslesen (Codec, Format, Auflösung, Dauer)
  - Browser-Kompatibilität prüfen
  - FFmpeg/FFprobe Integration
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Video-Datei prüfen
# ------------------------------------------------------------
function Test-IsVideoFile {
  <#
  .SYNOPSIS
  Prüft ob eine Datei ein Video ist (anhand Extension)
  
  .PARAMETER Path
  Dateipfad oder Dateiname
  
  .OUTPUTS
  Boolean - True wenn Video, sonst False
  #>
  
  param([string]$Path)
  
  $videoExt = @(
    ".mp4",".mov",".avi",".mkv",".webm",".m4v",".wmv",".flv",
    ".mpg",".mpeg",".3gp"
  )
  
  $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
  return $videoExt -contains $ext
}

# ------------------------------------------------------------
# Thumbnail-Pfad ermitteln
# ------------------------------------------------------------
function Get-VideoThumbnailPath {
  <#
  .SYNOPSIS
  Gibt den Pfad zum Thumbnail zurück (video.ext.jpg)
  
  .PARAMETER VideoPath
  Pfad zur Video-Datei
  
  .OUTPUTS
  String - Pfad zum Thumbnail (.thumbs/video.ext.jpg)
  #>
  
  param(
    [Parameter(Mandatory)]
    [string]$VideoPath
  )
  
  $dir = Split-Path -Parent $VideoPath
  $filename = Split-Path -Leaf $VideoPath
  $thumbsDir = Join-Path $dir ".thumbs"
  $thumbName = "$filename.jpg"
  
  return Join-Path $thumbsDir $thumbName
}

# ------------------------------------------------------------
# .thumbs Ordner erstellen
# ------------------------------------------------------------
function Ensure-ThumbsDirectory {
  <#
  .SYNOPSIS
  Erstellt .thumbs Ordner falls nicht vorhanden (mit Hidden Attribut)
  
  .PARAMETER VideoPath
  Pfad zur Video-Datei
  #>
  
  param([string]$VideoPath)
  
  $dir = Split-Path -Parent $VideoPath
  $thumbsDir = Join-Path $dir ".thumbs"
  
  if (-not (Test-Path -LiteralPath $thumbsDir)) {
    $folder = New-Item -Path $thumbsDir -ItemType Directory -Force
    $folder.Attributes = $folder.Attributes -bor [System.IO.FileAttributes]::Hidden
  }
}

# ------------------------------------------------------------
# FFmpeg-Pfad finden
# ------------------------------------------------------------
function Find-FFmpegPath {
  <#
  .SYNOPSIS
  Sucht FFmpeg in Tools/ oder System-PATH
  
  .PARAMETER ProjectRoot
  Projekt-Root-Verzeichnis
  
  .OUTPUTS
  String - Pfad zu ffmpeg.exe
  #>
  
  param([string]$ProjectRoot)
  
  # Mögliche Pfade (in Prioritätsreihenfolge)
  $paths = @(
    (Join-Path $ProjectRoot "Tools\ffmpeg.exe"),
    (Join-Path $ProjectRoot "Tools\ffmpeg\ffmpeg.exe"),
    (Join-Path $ProjectRoot "Tools\ffmpeg\bin\ffmpeg.exe")
  )
  
  foreach ($p in $paths) {
    if (Test-Path -LiteralPath $p) {
      Write-Verbose "FFmpeg gefunden: $p"
      return $p
    }
  }
  
  # Fallback: System-FFmpeg (falls in PATH)
  try {
    $result = & where.exe ffmpeg 2>$null
    if ($result) { 
      Write-Verbose "FFmpeg in System-PATH gefunden: $result"
      return "ffmpeg" 
    }
  } catch { }
  
  throw "FFmpeg nicht gefunden. Bitte in Tools\ ablegen."
}

# ------------------------------------------------------------
# Video-Dauer ermitteln
# ------------------------------------------------------------
function Get-VideoDuration {
  <#
  .SYNOPSIS
  Ermittelt die Länge eines Videos in Sekunden
  
  .PARAMETER VideoPath
  Pfad zur Video-Datei
  
  .PARAMETER FFmpegPath
  Pfad zu FFmpeg (optional)
  
  .OUTPUTS
  Double - Dauer in Sekunden
  #>
  
  param(
    [Parameter(Mandatory)]
    [string]$VideoPath,
    
    [string]$FFmpegPath
  )
  
  # FFmpeg finden
  if ([string]::IsNullOrWhiteSpace($FFmpegPath)) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $FFmpegPath = Find-FFmpegPath -ProjectRoot $projectRoot
  }
  
  # FFprobe bevorzugen (schneller)
  $ffprobePath = $FFmpegPath -replace "ffmpeg\.exe$", "ffprobe.exe"
  
  if (Test-Path -LiteralPath $ffprobePath) {
    try {
      $output = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "`"$VideoPath`"" 2>&1
      $duration = [double]$output
      if ($duration -gt 0) {
        return $duration
      }
    } catch {
      Write-Verbose "FFprobe fehlgeschlagen, verwende FFmpeg: $($_.Exception.Message)"
    }
  }
  
  # Fallback: FFmpeg
  $output = & $FFmpegPath -i "`"$VideoPath`"" 2>&1 | Out-String
  
  if ($output -match "Duration:\s*(\d{2}):(\d{2}):(\d{2})\.(\d{2})") {
    $hours = [int]$matches[1]
    $minutes = [int]$matches[2]
    $seconds = [int]$matches[3]
    return ($hours * 3600) + ($minutes * 60) + $seconds
  }
  
  throw "Konnte Video-Dauer nicht ermitteln"
}

# ------------------------------------------------------------
# Video-Metadaten auslesen
# ------------------------------------------------------------
function Get-VideoMetadata {
  <#
  .SYNOPSIS
  Liest Video-Metadaten aus (Codec, Format, Größe, Dauer, Browser-Kompatibilität)
  
  .PARAMETER VideoPath
  Pfad zur Video-Datei
  
  .PARAMETER FFmpegPath
  Pfad zu FFmpeg (optional)
  
  .OUTPUTS
  PSCustomObject mit: Codec, Format, Width, Height, Duration, Bitrate, Size, BrowserCompatibility, CompatibilityIcon
  #>
  
  param(
    [Parameter(Mandatory)]
    [string]$VideoPath,
    
    [string]$FFmpegPath
  )
  
  # FFmpeg finden
  if ([string]::IsNullOrWhiteSpace($FFmpegPath)) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $FFmpegPath = Find-FFmpegPath -ProjectRoot $projectRoot
  }
  
  if (-not (Test-Path -LiteralPath $VideoPath)) {
    throw "Video nicht gefunden: $VideoPath"
  }
  
  # FFprobe bevorzugen, falls verfügbar
  $ffprobePath = $FFmpegPath -replace "ffmpeg\.exe$", "ffprobe.exe"
  
  $output = ""
  
  if (Test-Path -LiteralPath $ffprobePath) {
    # FFprobe verwenden (detaillierter)
    try {
      $output = & $ffprobePath -v error -show_entries stream=codec_name,codec_type,width,height,bit_rate -show_entries format=duration,size,format_name -of default=noprint_wrappers=1 "`"$VideoPath`"" 2>&1 | Out-String
    } catch {
      Write-Verbose "FFprobe fehlgeschlagen, verwende FFmpeg: $($_.Exception.Message)"
    }
  }
  
  # Fallback: FFmpeg
  if ([string]::IsNullOrWhiteSpace($output)) {
    try {
      $output = & $FFmpegPath -i "`"$VideoPath`"" 2>&1 | Out-String
    } catch {
      throw "FFmpeg/FFprobe fehlgeschlagen: $($_.Exception.Message)"
    }
  }
  
  # Parsing
  $videoCodec = "unknown"
  $audioCodec = "unknown"
  $width = 0
  $height = 0
  $duration = 0.0
  $bitrate = 0
  $fileSize = 0
  $format = [System.IO.Path]::GetExtension($VideoPath).TrimStart('.').ToUpperInvariant()
  
  # Video-Codec
  if ($output -match "Video:\s*([a-zA-Z0-9_]+)") {
    $videoCodec = $matches[1].ToLowerInvariant()
  } elseif ($output -match "codec_name=([^\r\n]+)") {
    $videoCodec = $matches[1].ToLowerInvariant()
  }
  
  # Audio-Codec
  if ($output -match "Audio:\s*([a-zA-Z0-9_]+)") {
    $audioCodec = $matches[1].ToLowerInvariant()
  }
  
  # Auflösung
  if ($output -match "(\d{2,5})x(\d{2,5})") {
    $width = [int]$matches[1]
    $height = [int]$matches[2]
  } elseif ($output -match "width=(\d+)") {
    $width = [int]$matches[1]
    if ($output -match "height=(\d+)") {
      $height = [int]$matches[1]
    }
  }
  
  # Dauer
  if ($output -match "Duration:\s*(\d{2}):(\d{2}):(\d{2})\.(\d{2})") {
    $hours = [int]$matches[1]
    $minutes = [int]$matches[2]
    $seconds = [int]$matches[3]
    $duration = ($hours * 3600) + ($minutes * 60) + $seconds
  } elseif ($output -match "duration=([0-9.]+)") {
    $duration = [double]$matches[1]
  }
  
  # Bitrate
  if ($output -match "bitrate:\s*(\d+)\s*kb/s") {
    $bitrate = [int]$matches[1]
  } elseif ($output -match "bit_rate=(\d+)") {
    $bitrate = [int]([int]$matches[1] / 1000)  # bps → kbps
  }
  
  # Dateigröße
  $fileInfo = Get-Item -LiteralPath $VideoPath
  $fileSize = $fileInfo.Length
  
  # Browser-Kompatibilität prüfen
  $compat = Get-BrowserCompatibility -VideoCodec $videoCodec -AudioCodec $audioCodec -Format $format
  
  return [PSCustomObject]@{
    FileName            = [System.IO.Path]::GetFileName($VideoPath)
    Format              = $format
    VideoCodec          = $videoCodec
    AudioCodec          = $audioCodec
    Width               = $width
    Height              = $height
    Resolution          = "${width}x${height}"
    Duration            = [Math]::Round($duration, 1)
    DurationFormatted   = Format-Duration -Seconds $duration
    Bitrate             = $bitrate
    BitrateFormatted    = "${bitrate} kb/s"
    FileSize            = $fileSize
    FileSizeFormatted   = Format-FileSize -Bytes $fileSize
    BrowserCompatibility = $compat.Level
    CompatibilityIcon   = $compat.Icon
    CompatibilityText   = $compat.Text
  }
}

# ------------------------------------------------------------
# Browser-Kompatibilität prüfen
# ------------------------------------------------------------
function Get-BrowserCompatibility {
  param(
    [string]$VideoCodec,
    [string]$AudioCodec,
    [string]$Format
  )
  
  # Normalisieren
  $vc = $VideoCodec.ToLowerInvariant()
  $ac = $AudioCodec.ToLowerInvariant()
  $fmt = $Format.ToLowerInvariant()
  
  # Perfekte Kompatibilität
  if (($vc -eq "h264" -or $vc -eq "avc") -and ($fmt -in @("mp4","m4v","mov"))) {
    return @{ Level = "excellent"; Icon = "✅"; Text = "Perfekt kompatibel (H.264)" }
  }
  
  if (($vc -in @("vp8","vp9")) -and $fmt -eq "webm") {
    return @{ Level = "excellent"; Icon = "✅"; Text = "Perfekt kompatibel (VP8/VP9)" }
  }
  
  # Gute Kompatibilität
  if ($vc -in @("h264","avc","h265","hevc","vp8","vp9")) {
    return @{ Level = "good"; Icon = "✅"; Text = "Gut kompatibel" }
  }
  
  # Eingeschränkte Kompatibilität
  if ($vc -in @("mpeg4","msmpeg4","wmv1","wmv2","wmv3","xvid","divx","mjpeg")) {
    return @{ Level = "limited"; Icon = "⚠️"; Text = "Eingeschränkt (alter Codec)" }
  }
  
  # Keine Kompatibilität
  if ($vc -in @("rv40","rv30","theora","vp6","indeo","sorenson") -or $fmt -eq "flv") {
    return @{ Level = "none"; Icon = "❌"; Text = "Nicht kompatibel" }
  }
  
  # Unbekannt
  return @{ Level = "unknown"; Icon = "❓"; Text = "Unbekannt" }
}

# ------------------------------------------------------------
# Helper: Dauer formatieren
# ------------------------------------------------------------
function Format-Duration {
  param([double]$Seconds)
  
  $hours = [int][Math]::Floor($Seconds / 3600)
  $minutes = [int][Math]::Floor(($Seconds % 3600) / 60)
  $secs = [int][Math]::Floor($Seconds % 60)
  
  if ($hours -gt 0) {
    return ("{0:00}:{1:00}:{2:00}" -f $hours, $minutes, $secs)
  } else {
    return ("{0:00}:{1:00}" -f $minutes, $secs)
  }
}

# ------------------------------------------------------------
# Helper: Dateigröße formatieren
# ------------------------------------------------------------
function Format-FileSize {
  param([long]$Bytes)
  
  if ($Bytes -ge 1GB) {
    $val = [double]($Bytes / 1GB)
    return ("{0:0.00} GB" -f $val)
  } elseif ($Bytes -ge 1MB) {
    $val = [double]($Bytes / 1MB)
    return ("{0:0.00} MB" -f $val)
  } elseif ($Bytes -ge 1KB) {
    $val = [double]($Bytes / 1KB)
    return ("{0:0.00} KB" -f $val)
  } else {
    return "$Bytes Bytes"
  }
}

# ------------------------------------------------------------
# Video-Thumbnail generieren
# ------------------------------------------------------------
function New-VideoThumbnail {
  <#
  .SYNOPSIS
  Generiert ein Thumbnail für ein Video (140x140px JPG)
  
  .PARAMETER VideoPath
  Pfad zur Video-Datei
  
  .PARAMETER FFmpegPath
  Pfad zu FFmpeg (optional, wird automatisch gesucht)
  
  .PARAMETER Size
  Thumbnail-Größe in Pixel (Standard: 140)
  
  .PARAMETER Quality
  JPEG-Qualität 1-31 (1=beste, 31=schlechteste, Standard: 5)
  
  .OUTPUTS
  String - Pfad zum generierten Thumbnail
  #>
  
  param(
    [Parameter(Mandatory)]
    [string]$VideoPath,
    
    [string]$FFmpegPath,
    [int]$Size = 140,
    [int]$Quality = 5
  )
  
  # FFmpeg finden
  if ([string]::IsNullOrWhiteSpace($FFmpegPath)) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $FFmpegPath = Find-FFmpegPath -ProjectRoot $projectRoot
  }
  
  if (-not (Test-Path -LiteralPath $VideoPath)) {
    throw "Video nicht gefunden: $VideoPath"
  }
  
  Write-Verbose "Video: $VideoPath"
  
  # .thumbs Ordner erstellen
  Ensure-ThumbsDirectory -VideoPath $VideoPath
  
  # Thumbnail-Pfad
  $thumbPath = Get-VideoThumbnailPath -VideoPath $VideoPath
  
  # Falls Thumbnail bereits existiert, nichts tun
  if (Test-Path -LiteralPath $thumbPath) {
    Write-Verbose "Thumbnail existiert bereits: $thumbPath"
    return $thumbPath
  }
  
  # Video-Dauer ermitteln
  try {
    $duration = Get-VideoDuration -VideoPath $VideoPath -FFmpegPath $FFmpegPath
  } catch {
    Write-Warning "Konnte Dauer nicht ermitteln: $($_.Exception.Message)"
    $duration = 60  # Fallback
  }
  
  Write-Verbose "Dauer: $duration Sekunden"
  
  # Zufällige Position zwischen 40% und 70%
  $minPos = [Math]::Max(1, $duration * 0.4)
  $maxPos = [Math]::Min($duration - 1, $duration * 0.7)
  $seekSeconds = [Math]::Floor((Get-Random -Minimum $minPos -Maximum $maxPos))
  
  Write-Verbose "Position: $([Math]::Round($seekSeconds / $duration * 100))% = $seekSeconds Sekunden"
  Write-Verbose "Thumbnail: $thumbPath"
  
  try {
    # FFmpeg Command:
    # -ss: Seek to position
    # -i: Input file
    # -vframes 1: Extract 1 frame
    # -update 1: Suppress image sequence warning
    # -vf scale: Scale to SIZExSIZE
    # -q:v: Quality (lower = better)
    
    $arguments = @(
      "-ss", $seekSeconds,
      "-i", "`"$VideoPath`"",
      "-vframes", "1",
      "-update", "1",
      "-vf", "scale=${Size}:${Size}:force_original_aspect_ratio=increase,crop=${Size}:${Size}",
      "-q:v", $Quality.ToString(),
      "-y",
      "`"$thumbPath`""
    )
    
    $process = Start-Process -FilePath $FFmpegPath -ArgumentList $arguments -NoNewWindow -Wait -PassThru
    
    if ($process.ExitCode -ne 0) {
      throw "FFmpeg fehlgeschlagen (Exit Code: $($process.ExitCode))"
    }
    
    if (-not (Test-Path -LiteralPath $thumbPath)) {
      throw "Thumbnail wurde nicht erstellt"
    }
    
    Write-Verbose "Thumbnail erfolgreich erstellt: $thumbPath"
    return $thumbPath
    
  } catch {
    Write-Warning "Fehler beim Generieren des Thumbnails für $VideoPath : $($_.Exception.Message)"
    return $null
  }
}

# ------------------------------------------------------------
# Bulk-Thumbnail-Generierung
# ------------------------------------------------------------
function New-VideoThumbnailsBulk {
  <#
  .SYNOPSIS
  Generiert Thumbnails für alle Videos in einem Ordner
  
  .PARAMETER FolderPath
  Ordner mit Videos
  
  .PARAMETER FFmpegPath
  Pfad zu FFmpeg (optional)
  
  .OUTPUTS
  PSCustomObject mit Created, Skipped, Failed
  #>
  
  param(
    [Parameter(Mandatory)]
    [string]$FolderPath,
    
    [string]$FFmpegPath
  )
  
  if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
    throw "Ordner nicht gefunden: $FolderPath"
  }
  
  $videos = Get-ChildItem -LiteralPath $FolderPath -File | Where-Object { Test-IsVideoFile -Path $_.FullName }
  
  $created = 0
  $skipped = 0
  $failed = 0
  
  foreach ($video in $videos) {
    $thumbPath = Get-VideoThumbnailPath -VideoPath $video.FullName
    
    if (Test-Path -LiteralPath $thumbPath) {
      $skipped++
    } else {
      try {
        $result = New-VideoThumbnail -VideoPath $video.FullName -FFmpegPath $FFmpegPath -Verbose:$false
        if ($result) { $created++ } else { $failed++ }
      } catch {
        $failed++
        Write-Warning "Fehler bei $($video.Name): $($_.Exception.Message)"
      }
    }
  }
  
  return [PSCustomObject]@{
    Created = $created
    Skipped = $skipped
    Failed = $failed
    Total = $videos.Count
  }
}