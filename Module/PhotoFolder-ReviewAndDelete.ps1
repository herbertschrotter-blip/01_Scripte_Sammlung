<#
ManifestHint:
  ExportFunctions = @()
  Description     = "Lokale HTML-Übersicht für Bild- und Video-Ordner (rekursiv), Ordner auswählen + löschen (Papierkorb), Video-Thumbnails mit FFmpeg, Ordner zuklappbar (ganze Zeile klickbar), im zugeklappten Zustand 10 zufällige Preview-Thumbs pro Ordner, beim Aufklappen werden alle Medien geladen. Viewer mit Navigation (Pfeiltasten + Klick links/rechts) für Bilder und Videos. Beenden per X. /img und /videothumb liefern per Streaming."
  Category        = "Media"
  Tags            = @("Photos","Videos","HTML","Gallery","Recursive","DeleteFolders","RecycleBin","HttpListener","Lightbox","Collapse","Shutdown","OnDemand","Preview10Random","ArrowKeys","NextPrev","Streaming","FFmpeg","VideoThumbnails")
  Dependencies    = @("System.Net.HttpListener","System.Windows.Forms","Microsoft.VisualBasic","FFmpeg")

Zweck:
  - Root wählen (Dialog, wenn -RootPath nicht gesetzt).
  - Alle Unterordner scannen und Ordner listen, die Bild- oder Videodateien enthalten.
  - Video-Thumbnails automatisch mit FFmpeg generieren (in .thumbs Ordner) BEIM START.
  - Zugeklappt: pro Ordner 10 zufällige Preview-Thumbs immer sichtbar.
  - Aufklappen: Preview ausblenden, alle Medien on-demand laden.
  - Thumbnail klick -> großer Viewer im Browser (Overlay/Lightbox) + Navigation:
      -> Pfeiltasten Links/Rechts
      -> Klick linke Bildhälfte = zurück, rechte Bildhälfte = vorwärts
      -> Videos abspielen mit HTML5 Video-Player
  - Ausgewählte Ordner löschen (Papierkorb oder HardDelete).
  - Tool per X in der HTML beenden (kein Strg+C).
  - /img: Streaming für Bilder und Videos (RAM-schonend).
  - /videothumb: On-Demand Video-Thumbnail-Generierung mit FFmpeg.

Parameter:
  -RootPath   : Root-Ordner (optional; sonst Dialog)
  -Port       : Port für lokalen Server (Default 8787)
  -HardDelete : Endgültig löschen (ohne Papierkorb) (vorsichtig)

Fehlercodes:
  E010 RootPath fehlt oder existiert nicht
  E020 HttpListener konnte nicht gestartet werden (Port belegt / Rechte)
  E030 Scan fehlgeschlagen
  E040 Löschen fehlgeschlagen
  E050 Verschieben fehlgeschlagen
#>

param(
  [string]$RootPath,
  [int]$Port = 8787,
  [switch]$HardDelete
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Libs laden (aus ..\Lib) – Script liegt in \Module\
# ------------------------------------------------------------
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

. (Join-Path $ProjectRoot "Lib\Lib_Http.ps1")
. (Join-Path $ProjectRoot "Lib\Lib_FileSystem.ps1")
. (Join-Path $ProjectRoot "Lib\Lib_FastScan.ps1")
. (Join-Path $ProjectRoot "Lib\Lib_VideoThumbs.ps1")
. (Join-Path $ProjectRoot "Lib\Lib_PhotoGallery_UI.ps1")
. (Join-Path $ProjectRoot "Lib\Lib_Dialogs.ps1")

# -----------------------------
# Einstellungen
# -----------------------------
$MediaExt = @(
  # Bilder
  ".jpg",".jpeg",".png",".webp",".gif",".bmp",".tif",".tiff",
  # Videos
  ".mp4",".mov",".avi",".mkv",".webm",".m4v",".wmv",".flv",".mpg",".mpeg",".3gp"
)

# Assembly einmal vorladen (nicht bei jedem Delete-Request)
Add-Type -AssemblyName Microsoft.VisualBasic | Out-Null

function Write-Err {
  param([string]$Code, [string]$Msg)
  Write-Host "$Code $Msg" -ForegroundColor Red
}

# -----------------------------
# Root per Dialog (wenn nicht übergeben)
# -----------------------------
if ([string]::IsNullOrWhiteSpace($RootPath)) {
  $RootPath = Show-FolderDialog -Description "Root-Ordner auswählen" -ShowNewFolderButton $false -TopMost $true
  
  if (-not $RootPath) {
    Write-Err "E010" "Kein Root-Ordner ausgewählt"
    return
  }
}

if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
  Write-Err "E010" "RootPath existiert nicht: $RootPath"
  return
}

$RootFull = [System.IO.Path]::GetFullPath($RootPath)

try {
  Write-Host "Scanne Bild- und Video-Ordner..."
  $Folders = Scan-ImageFolders -Root $RootFull -ImageExt $MediaExt -UseCache
  Write-Host "Fertig: $($Folders.Count) Ordner mit Medien gefunden"
  
# NEU: Video-Thumbnails pre-generieren
Write-Host "Generiere Video-Thumbnails (falls noch nicht vorhanden)..."

# Alle Videos sammeln
$allVideos = @()
foreach ($folder in $Folders) {
  foreach ($mediaRel in $folder.ImagesRel) {
    if (Test-IsVideoFile -Path $mediaRel) {
      try {
        $videoFull = Resolve-FullPathSafe -RootFull $RootFull -RelPath $mediaRel
        $allVideos += [PSCustomObject]@{
          RelPath = $mediaRel
          FullPath = $videoFull
        }
      } catch {
        Write-Warning "Fehler beim Auflösen von $mediaRel : $($_.Exception.Message)"
      }
    }
  }
}

$videoTotal = $allVideos.Count

if ($videoTotal -gt 0) {
  Write-Host "Gefunden: $videoTotal Videos"
  
  # PowerShell 7+ mit Parallel-Verarbeitung
  if ($PSVersionTable.PSVersion.Major -ge 7) {
    Write-Host "Verwende parallele Verarbeitung (bis zu 8 Videos gleichzeitig)..." -ForegroundColor Cyan
    
    $results = $allVideos | ForEach-Object -ThrottleLimit 8 -Parallel {
      $video = $_
      $ProjectRoot = $using:ProjectRoot
      
      # Libs in Parallel-Context laden
      . (Join-Path $ProjectRoot "Lib\Lib_FileSystem.ps1")
      . (Join-Path $ProjectRoot "Lib\Lib_VideoThumbs.ps1")
      
      $thumbPath = Get-VideoThumbnailPath -VideoPath $video.FullPath
      
      if (Test-Path -LiteralPath $thumbPath) {
        return [PSCustomObject]@{ Status = "Skipped"; Path = $video.RelPath }
      } else {
        try {
          $thumb = New-VideoThumbnail -VideoPath $video.FullPath -Verbose:$false
          if ($thumb) {
            return [PSCustomObject]@{ Status = "Created"; Path = $video.RelPath }
          } else {
            return [PSCustomObject]@{ Status = "Failed"; Path = $video.RelPath }
          }
        } catch {
          return [PSCustomObject]@{ Status = "Error"; Path = $video.RelPath; Error = $_.Exception.Message }
        }
      }
    }
    
$videoCount = @($results | Where-Object { $_.Status -eq "Created" }).Count
$videoSkipped = @($results | Where-Object { $_.Status -eq "Skipped" }).Count
$videoFailed = @($results | Where-Object { $_.Status -in @("Failed","Error") }).Count
    
    if ($videoFailed -gt 0) {
      Write-Warning "$videoFailed Videos konnten nicht verarbeitet werden"
    }
    
  } else {
    # PowerShell 5.1 - Sequenziell (wie vorher)
    Write-Host "Verwende sequenzielle Verarbeitung (PowerShell 5.1)..." -ForegroundColor Yellow
    Write-Host "TIPP: Für 4-8x schnellere Verarbeitung PowerShell 7+ installieren!" -ForegroundColor Yellow
    Write-Host "      Download: https://aka.ms/powershell" -ForegroundColor Yellow
    
    $videoCount = 0
    $videoSkipped = 0
    
    $progressCount = 0
    foreach ($video in $allVideos) {
      $progressCount++
      
      $thumbPath = Get-VideoThumbnailPath -VideoPath $video.FullPath
      if (Test-Path -LiteralPath $thumbPath) {
        $videoSkipped++
      } else {
        Write-Host "  [$progressCount/$videoTotal] Erstelle: $($video.RelPath)" -ForegroundColor Cyan
        try {
          $thumb = New-VideoThumbnail -VideoPath $video.FullPath -Verbose:$false
          if ($thumb) { $videoCount++ }
        } catch {
          Write-Warning "Fehler bei $($video.RelPath): $($_.Exception.Message)"
        }
      }
    }
  }
  
  Write-Host "Video-Thumbnails: $videoCount neu erstellt, $videoSkipped bereits vorhanden (von $videoTotal Videos gesamt)" -ForegroundColor Green
}

} catch {
  Write-Err "E030" "Scan fehlgeschlagen: $($_.Exception.Message)"
  return
}

# -----------------------------
# HTML Card Rows generieren
# -----------------------------
function Build-CardRows {
  param([object[]]$Folders)

  $rows = New-Object System.Text.StringBuilder

  foreach ($f in $Folders) {
    $rel = $f.RelPath
    $cnt = $f.ImgCount

    # Bilder + Videos als URLs generieren
    $imgList = @()
    $imgRelList = @()
    $mediaTypes = @()
    
    foreach ($mediaRel in $f.ImagesRel) {
      $imgRelList += $mediaRel
      
      # Prüfen ob Video
      $isVideo = Test-IsVideoFile -Path $mediaRel
      
      if ($isVideo) {
        # Video-Thumbnail URL
        $imgList += "/videothumb?path=$(UrlEncode($mediaRel))"
        $mediaTypes += "video"
      } else {
        # Normales Bild URL
        $imgList += "/img?path=$(UrlEncode($mediaRel))"
        $mediaTypes += "image"
      }
    }
    
    $imgListStr = ($imgList) -join "|"
    $imgRelListStr = ($imgRelList) -join "|"
    $mediaTypesStr = ($mediaTypes) -join "|"

    [void]$rows.AppendLine(@"
<div class="card" data-path="$(HtmlEncode($rel))">
  <div class="hdr" onclick="toggleFolderRow(event, this)">
    <input type="checkbox" name="folder" value="$(HtmlEncode($rel))" />
    <span class="path">$(HtmlEncode($rel))</span>
    <span class="meta">($cnt)</span>
    <button class="toggleBtn" type="button" onclick="toggleFolder(this)">▸</button>
  </div>

  <!-- Zugeklappt: 10 zufällige Preview-Thumbs -->
  <div class="previewRow" data-preview-loaded="0" data-images="$(HtmlEncode($imgListStr))" data-images-rel="$(HtmlEncode($imgRelListStr))" data-media-types="$(HtmlEncode($mediaTypesStr))"></div>

  <!-- Aufgeklappt: alle Medien (on-demand) -->
  <div class="thumbs isCollapsed" data-loaded="0" data-images="$(HtmlEncode($imgListStr))" data-images-rel="$(HtmlEncode($imgRelListStr))" data-media-types="$(HtmlEncode($mediaTypesStr))"></div>
</div>
"@)
  }

  return $rows.ToString()
}

# -----------------------------
# HttpListener Start
# -----------------------------
$prefix = "http://localhost:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
  $listener.Start()
} catch {
  Write-Err "E020" "HttpListener Start fehlgeschlagen (Port belegt / Rechte): $($_.Exception.Message)"
  return
}

Write-Host "Server läuft: $prefix"

try {
  Start-Process $prefix | Out-Null
} catch {
  try {
    & cmd.exe /c "start" "" $prefix | Out-Null
  } catch {
    Write-Host "Hinweis: Browser konnte nicht automatisch geöffnet werden. Bitte manuell öffnen: $prefix"
  }
}

$ServerRunning = $true

try {
  while ($listener.IsListening -and $ServerRunning) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response
    $path = $req.Url.AbsolutePath.ToLowerInvariant()

    try {
      if ($path -eq "/" -and $req.HttpMethod -eq "GET") {
        $cardRows = Build-CardRows -Folders $Folders
        $html = Get-PhotoGalleryHTML -RootPath (HtmlEncode($RootFull)) -CardRowsHTML $cardRows -HardDelete $HardDelete
        Send-ResponseHtml -Response $res -Html $html
        continue
      }

      if ($path -eq "/shutdown" -and $req.HttpMethod -eq "POST") {
        $ServerRunning = $false
        Send-ResponseHtml -Response $res -Html "<html><body>Server beendet</body></html>"
        break
      }

      if ($path -eq "/openrecyclebin" -and $req.HttpMethod -eq "POST") {
        Start-Process "explorer.exe" -ArgumentList "shell:RecycleBinFolder"
        Send-ResponseText -Response $res -Text "OK" -StatusCode 200
        continue
      }

if ($path -eq "/changeroot" -and $req.HttpMethod -eq "POST") {
  $newRoot = Show-FolderDialog -Description "Neuen Root-Ordner auswählen" -ShowNewFolderButton $false -TopMost $true
  
  if ($newRoot -and (Test-Path -LiteralPath $newRoot -PathType Container)) {
    $RootFull = [System.IO.Path]::GetFullPath($newRoot)
    
    # Scan
    Write-Host ("[INFO] Root gewechselt: {0}" -f $RootFull)
    $Folders = Scan-ImageFolders -Root $RootFull -ImageExt $MediaExt -UseCache
    
    # Video-Thumbnails pre-generieren (parallel wie beim Start)
    Write-Host "Generiere Video-Thumbnails..."
    
    # Alle Videos sammeln
    $allVideos = @()
    foreach ($folder in $Folders) {
      foreach ($mediaRel in $folder.ImagesRel) {
        if (Test-IsVideoFile -Path $mediaRel) {
          try {
            $videoFull = Resolve-FullPathSafe -RootFull $RootFull -RelPath $mediaRel
            $allVideos += [PSCustomObject]@{ RelPath = $mediaRel; FullPath = $videoFull }
          } catch { }
        }
      }
    }
    
    $videoTotal = $allVideos.Count
    
    if ($videoTotal -gt 0) {
      if ($PSVersionTable.PSVersion.Major -ge 7) {
        # PowerShell 7: Parallel
        $results = $allVideos | ForEach-Object -ThrottleLimit 8 -Parallel {
          $video = $_
          $ProjectRoot = $using:ProjectRoot
          
          . (Join-Path $ProjectRoot "Lib\Lib_FileSystem.ps1")
          . (Join-Path $ProjectRoot "Lib\Lib_VideoThumbs.ps1")
          
          $thumbPath = Get-VideoThumbnailPath -VideoPath $video.FullPath
          if (-not (Test-Path -LiteralPath $thumbPath)) {
            try {
              $thumb = New-VideoThumbnail -VideoPath $video.FullPath -Verbose:$false
              if ($thumb) { return "Created" } else { return "Failed" }
            } catch { return "Error" }
          } else { return "Skipped" }
        }
        
        $videoCount = ($results | Where-Object { $_ -eq "Created" }).Count
      } else {
        # PowerShell 5.1: Sequenziell
        $videoCount = 0
        foreach ($video in $allVideos) {
          $thumbPath = Get-VideoThumbnailPath -VideoPath $video.FullPath
          if (-not (Test-Path -LiteralPath $thumbPath)) {
            try {
              $thumb = New-VideoThumbnail -VideoPath $video.FullPath -Verbose:$false
              if ($thumb) { $videoCount++ }
            } catch { }
          }
        }
      }
      
      if ($videoCount -gt 0) {
        Write-Host "Video-Thumbnails erstellt: $videoCount"
      }
    }
  }

  Send-ResponseText -Response $res -Text "OK" -StatusCode 200
  continue
}
      if ($path -eq "/img" -and $req.HttpMethod -eq "GET") {
        $q = $req.QueryString["path"]
        if ([string]::IsNullOrWhiteSpace($q)) {
          Send-ResponseText -Response $res -Text "Missing path" -StatusCode 400
          continue
        }

        $rel = UrlDecode($q)
        try {
          $full = Resolve-FullPathSafe -RootFull $RootFull -RelPath $rel
        } catch {
          Send-ResponseText -Response $res -Text "Forbidden" -StatusCode 403
          continue
        }

        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
          Send-ResponseText -Response $res -Text "Not found" -StatusCode 404
          continue
        }

        # Streaming (für Bilder UND Videos)
        $ct = Get-ContentTypeByExt -Path $full
        $res.StatusCode = 200
        $res.ContentType = $ct

        $fi = [System.IO.FileInfo]::new($full)
        $res.ContentLength64 = $fi.Length

        $fs = [System.IO.File]::Open($full, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
          $fs.CopyTo($res.OutputStream)
        }
        finally {
          $fs.Close()
          $res.OutputStream.Close()
        }
        continue
      }

      if ($path -eq "/videothumb" -and $req.HttpMethod -eq "GET") {
        $q = $req.QueryString["path"]
        if ([string]::IsNullOrWhiteSpace($q)) {
          Send-ResponseText -Response $res -Text "Missing path" -StatusCode 400
          continue
        }

        $rel = UrlDecode($q)
        try {
          $videoFull = Resolve-FullPathSafe -RootFull $RootFull -RelPath $rel
        } catch {
          Send-ResponseText -Response $res -Text "Forbidden" -StatusCode 403
          continue
        }

        if (-not (Test-Path -LiteralPath $videoFull -PathType Leaf)) {
          Send-ResponseText -Response $res -Text "Video not found" -StatusCode 404
          continue
        }

        # Video-Thumbnail holen (sollte schon existieren durch Pre-Generate)
        try {
          $thumbPath = Get-VideoThumbnailPath -VideoPath $videoFull
          
          # Falls doch nicht vorhanden, jetzt erstellen
          if (-not (Test-Path -LiteralPath $thumbPath)) {
            Write-Host "[INFO] Thumbnail on-demand erstellen: $rel" -ForegroundColor Yellow
            $thumbPath = New-VideoThumbnail -VideoPath $videoFull
          }
          
          if (-not $thumbPath -or -not (Test-Path -LiteralPath $thumbPath)) {
            Send-ResponseText -Response $res -Text "Thumbnail generation failed" -StatusCode 500
            continue
          }
          
          # Thumbnail als Bild ausliefern
          $ct = "image/jpeg"
          $res.StatusCode = 200
          $res.ContentType = $ct

          $fi = [System.IO.FileInfo]::new($thumbPath)
          $res.ContentLength64 = $fi.Length

          $fs = [System.IO.File]::Open($thumbPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
          try {
            $fs.CopyTo($res.OutputStream)
          }
          finally {
            $fs.Close()
            $res.OutputStream.Close()
          }
        } catch {
          Send-ResponseText -Response $res -Text "Thumbnail error: $($_.Exception.Message)" -StatusCode 500
        }
        continue
      }

      if ($path -eq "/move" -and $req.HttpMethod -eq "POST") {
        $body = Read-RequestBody -Request $req
        $form = Parse-FormUrlEncoded -Body $body

        # Ordner + Bilder sammeln
        $selectedFolders = @()
        if ($form.ContainsKey("folder")) {
          if ($form["folder"] -is [System.Collections.IList]) { $selectedFolders = @($form["folder"]) }
          else { $selectedFolders = @($form["folder"]) }
        }
        $selectedImgs = @()
        if ($form.ContainsKey("img")) {
          if ($form["img"] -is [System.Collections.IList]) { $selectedImgs = @($form["img"]) }
          else { $selectedImgs = @($form["img"]) }
        }

        if ($selectedFolders.Count -eq 0 -and $selectedImgs.Count -eq 0) {
          Send-ResponseText -Response $res -Text '{"error":"Nichts ausgewählt"}' -StatusCode 400 -ContentType "application/json; charset=utf-8"
          continue
        }

        # Zielordner per Dialog wählen
        $destDir = Show-FolderDialog -Description "Zielordner für Verschieben auswählen" -ShowNewFolderButton $true -TopMost $true

        if (-not $destDir) {
          $json = @{ cancelled = $true; msg = "Abgebrochen" } | ConvertTo-Json -Compress
          Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
          continue
        }

        if (-not (Test-Path -LiteralPath $destDir -PathType Container)) {
          $json = @{ error = "Zielordner existiert nicht" } | ConvertTo-Json -Compress
          Send-ResponseText -Response $res -Text $json -StatusCode 400 -ContentType "application/json; charset=utf-8"
          continue
        }

        $ok = 0
        $fail = 0
        $errors = @()

        # Ordner verschieben
        foreach ($relFolder in $selectedFolders) {
          try {
            $srcFull = Resolve-FullPathSafe -RootFull $RootFull -RelPath $relFolder
            if (Test-Path -LiteralPath $srcFull -PathType Container) {
              $folderName = Split-Path -Leaf $srcFull
              $destPath = Join-Path $destDir $folderName

              # Bei Namenskollision umbenennen
              if (Test-Path -LiteralPath $destPath) {
                $i = 1
                do {
                  $destPath = Join-Path $destDir ("{0}__{1}" -f $folderName, $i)
                  $i++
                } while (Test-Path -LiteralPath $destPath)
              }

              Move-Item -LiteralPath $srcFull -Destination $destPath -Force
              $ok++
            } else {
              $fail++
              $errors += "E050 Ordner nicht gefunden: $relFolder"
            }
          } catch {
            $fail++
            $errors += "E050 $relFolder : $($_.Exception.Message)"
          }
        }

        # Medien verschieben
        foreach ($relImg in $selectedImgs) {
          try {
            $imgFull = Resolve-FullPathSafe -RootFull $RootFull -RelPath $relImg
            if (Test-Path -LiteralPath $imgFull -PathType Leaf) {
              $fileName = Split-Path -Leaf $imgFull
              $destPath = Join-Path $destDir $fileName

              # Bei Namenskollision umbenennen
              if (Test-Path -LiteralPath $destPath) {
                $baseName = [IO.Path]::GetFileNameWithoutExtension($fileName)
                $ext = [IO.Path]::GetExtension($fileName)
                $i = 1
                do {
                  $destPath = Join-Path $destDir ("{0}__{1}{2}" -f $baseName, $i, $ext)
                  $i++
                } while (Test-Path -LiteralPath $destPath)
              }

              Move-Item -LiteralPath $imgFull -Destination $destPath -Force
              $ok++
            } else {
              $fail++
              $errors += "E050 Medium nicht gefunden: $relImg"
            }
          } catch {
            $fail++
            $errors += "E050 $relImg : $($_.Exception.Message)"
          }
        }

        $Folders = Scan-ImageFolders -Root $RootFull -ImageExt $MediaExt -UseCache

        $msg = "Verschoben: OK=$ok | FAIL=$fail"
        if ($errors.Count -gt 0) {
          $msg += " | Fehler: " + ($errors -join " || ")
        }

        $json = @{ ok = $ok; fail = $fail; msg = $msg } | ConvertTo-Json -Compress
        Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"
        continue
      }

      if ($path -eq "/delete" -and $req.HttpMethod -eq "POST") {
        $body = Read-RequestBody -Request $req
        $form = Parse-FormUrlEncoded -Body $body

        if (-not $form.ContainsKey("confirm") -or $form["confirm"] -ne "1") {
          Send-ResponseText -Response $res -Text '{"error":"Keine Bestätigung"}' -StatusCode 400 -ContentType "application/json; charset=utf-8"
          continue
        }

        # Ordner sammeln
        $selectedFolders = @()
        if ($form.ContainsKey("folder")) {
          if ($form["folder"] -is [System.Collections.IList]) { $selectedFolders = @($form["folder"]) }
          else { $selectedFolders = @($form["folder"]) }
        }

        # Medien sammeln
        $selectedImgs = @()
        if ($form.ContainsKey("img")) {
          if ($form["img"] -is [System.Collections.IList]) { $selectedImgs = @($form["img"]) }
          else { $selectedImgs = @($form["img"]) }
        }

        if ($selectedFolders.Count -eq 0 -and $selectedImgs.Count -eq 0) {
          Send-ResponseText -Response $res -Text '{"error":"Nichts ausgewählt"}' -StatusCode 400 -ContentType "application/json; charset=utf-8"
          continue
        }

        # Sofort antworten – Löschung läuft im Hintergrund
        $json = @{ ok = 0; queued = ($selectedFolders.Count + $selectedImgs.Count); msg = "Löschung gestartet" } | ConvertTo-Json -Compress
        Send-ResponseText -Response $res -Text $json -StatusCode 200 -ContentType "application/json; charset=utf-8"

        # --- Background-Löschung mit geladenen Libs ---
        $delRootFull   = $RootFull
        $delHardDelete = [bool]$HardDelete
        $delFolders    = $selectedFolders
        $delImgs       = $selectedImgs

        # Lib-Inhalte als String einlesen
        $libFileSystemPath = Join-Path $ProjectRoot "Lib\Lib_FileSystem.ps1"
        $libFileSystemContent = Get-Content -LiteralPath $libFileSystemPath -Raw

        $ps = [PowerShell]::Create()
        $null = $ps.AddScript({
          param($RootFull, $DoHardDelete, $SelFolders, $SelImgs, $LibCode)

          # Lib-Funktionen in Runspace laden
          Invoke-Expression $LibCode

          # Assembly für FileSystem laden
          Add-Type -AssemblyName Microsoft.VisualBasic | Out-Null

          # --- Medien nach Ordner gruppieren (für schnelleres Löschen) ---
          $imgsByFolder = @{}
          foreach ($relImg in $SelImgs) {
            try {
              $imgFull = Resolve-FullPathSafe -RootFull $RootFull -RelPath $relImg
              $parentDir = Split-Path -Parent $imgFull
              $parentRel = Get-RelativePathSafe -Base $RootFull -Full $parentDir
              
              if (-not $imgsByFolder.ContainsKey($parentRel)) { 
                $imgsByFolder[$parentRel] = @() 
              }
              $imgsByFolder[$parentRel] += $imgFull
            } catch {
              Write-Warning "Fehler beim Auflösen von $relImg : $($_.Exception.Message)"
            }
          }

          # Medien GRUPPIERT löschen (alle Medien eines Ordners auf einmal)
          foreach ($folderRel in $imgsByFolder.Keys) {
            $imgFiles = $imgsByFolder[$folderRel]
            
            if ($DoHardDelete) {
              # HardDelete: einzeln löschen
              foreach ($imgFull in $imgFiles) {
                try {
                  if (Test-Path -LiteralPath $imgFull -PathType Leaf) {
                    Remove-Item -LiteralPath $imgFull -Force
                  }
                } catch {
                  Write-Warning "Fehler beim Löschen von ${imgFull}: $($_.Exception.Message)"
                }
              }
            } else {
              # Papierkorb: gruppiert löschen (schneller)
              foreach ($imgFull in $imgFiles) {
                try {
                  if (Test-Path -LiteralPath $imgFull -PathType Leaf) {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                      $imgFull,
                      [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                      [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                    )
                  }
                } catch {
                  Write-Warning "Fehler beim Löschen von ${imgFull}: $($_.Exception.Message)"
                }
              }
            }
          }

          # Ordner löschen
          foreach ($relFolder in $SelFolders) {
            try {
              Delete-FolderSafe -RootFull $RootFull -RelFolder $relFolder -HardDelete:$DoHardDelete
            } catch {
              Write-Warning "Fehler beim Löschen von Ordner ${relFolder}: $($_.Exception.Message)"
            }
          }
        })

        # Parameter übergeben
        $null = $ps.AddParameter("RootFull", $delRootFull)
        $null = $ps.AddParameter("DoHardDelete", $delHardDelete)
        $null = $ps.AddParameter("SelFolders", $delFolders)
        $null = $ps.AddParameter("SelImgs", $delImgs)
        $null = $ps.AddParameter("LibCode", $libFileSystemContent)

        $null = $ps.BeginInvoke()
        continue
      }

      Send-ResponseText -Response $res -Text "Not found" -StatusCode 404
    } catch {
      Send-ResponseText -Response $res -Text ("Server error: " + $_.Exception.Message) -StatusCode 500
    }
  }
}
finally {
  if ($listener.IsListening) { $listener.Stop() }
  $listener.Close()
}
