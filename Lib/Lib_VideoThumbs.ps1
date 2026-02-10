<#
ManifestHint:
  ExportFunctions = @("Get-VideoThumbnailPath","New-VideoThumbnail","Test-IsVideoFile")
  Description     = "Video Thumbnail Generator mit FFmpeg - Thumbnails in verstecktem .thumbs Ordner"
  Category        = "Media"
  Tags            = @("Video","Thumbnail","FFmpeg","Cache")
  Dependencies    = @()

Zweck:
  - Video-Thumbnails mit FFmpeg generieren
  - Thumbnails in verstecktem .thumbs Ordner pro Video-Ordner
  - On-Demand Generation (nur beim ersten Zugriff)
  - Frame-Extraktion bei 40-70% der Videolänge
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Video-Extensions
$script:VideoExtensions = @(".mp4",".mov",".avi",".mkv",".webm",".m4v",".wmv",".flv",".mpg",".mpeg",".3gp")

# ------------------------------------------------------------
# Prüfen ob Datei ein Video ist
# ------------------------------------------------------------
function Test-IsVideoFile {
  <#
  .SYNOPSIS
  Prüft ob eine Datei ein Video ist
  
  .PARAMETER Path
  Dateipfad
  
  .EXAMPLE
  Test-IsVideoFile "video.mp4"  # Returns: $true
  Test-IsVideoFile "photo.jpg"  # Returns: $false
  #>
  
  param([string]$Path)
  
  $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
  return ($script:VideoExtensions -contains $ext)
}

# ------------------------------------------------------------
# Thumbnail-Pfad ermitteln
# ------------------------------------------------------------
function Get-VideoThumbnailPath {
  <#
  .SYNOPSIS
  Gibt Pfad zum Thumbnail zurück
  
  .PARAMETER VideoPath
  Pfad zur Video-Datei
  
  .EXAMPLE
  Get-VideoThumbnailPath "D:\Videos\video.mp4"
  # Returns: "D:\Videos\.thumbs\video.mp4.jpg"
  #>
  
  param([Parameter(Mandatory)]
        [string]$VideoPath)
  
  $videoDir = Split-Path -Parent $VideoPath
  $videoName = Split-Path -Leaf $VideoPath
  
  $thumbsDir = Join-Path $videoDir ".thumbs"
  $thumbName = "$videoName.jpg"
  
  return Join-Path $thumbsDir $thumbName
}

# ------------------------------------------------------------
# .thumbs Ordner erstellen (mit Hidden Attribute)
# ------------------------------------------------------------
function Ensure-ThumbsDirectory {
  param([string]$VideoDir)
  
  $thumbsDir = Join-Path $VideoDir ".thumbs"
  
  if (-not (Test-Path -LiteralPath $thumbsDir)) {
    $dir = New-Item -Path $thumbsDir -ItemType Directory -Force
    # Hidden Attribute setzen
    $dir.Attributes = $dir.Attributes -bor [System.IO.FileAttributes]::Hidden
  }
  
  return $thumbsDir
}

# ------------------------------------------------------------
# FFmpeg-Pfad finden
# ------------------------------------------------------------
function Find-FFmpegPath {
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
# Video-Dauer ermitteln (in Sekunden)
# ------------------------------------------------------------
function Get-VideoDuration {
  param(
    [string]$VideoPath,
    [string]$FFmpegPath
  )
  
  try {
    # FFprobe nutzen (besser als FFmpeg für Metadaten)
    $ffprobePath = $FFmpegPath -replace "ffmpeg\.exe$", "ffprobe.exe"
    
    if (Test-Path $ffprobePath) {
      $output = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $VideoPath 2>&1
      $duration = [double]$output
      return $duration
    }
    
    # Fallback: FFmpeg output parsen
    $output = & $FFmpegPath -i $VideoPath 2>&1 | Out-String
    if ($output -match "Duration: (\d{2}):(\d{2}):(\d{2})\.(\d{2})") {
      $hours = [int]$matches[1]
      $mins = [int]$matches[2]
      $secs = [int]$matches[3]
      return ($hours * 3600) + ($mins * 60) + $secs
    }
    
    # Default: 60 Sekunden annehmen
    return 60
  } catch {
    Write-Warning "Fehler beim Ermitteln der Video-Dauer: $($_.Exception.Message)"
    return 60
  }
}

# ------------------------------------------------------------
# Video-Thumbnail generieren
# ------------------------------------------------------------
function New-VideoThumbnail {
  <#
  .SYNOPSIS
  Generiert Thumbnail für Video mit FFmpeg
  
  .PARAMETER VideoPath
  Pfad zur Video-Datei
  
  .PARAMETER FFmpegPath
  Pfad zu ffmpeg.exe (optional, wird automatisch gesucht)
  
  .PARAMETER PercentMin
  Minimale Position in % (Default: 40)
  
  .PARAMETER PercentMax
  Maximale Position in % (Default: 70)
  
  .PARAMETER Size
  Thumbnail-Größe (Default: 140)
  
  .EXAMPLE
  New-VideoThumbnail -VideoPath "D:\Videos\video.mp4"
  
  .OUTPUTS
  String - Pfad zum generierten Thumbnail
  #>
  
  param(
    [Parameter(Mandatory)]
    [string]$VideoPath,
    
    [string]$FFmpegPath,
    
    [int]$PercentMin = 40,
    [int]$PercentMax = 70,
    
    [int]$Size = 140
  )
  
  if (-not (Test-Path -LiteralPath $VideoPath)) {
    throw "Video nicht gefunden: $VideoPath"
  }
  
  # Thumbnail-Pfad
  $thumbPath = Get-VideoThumbnailPath -VideoPath $VideoPath
  
  # Existiert schon?
  if (Test-Path -LiteralPath $thumbPath) {
    return $thumbPath
  }
  
# FFmpeg finden
  if ([string]::IsNullOrWhiteSpace($FFmpegPath)) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $FFmpegPath = Find-FFmpegPath -ProjectRoot $projectRoot
  }

  # .thumbs Ordner erstellen
  $videoDir = Split-Path -Parent $VideoPath
  $thumbsDir = Ensure-ThumbsDirectory -VideoDir $videoDir
  
  # Video-Dauer ermitteln
  $duration = Get-VideoDuration -VideoPath $VideoPath -FFmpegPath $FFmpegPath
  
  # Random Position zwischen Min-Max%
  $percent = Get-Random -Minimum $PercentMin -Maximum $PercentMax
  $seekSeconds = [Math]::Floor($duration * $percent / 100)
  
  Write-Verbose "Video: $VideoPath"
  Write-Verbose "Dauer: $duration Sekunden"
  Write-Verbose "Position: $percent% = $seekSeconds Sekunden"
  Write-Verbose "Thumbnail: $thumbPath"
  
  try {
    # FFmpeg Command:
    # -ss: Seek to position
    # -i: Input file
    # -vframes 1: Extract 1 frame
    # -vf scale: Scale to SIZExSIZE
    # -q:v 2: Quality (2 = high quality)
    
    $arguments = @(
      "-ss", $seekSeconds,
      "-i", "`"$VideoPath`"",
      "-vframes", "1",
      "-vf", "scale=${Size}:${Size}:force_original_aspect_ratio=increase,crop=${Size}:${Size}",
      "-q:v", "2",
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
# Alle Thumbnails für Ordner generieren (Bulk)
# ------------------------------------------------------------
function New-VideoThumbnailsBulk {
  <#
  .SYNOPSIS
  Generiert Thumbnails für alle Videos in einem Ordner
  
  .PARAMETER FolderPath
  Pfad zum Ordner
  
  .PARAMETER Recursive
  Rekursiv in Unterordner
  
  .EXAMPLE
  New-VideoThumbnailsBulk -FolderPath "D:\Videos" -Recursive
  #>
  
  param(
    [Parameter(Mandatory)]
    [string]$FolderPath,
    
    [switch]$Recursive
  )
  
  $videos = Get-ChildItem -LiteralPath $FolderPath -File -Recurse:$Recursive | 
            Where-Object { Test-IsVideoFile -Path $_.FullName }
  
  Write-Host "Gefunden: $($videos.Count) Videos"
  
  $generated = 0
  $existing = 0
  
  foreach ($video in $videos) {
    $thumbPath = Get-VideoThumbnailPath -VideoPath $video.FullName
    
    if (Test-Path -LiteralPath $thumbPath) {
      $existing++
      Write-Verbose "Thumbnail existiert: $($video.Name)"
    } else {
      Write-Host "Generiere Thumbnail: $($video.Name)"
      $result = New-VideoThumbnail -VideoPath $video.FullName
      if ($result) {
        $generated++
      }
    }
  }
  
  Write-Host "Fertig: $generated neu generiert, $existing bereits vorhanden"
}