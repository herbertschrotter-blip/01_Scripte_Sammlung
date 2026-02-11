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
  - Lazy Video Conversion (WMV/DivX/XviD → H.264)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-IsVideoFile {
  param([string]$Path)
  $videoExt = @(".mp4",".mov",".avi",".mkv",".webm",".m4v",".wmv",".flv",".mpg",".mpeg",".3gp")
  $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
  return $videoExt -contains $ext
}

function Get-VideoThumbnailPath {
  param([Parameter(Mandatory)][string]$VideoPath)
  $dir = Split-Path -Parent $VideoPath
  $filename = Split-Path -Leaf $VideoPath
  $thumbsDir = Join-Path $dir ".thumbs"
  $thumbName = "$filename.jpg"
  return Join-Path $thumbsDir $thumbName
}

function Ensure-ThumbsDirectory {
  param([string]$VideoPath)
  $dir = Split-Path -Parent $VideoPath
  $thumbsDir = Join-Path $dir ".thumbs"
  if (-not (Test-Path -LiteralPath $thumbsDir)) {
    $folder = New-Item -Path $thumbsDir -ItemType Directory -Force
    $folder.Attributes = $folder.Attributes -bor [System.IO.FileAttributes]::Hidden
  }
}

function Find-FFmpegPath {
  param([string]$ProjectRoot)
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
  try {
    $result = & where.exe ffmpeg 2>$null
    if ($result) { 
      Write-Verbose "FFmpeg in System-PATH gefunden: $result"
      return "ffmpeg" 
    }
  } catch { }
  throw "FFmpeg nicht gefunden. Bitte in Tools\ ablegen."
}

function Get-VideoDuration {
  param(
    [Parameter(Mandatory)][string]$VideoPath,
    [string]$FFmpegPath
  )
  if ([string]::IsNullOrWhiteSpace($FFmpegPath)) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $FFmpegPath = Find-FFmpegPath -ProjectRoot $projectRoot
  }
  $ffprobePath = $FFmpegPath -replace "ffmpeg\.exe$", "ffprobe.exe"
  if (Test-Path -LiteralPath $ffprobePath) {
    try {
      $output = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $VideoPath 2>&1
      $duration = [double]$output
      if ($duration -gt 0) { return $duration }
    } catch {
      Write-Verbose "FFprobe fehlgeschlagen, verwende FFmpeg: $($_.Exception.Message)"
    }
  }
  $output = & $FFmpegPath -i $VideoPath 2>&1 | Out-String
  if ($output -match "Duration:\s*(\d{2}):(\d{2}):(\d{2})\.(\d{2})") {
    $hours = [int]$matches[1]
    $minutes = [int]$matches[2]
    $seconds = [int]$matches[3]
    return ($hours * 3600) + ($minutes * 60) + $seconds
  }
  throw "Konnte Video-Dauer nicht ermitteln"
}

function Get-VideoMetadata {
  param(
    [Parameter(Mandatory)][string]$VideoPath,
    [string]$FFmpegPath
  )
  if ([string]::IsNullOrWhiteSpace($FFmpegPath)) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $FFmpegPath = Find-FFmpegPath -ProjectRoot $projectRoot
  }
  if (-not (Test-Path -LiteralPath $VideoPath)) {
    throw "Video nicht gefunden: $VideoPath"
  }
  $ffprobePath = $FFmpegPath -replace "ffmpeg\.exe$", "ffprobe.exe"
  $output = ""
  if (Test-Path -LiteralPath $ffprobePath) {
    try {
      $output = & $ffprobePath -v error -show_entries stream=codec_name,codec_type,width,height,bit_rate -show_entries format=duration,size,format_name -of default=noprint_wrappers=1 $VideoPath 2>&1 | Out-String
    } catch {
      Write-Verbose "FFprobe fehlgeschlagen, verwende FFmpeg: $($_.Exception.Message)"
    }
  }
  if ([string]::IsNullOrWhiteSpace($output)) {
    try {
      $output = & $FFmpegPath -i $VideoPath 2>&1 | Out-String
    } catch {
      throw "FFmpeg/FFprobe fehlgeschlagen: $($_.Exception.Message)"
    }
  }
  $videoCodec = "unknown"
  $audioCodec = "unknown"
  $width = 0
  $height = 0
  $duration = 0.0
  $bitrate = 0
  $fileSize = 0
  $format = [System.IO.Path]::GetExtension($VideoPath).TrimStart('.').ToUpperInvariant()
  if ($output -match "Video:\s*([a-zA-Z0-9_]+)") {
    $videoCodec = $matches[1].ToLowerInvariant()
  } elseif ($output -match "codec_name=([^\r\n]+)") {
    $videoCodec = $matches[1].ToLowerInvariant()
  }
  if ($output -match "Audio:\s*([a-zA-Z0-9_]+)") {
    $audioCodec = $matches[1].ToLowerInvariant()
  }
  if ($output -match "(\d{2,5})x(\d{2,5})") {
    $width = [int]$matches[1]
    $height = [int]$matches[2]
  } elseif ($output -match "width=(\d+)") {
    $width = [int]$matches[1]
    if ($output -match "height=(\d+)") {
      $height = [int]$matches[1]
    }
  }
  if ($output -match "Duration:\s*(\d{2}):(\d{2}):(\d{2})\.(\d{2})") {
    $hours = [int]$matches[1]
    $minutes = [int]$matches[2]
    $seconds = [int]$matches[3]
    $duration = ($hours * 3600) + ($minutes * 60) + $seconds
  } elseif ($output -match "duration=([0-9.]+)") {
    $duration = [double]$matches[1]
  }
  if ($output -match "bitrate:\s*(\d+)\s*kb/s") {
    $bitrate = [int]$matches[1]
  } elseif ($output -match "bit_rate=(\d+)") {
    $bitrate = [int]([int]$matches[1] / 1000)
  }
  $fileInfo = Get-Item -LiteralPath $VideoPath
  $fileSize = $fileInfo.Length
  $compat = Get-BrowserCompatibility -VideoCodec $videoCodec -AudioCodec $audioCodec -Format $format
  return [PSCustomObject]@{
    FileName = [System.IO.Path]::GetFileName($VideoPath)
    Format = $format
    VideoCodec = $videoCodec
    AudioCodec = $audioCodec
    Width = $width
    Height = $height
    Resolution = "${width}x${height}"
    Duration = [Math]::Round($duration, 1)
    DurationFormatted = Format-Duration -Seconds $duration
    Bitrate = $bitrate
    BitrateFormatted = "${bitrate} kb/s"
    FileSize = $fileSize
    FileSizeFormatted = Format-FileSize -Bytes $fileSize
    BrowserCompatibility = $compat.Level
    CompatibilityIcon = $compat.Icon
    CompatibilityText = $compat.Text
  }
}

function Get-BrowserCompatibility {
  param([string]$VideoCodec, [string]$AudioCodec, [string]$Format)
  $vc = $VideoCodec.ToLowerInvariant()
  $ac = $AudioCodec.ToLowerInvariant()
  $fmt = $Format.ToLowerInvariant()
  if (($vc -eq "h264" -or $vc -eq "avc") -and ($fmt -in @("mp4","m4v","mov"))) {
    return @{ Level = "excellent"; Icon = "✅"; Text = "Perfekt kompatibel (H.264)" }
  }
  if (($vc -in @("vp8","vp9")) -and $fmt -eq "webm") {
    return @{ Level = "excellent"; Icon = "✅"; Text = "Perfekt kompatibel (VP8/VP9)" }
  }
  if ($vc -in @("h264","avc","h265","hevc","vp8","vp9")) {
    return @{ Level = "good"; Icon = "✅"; Text = "Gut kompatibel" }
  }
  if ($vc -in @("mpeg4","msmpeg4","wmv1","wmv2","wmv3","xvid","divx","mjpeg")) {
    return @{ Level = "limited"; Icon = "⚠️"; Text = "Eingeschränkt (alter Codec)" }
  }
  if ($vc -in @("rv40","rv30","theora","vp6","indeo","sorenson") -or $fmt -eq "flv") {
    return @{ Level = "none"; Icon = "❌"; Text = "Nicht kompatibel" }
  }
  return @{ Level = "unknown"; Icon = "❓"; Text = "Unbekannt" }
}

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

function Format-FileSize {
  param([long]$Bytes)
  if ($Bytes -ge 1GB) {
    return ("{0:0.00} GB" -f [double]($Bytes / 1GB))
  } elseif ($Bytes -ge 1MB) {
    return ("{0:0.00} MB" -f [double]($Bytes / 1MB))
  } elseif ($Bytes -ge 1KB) {
    return ("{0:0.00} KB" -f [double]($Bytes / 1KB))
  } else {
    return "$Bytes Bytes"
  }
}

function New-VideoThumbnail {
  param(
    [Parameter(Mandatory)][string]$VideoPath,
    [string]$FFmpegPath,
    [int]$Size = 140,
    [int]$Quality = 5
  )
  if ([string]::IsNullOrWhiteSpace($FFmpegPath)) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $FFmpegPath = Find-FFmpegPath -ProjectRoot $projectRoot
  }
  if (-not (Test-Path -LiteralPath $VideoPath)) {
    throw "Video nicht gefunden: $VideoPath"
  }
  Write-Verbose "Video: $VideoPath"
  Ensure-ThumbsDirectory -VideoPath $VideoPath
  $thumbPath = Get-VideoThumbnailPath -VideoPath $VideoPath
  if (Test-Path -LiteralPath $thumbPath) {
    Write-Verbose "Thumbnail existiert bereits: $thumbPath"
    return $thumbPath
  }
  try {
    $duration = Get-VideoDuration -VideoPath $VideoPath -FFmpegPath $FFmpegPath
  } catch {
    Write-Warning "Konnte Dauer nicht ermitteln: $($_.Exception.Message)"
    $duration = 60
  }
  Write-Verbose "Dauer: $duration Sekunden"
  $minPos = [Math]::Max(1, $duration * 0.4)
  $maxPos = [Math]::Min($duration - 1, $duration * 0.7)
  $seekSeconds = [Math]::Floor((Get-Random -Minimum $minPos -Maximum $maxPos))
  Write-Verbose "Position: $([Math]::Round($seekSeconds / $duration * 100))% = $seekSeconds Sekunden"
  Write-Verbose "Thumbnail: $thumbPath"
  try {
    $arguments = @(
      "-ss", $seekSeconds,
      "-i", $VideoPath,
      "-vframes", "1",
      "-update", "1",
      "-vf", "scale=${Size}:${Size}:force_original_aspect_ratio=increase,crop=${Size}:${Size}",
      "-q:v", $Quality.ToString(),
      "-y",
      $thumbPath
    )
# FFmpeg direkt aufrufen (besser für Pfade mit Leerzeichen)
& $FFmpegPath @arguments *>&1 | Out-Null
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
  throw "FFmpeg fehlgeschlagen (Exit Code: $exitCode)"
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

function New-VideoThumbnailsBulk {
  param(
    [Parameter(Mandatory)][string]$FolderPath,
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

function Get-ConvertedVideoPath {
  param([Parameter(Mandatory)][string]$VideoPath)
  $dir = Split-Path -Parent $VideoPath
  $thumbsDir = Join-Path $dir ".thumbs"
  if (-not (Test-Path -LiteralPath $thumbsDir)) {
    New-Item -Path $thumbsDir -ItemType Directory -Force | Out-Null
    try {
      (Get-Item -LiteralPath $thumbsDir -Force).Attributes = "Hidden"
    } catch { }
  }
  $fileName = [System.IO.Path]::GetFileName($VideoPath)
  $convertedName = [System.IO.Path]::GetFileNameWithoutExtension($fileName) + "_h264.mp4"
  return Join-Path $thumbsDir $convertedName
}

function Get-ConvertedHLSPath {
  param([Parameter(Mandatory)][string]$VideoPath)
  
  $dir = Split-Path -Parent $VideoPath
  $thumbsDir = Join-Path $dir ".thumbs"
  
  if (-not (Test-Path -LiteralPath $thumbsDir)) {
    New-Item -Path $thumbsDir -ItemType Directory -Force | Out-Null
    try {
      (Get-Item -LiteralPath $thumbsDir -Force).Attributes = "Hidden"
    } catch { }
  }
  
  $fileName = [System.IO.Path]::GetFileName($VideoPath)
  $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
  $playlistName = "${baseName}_h264.m3u8"
  
  return Join-Path $thumbsDir $playlistName
}

function Convert-VideoToH264 {
  param(
    [Parameter(Mandatory)][string]$VideoPath,
    [string]$OutputPath
  )
  
  if (-not (Test-Path -LiteralPath $VideoPath)) {
    throw "Video nicht gefunden: $VideoPath"
  }
  
  $projectRoot = Split-Path -Parent $PSScriptRoot
  $ffmpeg = Find-FFmpegPath -ProjectRoot $projectRoot
  if (-not $ffmpeg) {
    throw "FFmpeg nicht gefunden"
  }
  
  # Output-Verzeichnis erstellen
  $outDir = Split-Path -Parent $OutputPath
  if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null
  }
  
  # HLS-Ausgabe (Playlist + Chunks)
  $hlsDir = $outDir
  $baseName = [System.IO.Path]::GetFileNameWithoutExtension($OutputPath)
  $playlistPath = Join-Path $hlsDir "$baseName.m3u8"
  $segmentPattern = Join-Path $hlsDir "${baseName}_%03d.ts"
  
  Write-Host "[CONVERT] Starte HLS-Conversion: $(Split-Path -Leaf $VideoPath)" -ForegroundColor Cyan
  
  # FFmpeg-Befehl: WMV -> HLS (2-Sekunden Chunks)
  $args = @(
    "-i"
    $VideoPath
    "-c:v"
    "libx264"
    "-preset"
    "veryfast"
    "-crf"
    "26"
    "-c:a"
    "aac"
    "-b:a"
    "96k"
    "-f"
    "hls"
    "-hls_time"
    "2"
    "-hls_list_size"
    "0"
    "-hls_flags"
    "append_list"
    "-hls_segment_filename"
    $segmentPattern
    "-y"
    $playlistPath
  )
  
# FFmpeg direkt aufrufen (besser für Pfade mit Leerzeichen)
& $ffmpeg @args *>&1 | Out-Host
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
  throw "FFmpeg-Fehler: Exit Code $exitCode"
}
  
  # Prüfen ob Playlist erstellt wurde
  if (Test-Path -LiteralPath $playlistPath) {
    Write-Host "[CONVERT] HLS-Playlist erstellt: $playlistPath" -ForegroundColor Green
    
    # Erstelle auch MP4-Symlink für Kompatibilität
    # (damit alte Links noch funktionieren)
    Copy-Item -LiteralPath $playlistPath -Destination $OutputPath -Force
    
    return $playlistPath
  } else {
    throw "HLS-Conversion fehlgeschlagen: Playlist nicht erstellt"
  }
}
function Test-NeedsConversion {
  param([Parameter(Mandatory)][string]$VideoPath)
  $metadata = Get-VideoMetadata -VideoPath $VideoPath
  $needsConversion = @(
    "divx", "dx50", "xvid", "div3", "mp4v",
    "msmpeg4", "msmpeg4v2", "msmpeg4v3",
    "flv1", "vp6", "vp6f",
    "rv10", "rv20", "rv30", "rv40",
    "wmv1", "wmv2", "wmv3", "vc1"
  )
  $codec = ($metadata.VideoCodec -replace '[^a-z0-9]', '').ToLower()
  Write-Verbose "Video-Codec: '$($metadata.VideoCodec)' | Normalisiert: '$codec' | Needs Conversion: $($needsConversion -contains $codec)"
  return $needsConversion -contains $codec
}