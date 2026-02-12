#Requires -Version 5.1

<#
.SYNOPSIS
    Video-Thumbnail-Generierung und Metadaten-Analyse mit FFmpeg

.DESCRIPTION
    Stellt Funktionen bereit für:
    - Video-Thumbnail-Generierung (JPEG)
    - Video-Metadaten-Auslesen (Codec, Format, Auflösung, Dauer)
    - Browser-Kompatibilitätsprüfung
    - H.264/HLS-Conversion für inkompatible Codecs
    - FFmpeg-Pfad-Erkennung

.EXAMPLE
    $thumb = New-VideoThumbnail -VideoPath "C:\Videos\test.mp4"
    
    Erstellt Thumbnail in .thumbs Unterordner

.EXAMPLE
    $meta = Get-VideoMetadata -VideoPath "C:\Videos\test.mp4"
    
    Liest Codec, Format, Auflösung, Dauer aus

.NOTES
    Autor: Herbert Schrotter
    Version: 1.0.1
    Erfordert: FFmpeg (ffmpeg.exe und ffprobe.exe)
    
.LINK
    https://github.com/herbertschrotter-blip/01_Scripte_Sammlung
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# ============================================================================
# FFMPEG PFAD-ERKENNUNG
# ============================================================================

function Find-FFmpegPath {
    <#
    .SYNOPSIS
        Findet FFmpeg Installation
    
    .DESCRIPTION
        Sucht nach ffmpeg.exe in:
        - Aktuelles Verzeichnis
        - PATH Umgebungsvariable
        - Standard-Installationspfade
    
    .EXAMPLE
        $ffmpeg = Find-FFmpegPath
    
    .OUTPUTS
        System.String
        
        Pfad zu ffmpeg.exe oder $null wenn nicht gefunden
    
    .NOTES
        Cached das Ergebnis für Performance
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    # Cache-Variable (einmal suchen pro Session)
    if ($script:FFmpegPath) {
        return $script:FFmpegPath
    }
    
    # 1) Aktuelles Verzeichnis
    $localFFmpeg = Join-Path $PSScriptRoot "ffmpeg.exe"
    if (Test-Path -LiteralPath $localFFmpeg) {
        $script:FFmpegPath = $localFFmpeg
        return $script:FFmpegPath
    }
    
    # 2) PATH Umgebungsvariable
    $ffmpegInPath = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($ffmpegInPath) {
        $script:FFmpegPath = $ffmpegInPath.Source
        return $script:FFmpegPath
    }
    
    # 3) Standard-Pfade
    $commonPaths = @(
        "C:\ffmpeg\bin\ffmpeg.exe",
        "C:\Program Files\ffmpeg\bin\ffmpeg.exe",
        "$env:ProgramFiles\ffmpeg\bin\ffmpeg.exe",
        "$env:LOCALAPPDATA\ffmpeg\bin\ffmpeg.exe"
    )
    
    foreach ($path in $commonPaths) {
        if (Test-Path -LiteralPath $path) {
            $script:FFmpegPath = $path
            return $script:FFmpegPath
        }
    }
    
    Write-Warning "FFmpeg nicht gefunden. Bitte installieren: https://ffmpeg.org/download.html"
    return $null
}

function Find-FFprobePath {
    <#
    .SYNOPSIS
        Findet FFprobe Installation
    
    .DESCRIPTION
        Sucht nach ffprobe.exe (meist im gleichen Verzeichnis wie FFmpeg)
    
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    if ($script:FFprobePath) {
        return $script:FFprobePath
    }
    
    $ffmpeg = Find-FFmpegPath
    if (-not $ffmpeg) {
        return $null
    }
    
    $ffprobeDir = Split-Path -Parent $ffmpeg
    $ffprobe = Join-Path $ffprobeDir "ffprobe.exe"
    
    if (Test-Path -LiteralPath $ffprobe) {
        $script:FFprobePath = $ffprobe
        return $script:FFprobePath
    }
    
    # Fallback: PATH durchsuchen
    $ffprobeInPath = Get-Command ffprobe -ErrorAction SilentlyContinue
    if ($ffprobeInPath) {
        $script:FFprobePath = $ffprobeInPath.Source
        return $script:FFprobePath
    }
    
    return $null
}

# ============================================================================
# VIDEO-METADATEN
# ============================================================================

function Get-VideoMetadata {
    <#
    .SYNOPSIS
        Liest Video-Metadaten mit FFprobe aus
    
    .DESCRIPTION
        Extrahiert:
        - Video-Codec (h264, mpeg4, etc.)
        - Container-Format (mp4, avi, mkv, etc.)
        - Auflösung (1920x1080)
        - Dauer (formatiert)
        - Dateigröße
        - Bitrate
        - Browser-Kompatibilität
    
    .PARAMETER VideoPath
        Pfad zur Videodatei
    
    .EXAMPLE
        $meta = Get-VideoMetadata -VideoPath "C:\Videos\test.mp4"
        Write-Host "Codec: $($meta.VideoCodec)"
    
    .OUTPUTS
        PSCustomObject
        
        Objekt mit allen Metadaten
    
    .NOTES
        Benötigt ffprobe.exe
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_ -PathType Leaf})]
        [string]$VideoPath
    )
    
    $ffprobe = Find-FFprobePath
    if (-not $ffprobe) {
        throw "FFprobe nicht gefunden"
    }
    
    try {
        # FFprobe JSON-Output
        $args = @(
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            $VideoPath
        )
        
        $output = & $ffprobe @args 2>&1 | Out-String
        $data = $output | ConvertFrom-Json
        
        # Video-Stream finden
        $videoStream = $data.streams | Where-Object { $_.codec_type -eq "video" } | Select-Object -First 1
        
        if (-not $videoStream) {
            throw "Kein Video-Stream gefunden"
        }
        
        # Metadaten extrahieren
        $codec = $videoStream.codec_name
        $format = $data.format.format_name -split ',' | Select-Object -First 1
        $width = $videoStream.width
        $height = $videoStream.height
        $duration = [math]::Round([double]$data.format.duration, 1)
        $bitrate = [math]::Round([double]$data.format.bit_rate / 1000, 0)  # kbps
        
        # Dateigröße
        $fileInfo = Get-Item -LiteralPath $VideoPath
        $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
        
        # Dauer formatieren (MM:SS)
        $durationMin = [math]::Floor($duration / 60)
        $durationSec = $duration % 60
        $durationFormatted = "{0:D2}:{1:D2}" -f $durationMin, $durationSec
        
        # Browser-Kompatibilität prüfen
        $compat = Get-BrowserCompatibility -Codec $codec -Format $format
        
        return [PSCustomObject]@{
            VideoCodec           = $codec
            Format               = $format
            Resolution           = "${width}x${height}"
            Width                = $width
            Height               = $height
            Duration             = $duration
            DurationFormatted    = $durationFormatted
            Bitrate              = $bitrate
            BitrateFormatted     = "${bitrate} kbps"
            FileSize             = $fileInfo.Length
            FileSizeFormatted    = "${fileSizeMB} MB"
            FileName             = $fileInfo.Name
            BrowserCompatibility = $compat.Status
            CompatibilityIcon    = $compat.Icon
            CompatibilityText    = $compat.Text
        }
    }
    catch {
        Write-Error "Fehler beim Auslesen der Video-Metadaten: $_"
        throw
    }
}

function Get-BrowserCompatibility {
    <#
    .SYNOPSIS
        Prüft Browser-Kompatibilität
    
    .PARAMETER Codec
        Video-Codec
    
    .PARAMETER Format
        Container-Format
    
    .OUTPUTS
        PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Codec,
        
        [Parameter(Mandatory)]
        [string]$Format
    )
    
    # Browser-kompatible Codecs
    $compatibleCodecs = @('h264', 'vp8', 'vp9', 'av1')
    $compatibleFormats = @('mp4', 'webm')
    
    $isCompatCodec = $Codec -in $compatibleCodecs
    $isCompatFormat = $Format -in $compatibleFormats
    
    if ($isCompatCodec -and $isCompatFormat) {
        return [PSCustomObject]@{
            Status = 'compatible'
            Icon   = '✓'
            Text   = 'Browser-kompatibel'
        }
    }
    else {
        return [PSCustomObject]@{
            Status = 'needs_conversion'
            Icon   = '⚠'
            Text   = 'Conversion nötig'
        }
    }
}

# ============================================================================
# VIDEO-THUMBNAILS
# ============================================================================

function Get-VideoThumbnailPath {
    <#
    .SYNOPSIS
        Berechnet Thumbnail-Pfad für Video
    
    .PARAMETER VideoPath
        Pfad zur Videodatei
    
    .OUTPUTS
        System.String
        
        Pfad zum Thumbnail (.thumbs Unterordner)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$VideoPath
    )
    
    $dir = Split-Path -Parent $VideoPath
    $filename = Split-Path -Leaf $VideoPath
    $thumbsDir = Join-Path $dir ".thumbs"
    
    return Join-Path $thumbsDir "$filename.jpg"
}

function New-VideoThumbnail {
    <#
    .SYNOPSIS
        Erstellt Video-Thumbnail mit FFmpeg
    
    .DESCRIPTION
        Extrahiert Frame bei 10% der Video-Dauer als JPEG.
        Speichert in .thumbs Unterordner.
    
    .PARAMETER VideoPath
        Pfad zur Videodatei
    
    .PARAMETER Force
        Überschreibt existierendes Thumbnail
    
    .EXAMPLE
        $thumb = New-VideoThumbnail -VideoPath "C:\Videos\test.mp4"
    
    .OUTPUTS
        System.String
        
        Pfad zum erstellten Thumbnail
    
    .NOTES
        Benötigt ffmpeg.exe
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_ -PathType Leaf})]
        [string]$VideoPath,
        
        [Parameter()]
        [switch]$Force
    )
    
    $ffmpeg = Find-FFmpegPath
    if (-not $ffmpeg) {
        throw "FFmpeg nicht gefunden"
    }
    
    $thumbPath = Get-VideoThumbnailPath -VideoPath $VideoPath
    
    # Skip wenn bereits vorhanden
    if ((Test-Path -LiteralPath $thumbPath) -and -not $Force) {
        Write-Verbose "Thumbnail existiert bereits: $thumbPath"
        return $thumbPath
    }
    
    # .thumbs Ordner erstellen
    $thumbsDir = Split-Path -Parent $thumbPath
    if (-not (Test-Path -LiteralPath $thumbsDir)) {
        New-Item -Path $thumbsDir -ItemType Directory -Force | Out-Null
    }
    
    try {
        # Frame bei 10% extrahieren
        $args = @(
            "-ss", "00:00:01",           # 1 Sekunde nach Start
            "-i", $VideoPath,
            "-vframes", "1",             # Nur 1 Frame
            "-q:v", "2",                 # Hohe Qualität
            "-y",                        # Überschreiben
            $thumbPath
        )
        
        $output = & $ffmpeg @args 2>&1
        
        if (-not (Test-Path -LiteralPath $thumbPath)) {
            throw "Thumbnail wurde nicht erstellt"
        }
        
        Write-Verbose "Thumbnail erstellt: $thumbPath"
        return $thumbPath
    }
    catch {
        Write-Error "Fehler beim Erstellen des Thumbnails: $_"
        throw
    }
}

# ============================================================================
# VIDEO-CONVERSION
# ============================================================================

function Test-NeedsConversion {
    <#
    .SYNOPSIS
        Prüft ob Video Conversion benötigt
    
    .PARAMETER VideoPath
        Pfad zur Videodatei
    
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$VideoPath
    )
    
    try {
        $meta = Get-VideoMetadata -VideoPath $VideoPath
        return $meta.BrowserCompatibility -eq 'needs_conversion'
    }
    catch {
        return $false
    }
}

function Get-ConvertedHLSPath {
    <#
    .SYNOPSIS
        Berechnet Pfad für konvertierte HLS-Playlist
    
    .PARAMETER VideoPath
        Pfad zur Videodatei
    
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$VideoPath
    )
    
    $dir = Split-Path -Parent $VideoPath
    $baseNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($VideoPath)
    $thumbsDir = Join-Path $dir ".thumbs"
    
    return Join-Path $thumbsDir "${baseNameWithoutExt}_hls.m3u8"
}

function Convert-VideoToH264 {
    <#
    .SYNOPSIS
        Konvertiert Video zu H.264/HLS
    
    .DESCRIPTION
        Erstellt HLS-Playlist mit H.264-Codec für Browser-Kompatibilität.
    
    .PARAMETER VideoPath
        Pfad zur Videodatei
    
    .PARAMETER OutputPath
        Pfad zur HLS-Playlist (.m3u8)
    
    .EXAMPLE
        Convert-VideoToH264 -VideoPath "C:\Videos\old.avi" -OutputPath "C:\Videos\.thumbs\old_hls.m3u8"
    
    .OUTPUTS
        System.String
        
        Pfad zur erstellten Playlist
    
    .NOTES
        Benötigt ffmpeg.exe
        Erstellt .m3u8 Playlist + .ts Chunks
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_ -PathType Leaf})]
        [string]$VideoPath,
        
        [Parameter(Mandatory)]
        [string]$OutputPath
    )
    
    $ffmpeg = Find-FFmpegPath
    if (-not $ffmpeg) {
        throw "FFmpeg nicht gefunden"
    }
    
    # Output-Verzeichnis erstellen
    $outputDir = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }
    
    try {
        Write-Verbose "Konvertiere zu H.264/HLS: $VideoPath"
        
        $args = @(
            "-i", $VideoPath,
            "-c:v", "libx264",           # H.264 Codec
            "-c:a", "aac",                # AAC Audio
            "-b:v", "2M",                 # 2 Mbps Video-Bitrate
            "-b:a", "128k",               # 128 kbps Audio-Bitrate
            "-f", "hls",                  # HLS Format
            "-hls_time", "10",            # 10 Sekunden pro Chunk
            "-hls_list_size", "0",        # Alle Chunks in Playlist
            "-hls_segment_filename", (Join-Path $outputDir "chunk_%03d.ts"),
            "-y",                         # Überschreiben
            $OutputPath
        )
        
        $output = & $ffmpeg @args 2>&1
        
        if (-not (Test-Path -LiteralPath $OutputPath)) {
            throw "HLS-Playlist wurde nicht erstellt"
        }
        
        Write-Verbose "Conversion abgeschlossen: $OutputPath"
        return $OutputPath
    }
    catch {
        Write-Error "Fehler bei Video-Conversion: $_"
        throw
    }
}

# ============================================================================
# HELPER-FUNKTIONEN
# ============================================================================

function Test-IsVideoFile {
    <#
    .SYNOPSIS
        Prüft ob Datei ein Video ist
    
    .PARAMETER Path
        Dateipfad
    
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    $videoExtensions = @('.mp4', '.avi', '.mov', '.wmv', '.mkv', '.webm', '.m4v', '.mpg', '.mpeg', '.flv', '.3gp')
    $ext = [System.IO.Path]::GetExtension($Path).ToLower()
    
    return $ext -in $videoExtensions
}