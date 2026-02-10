<#
ManifestHint:
  ExportFunctions = @()
  Description     = "Lokale HTML-Übersicht für Bildordner (rekursiv), Ordner auswählen + löschen (Papierkorb), Ordner zuklappbar (ganze Zeile klickbar), im zugeklappten Zustand 10 zufällige Preview-Thumbs pro Ordner, beim Aufklappen werden alle Bilder geladen. Viewer mit Navigation (Pfeiltasten + Klick links/rechts). Beenden per X. /img liefert per Streaming."
  Category        = "Media"
  Tags            = @("Photos","HTML","Gallery","Recursive","DeleteFolders","RecycleBin","HttpListener","Lightbox","Collapse","Shutdown","OnDemand","Preview10Random","ArrowKeys","NextPrev","Streaming")
  Dependencies    = @("System.Net.HttpListener","System.Windows.Forms","Microsoft.VisualBasic")

Zweck:
  - Root wählen (Dialog, wenn -RootPath nicht gesetzt).
  - Alle Unterordner scannen und Ordner listen, die Bilddateien enthalten.
  - Zugeklappt: pro Ordner 10 zufällige Preview-Thumbs immer sichtbar.
  - Aufklappen: Preview ausblenden, alle Bilder on-demand laden.
  - Thumbnail klick -> großer Viewer im Browser (Overlay/Lightbox) + Navigation:
      -> Pfeiltasten Links/Rechts
      -> Klick linke Bildhälfte = zurück, rechte Bildhälfte = vorwärts
  - Ausgewählte Ordner löschen (Papierkorb oder HardDelete).
  - Tool per X in der HTML beenden (kein Strg+C).
  - /img: Streaming statt ReadAllBytes (RAM-schonend).

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
. (Join-Path $ProjectRoot "Lib\Lib_PhotoGallery_UI.ps1")
. (Join-Path $ProjectRoot "Lib\Lib_Dialogs.ps1")

# -----------------------------
# Einstellungen
# -----------------------------
$ImageExt = @(".jpg",".jpeg",".png",".webp",".gif",".bmp",".tif",".tiff")

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
  Write-Host "Scanne Bildordner..."
  $Folders = Scan-ImageFolders -Root $RootFull -ImageExt $ImageExt -UseCache
  Write-Host "Fertig: $($Folders.Count) Ordner mit Bildern gefunden"
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

    $imgList = ($f.ImagesRel | ForEach-Object { "/img?path=$(UrlEncode($_))" }) -join "|"
    $imgRelList = ($f.ImagesRel) -join "|"

    [void]$rows.AppendLine(@"
<div class="card" data-path="$(HtmlEncode($rel))">
  <div class="hdr" onclick="toggleFolderRow(event, this)">
    <input type="checkbox" name="folder" value="$(HtmlEncode($rel))" />
    <span class="path">$(HtmlEncode($rel))</span>
    <span class="meta">($cnt)</span>
    <button class="toggleBtn" type="button" onclick="toggleFolder(this)">▸</button>
  </div>

  <!-- Zugeklappt: 10 zufällige Preview-Thumbs -->
  <div class="previewRow" data-preview-loaded="0" data-images="$(HtmlEncode($imgList))" data-images-rel="$(HtmlEncode($imgRelList))"></div>

  <!-- Aufgeklappt: alle Bilder (on-demand) -->
  <div class="thumbs isCollapsed" data-loaded="0" data-images="$(HtmlEncode($imgList))" data-images-rel="$(HtmlEncode($imgRelList))"></div>
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
          $Folders = Scan-ImageFolders -Root $RootFull -ImageExt $ImageExt -UseCache
          Write-Host ("[INFO] Root gewechselt: {0}" -f $RootFull)
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

        # Streaming statt ReadAllBytes (RAM-schonend)
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

        # Bilder verschieben
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
              $errors += "E050 Bild nicht gefunden: $relImg"
            }
          } catch {
            $fail++
            $errors += "E050 $relImg : $($_.Exception.Message)"
          }
        }

        $Folders = Scan-ImageFolders -Root $RootFull -ImageExt $ImageExt -UseCache

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

        # Bilder sammeln
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

          # --- Bilder nach Ordner gruppieren (für schnelleres Löschen) ---
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

          # Bilder GRUPPIERT löschen (alle Bilder eines Ordners auf einmal)
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