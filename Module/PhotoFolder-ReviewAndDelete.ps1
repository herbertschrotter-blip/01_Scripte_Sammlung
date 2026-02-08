<#
ManifestHint:
  ExportFunctions = @()
  Description     = "Lokale HTML-Übersicht für Bildordner (rekursiv), Ordner auswählen + löschen (Papierkorb), Ordner zuklappbar (ganze Zeile klickbar), Thumbnails on-demand (lagarm), Thumbnail-Größenumschaltung (S/M/L), Bild-Viewer mit Navigation (Pfeiltasten + Klick links/rechts), Beenden per X. /img liefert per Streaming."
  Category        = "Media"
  Tags            = @("Photos","HTML","Gallery","Recursive","DeleteFolders","RecycleBin","HttpListener","Lightbox","Collapse","Shutdown","OnDemand","ThumbSize","ArrowKeys","NextPrev","Streaming")
  Dependencies    = @("System.Net.HttpListener","System.Windows.Forms","Microsoft.VisualBasic")

Zweck:
  - Root wählen (Dialog, wenn -RootPath nicht gesetzt).
  - Alle Unterordner scannen und Ordner listen, die Bilddateien enthalten.
  - Pro Ordner: Bilder on-demand laden (erst beim Aufklappen werden <img>-Tags erzeugt).
  - Thumbnail-Größe umschaltbar (klein/mittel/groß), Einstellung bleibt gespeichert.
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
#>

param(
  [string]$RootPath,
  [int]$Port = 8787,
  [switch]$HardDelete
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Libs laden (aus ..\Lib)
# ------------------------------------------------------------
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

. (Join-Path $ProjectRoot "Lib\Lib_Web.ps1")
. (Join-Path $ProjectRoot "Lib\Lib_Index.ps1")

# -----------------------------
# Einstellungen
# -----------------------------
$ImageExt = @(".jpg",".jpeg",".png",".webp",".gif",".bmp",".tif",".tiff")

function Write-Err {
  param([string]$Code, [string]$Msg)
  Write-Host "$Code $Msg" -ForegroundColor Red
}

# -----------------------------
# Root per Dialog (wenn nicht übergeben)
# -----------------------------
if ([string]::IsNullOrWhiteSpace($RootPath)) {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
  $dlg.Description = "Root-Ordner auswählen"
  $dlg.ShowNewFolderButton = $false

  if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK -or
      [string]::IsNullOrWhiteSpace($dlg.SelectedPath)) {
    Write-Err "E010" "Kein Root-Ordner ausgewählt"
    return
  }

  $RootPath = $dlg.SelectedPath
}

if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
  Write-Err "E010" "RootPath existiert nicht: $RootPath"
  return
}

$RootFull = [System.IO.Path]::GetFullPath($RootPath)

try {
  $Folders = Scan-ImageFolders -Root $RootFull -ImageExt $ImageExt
} catch {
  Write-Err "E030" "Scan fehlgeschlagen: $($_.Exception.Message)"
  return
}

# -----------------------------
# HTML Renderer
# -----------------------------
function Render-IndexPage {
  param(
    [string]$RootFull,
    [object[]]$Folders,
    [string]$Msg = ""
  )

  $rows = New-Object System.Text.StringBuilder

  foreach ($f in $Folders) {
    $rel = $f.RelPath
    $cnt = $f.ImgCount

    $imgList = ($f.ImagesRel | ForEach-Object { "/img?path=$(UrlEncode($_))" }) -join "|"

    [void]$rows.AppendLine(@"
<div class="card" data-path="$(HtmlEncode($rel))">
  <div class="hdr" onclick="toggleFolderRow(event, this)">
    <input type="checkbox" name="folder" value="$(HtmlEncode($rel))" />
    <span class="path">$(HtmlEncode($rel))</span>
    <span class="meta">($cnt)</span>
    <button class="toggleBtn" type="button" onclick="toggleFolder(this)">▸</button>
  </div>
  <div class="thumbs isCollapsed" data-loaded="0" data-images="$(HtmlEncode($imgList))"></div>
</div>
"@)
  }

  $msgHtml = ""
  if (-not [string]::IsNullOrWhiteSpace($Msg)) {
    $msgHtml = "<div class='msg'>$(HtmlEncode($Msg))</div>"
  }

  $hardInfo = if ($HardDelete) { "<b>HARD DELETE</b> (ohne Papierkorb!)" } else { "Papierkorb" }

@"
<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Foto-Ordner Review & Delete</title>
<style>
  body{font-family:Arial, sans-serif; margin:16px; background:#f7f7f7;}
  .top{display:flex; gap:12px; align-items:center; flex-wrap:wrap;}
  .box{background:#fff; padding:12px; border-radius:10px; box-shadow:0 1px 4px rgba(0,0,0,.08);}
  .msg{margin:12px 0; padding:10px; border-radius:8px; background:#e9f5ff;}
  .grid{display:grid; grid-template-columns:1fr; gap:10px; margin-top:12px;}
  .card{background:#fff; padding:10px; border-radius:10px; box-shadow:0 1px 4px rgba(0,0,0,.08);}
  .hdr{display:flex; gap:10px; align-items:center; cursor:pointer; user-select:none;}
  .path{font-weight:600; word-break:break-all;}
  .meta{opacity:.7;}
  .thumbs{display:flex; gap:8px; flex-wrap:wrap; margin-top:8px;}
  .thumbs.isCollapsed{display:none;}

  :root{ --thumb:140px; }
  img.t{width:var(--thumb); height:var(--thumb); object-fit:cover; border-radius:10px; background:#ddd; cursor:zoom-in;}

  input[type=text]{padding:8px; min-width:260px;}
  button{padding:10px 14px; border:0; border-radius:10px; cursor:pointer;}
  button.danger{background:#c62828; color:#fff;}
  button.neutral{background:#444; color:#fff;}
  .hint{opacity:.75; font-size:12px;}

  .toggleBtn{
    margin-left:auto;
    padding:6px 10px;
    border-radius:10px;
    background:#eee;
    cursor:pointer;
    font-weight:600;
  }
  .toggleBtn:hover{background:#e0e0e0;}

  .closeBtn{
    position:fixed;
    top:12px;
    right:12px;
    font-size:18px;
    font-weight:bold;
    background:#c62828;
    color:#fff;
    border:none;
    border-radius:50%;
    width:36px;
    height:36px;
    cursor:pointer;
    box-shadow:0 1px 4px rgba(0,0,0,.20);
  }
  .closeBtn:hover{ background:#b71c1c; }

  /* Viewer (Lightbox) */
  #viewer{
    position:fixed;
    inset:0;
    background:rgba(0,0,0,.92);
    display:none;
    align-items:center;
    justify-content:center;
    z-index:9999;
  }
  #viewerInner{
    position:relative;
    max-width:96vw;
    max-height:96vh;
  }
  #viewerImg{
    max-width:96vw;
    max-height:96vh;
    border-radius:12px;
    display:block;
    cursor:pointer;
  }
  #viewerX{
    position:absolute;
    top:-10px;
    right:-10px;
    width:38px;
    height:38px;
    border-radius:50%;
    border:0;
    background:#c62828;
    color:#fff;
    font-weight:700;
    cursor:pointer;
    box-shadow:0 1px 6px rgba(0,0,0,.35);
  }

  #viewerBar{
    margin-top:10px;
    text-align:center;
  }
  #viewerOpen{
    display:inline-block;
    padding:10px 14px;
    border-radius:10px;
    background:#444;
    color:#fff;
    text-decoration:none;
    font-weight:600;
  }
  #viewerOpen:hover{background:#333;}
</style>
</head>
<body>
  <button class="closeBtn" title="Beenden" onclick="shutdown()">X</button>

  <div class="box top">
    <div>
      <div><b>Root:</b> $(HtmlEncode($RootFull))</div>
      <div class="hint"><b>Löschmodus:</b> $hardInfo</div>
    </div>

    <div style="flex:1"></div>

    <input id="filter" type="text" placeholder="Filter (Teilstring im Ordnerpfad)" oninput="applyFilter()" />

    <div class="hint" style="margin-right:8px;">
      Thumbnails:
      <button class="neutral" type="button" onclick="setThumbSize('s')">klein</button>
      <button class="neutral" type="button" onclick="setThumbSize('m')">mittel</button>
      <button class="neutral" type="button" onclick="setThumbSize('l')">groß</button>
    </div>

    <button class="neutral" type="button" onclick="selectAll(true)">Alle</button>
    <button class="neutral" type="button" onclick="selectAll(false)">Keine</button>
    <button class="danger"  type="button" onclick="submitDelete()">Ausgewählte Ordner löschen</button>
  </div>

  $msgHtml

  <form id="delForm" method="post" action="/delete">
    <input type="hidden" name="confirm" value="0" />
    <div id="list" class="grid">
      $( $rows.ToString() )
    </div>
  </form>

  <div id="viewer" onclick="closeViewer()">
    <div id="viewerInner" onclick="event.stopPropagation()">
      <button id="viewerX" type="button" onclick="closeViewer()">X</button>
      <img id="viewerImg" src="" title="Links klicken = zurück | Rechts klicken = vorwärts" />
      <div id="viewerBar"><a id="viewerOpen" href="" target="_blank" rel="noopener">In neuem Tab öffnen</a></div>
    </div>
  </div>

<script>
// --- Thumbnail-Größen (persistiert) ---
function applyThumbSize(mode){
  const px = (mode === "s") ? 90 : (mode === "l") ? 200 : 140;
  document.documentElement.style.setProperty("--thumb", px + "px");
}
function setThumbSize(mode){
  localStorage.setItem("thumbSizeMode", mode);
  applyThumbSize(mode);
}
(function initThumbSize(){
  const mode = localStorage.getItem("thumbSizeMode") || "m";
  applyThumbSize(mode);
})();

function selectAll(state){
  document.querySelectorAll("input[type=checkbox][name=folder]").forEach(cb => cb.checked = state);
}
function applyFilter(){
  const q = document.getElementById("filter").value.toLowerCase();
  document.querySelectorAll(".card").forEach(card => {
    const path = card.getAttribute("data-path").toLowerCase();
    card.style.display = path.includes(q) ? "" : "none";
  });
}
function submitDelete(){
  const checked = Array.from(document.querySelectorAll("input[type=checkbox][name=folder]:checked")).length;
  if(checked === 0){ alert("Keine Ordner ausgewählt."); return; }
  const ok = confirm("Wirklich " + checked + " Ordner löschen? (Papierkorb/HardDelete je nach Modus)");
  if(!ok) return;
  document.querySelector("#delForm input[name=confirm]").value = "1";
  document.getElementById("delForm").submit();
}

// ganze Zeile klickbar, ohne Checkbox/Button zu triggern
function toggleFolderRow(ev, hdrEl){
  const t = ev.target;
  if (!t) return;

  const tag = (t.tagName || "").toLowerCase();
  if (tag === "input" || tag === "button" || tag === "a") return;

  const card = hdrEl.closest(".card");
  const btn = card.querySelector(".toggleBtn");
  toggleFolder(btn);
}

// Entfernt viele <img>-Elemente in kleinen Batches, damit das Zuklappen nicht "einfriert"
function unloadThumbs(thumbs){
  const batchSize = 25;
  function step(){
    let n = 0;
    while(thumbs.firstChild && n < batchSize){
      thumbs.removeChild(thumbs.firstChild);
      n++;
    }
    if(thumbs.firstChild){
      requestAnimationFrame(step);
      return;
    }
    thumbs.dataset.loaded = "0";
  }
  requestAnimationFrame(step);
}

// --- Viewer Navigation State ---
window.folderImages = window.folderImages || {};
window.viewerState = { folderKey:null, urls:[], idx:0 };

function openViewerBy(folderKey, idx){
  const urls = window.folderImages[folderKey] || [];
  if (!urls.length) return;

  window.viewerState.folderKey = folderKey;
  window.viewerState.urls = urls;
  window.viewerState.idx = Math.max(0, Math.min(idx, urls.length - 1));

  const src = urls[window.viewerState.idx];

  const v = document.getElementById("viewer");
  const img = document.getElementById("viewerImg");
  const a = document.getElementById("viewerOpen");

  img.src = src;
  a.href = src;
  v.style.display = "flex";
}

function viewerPrev(){
  const st = window.viewerState;
  if (!st.urls.length) return;
  st.idx = (st.idx - 1 + st.urls.length) % st.urls.length;
  openViewerBy(st.folderKey, st.idx);
}

function viewerNext(){
  const st = window.viewerState;
  if (!st.urls.length) return;
  st.idx = (st.idx + 1) % st.urls.length;
  openViewerBy(st.folderKey, st.idx);
}

function toggleFolder(btn){
  const card = btn.closest(".card");
  const thumbs = card.querySelector(".thumbs");

  if (!thumbs.classList.contains("isCollapsed")) {
    thumbs.classList.add("isCollapsed");
    unloadThumbs(thumbs);
    btn.textContent = "▸";
    return;
  }

  thumbs.classList.remove("isCollapsed");
  btn.textContent = "▾";

  if (thumbs.dataset.loaded === "1") return;

  const data = thumbs.dataset.images || "";
  if (!data) { thumbs.dataset.loaded = "1"; return; }

  const urls = data.split("|").filter(Boolean);
  const folderKey = card.getAttribute("data-path");

  window.folderImages = window.folderImages || {};
  window.folderImages[folderKey] = urls;

  const frag = document.createDocumentFragment();

  urls.forEach((src, i) => {
    const img = document.createElement("img");
    img.className = "t";
    img.loading = "lazy";
    img.src = src;
    img.addEventListener("click", () => openViewerBy(folderKey, i));
    frag.appendChild(img);
  });

  thumbs.appendChild(frag);
  thumbs.dataset.loaded = "1";
}

function closeViewer(){
  const v = document.getElementById("viewer");
  const img = document.getElementById("viewerImg");
  v.style.display = "none";
  img.src = "";
}

document.addEventListener("keydown", (e) => {
  if(e.key === "Escape") closeViewer();
  if(e.key === "ArrowLeft") viewerPrev();
  if(e.key === "ArrowRight") viewerNext();
});

// Klick links/rechts im Bild -> prev/next
document.getElementById("viewerImg").addEventListener("click", (e) => {
  const rect = e.target.getBoundingClientRect();
  const x = e.clientX - rect.left;
  if (x < rect.width / 2) viewerPrev();
  else viewerNext();
});

function shutdown(){
  if(!confirm("HTML-Tool beenden?")) return;
  fetch("/shutdown", { method:"POST" })
    .then(() => window.close())
    .catch(() => window.close());
}
</script>
</body>
</html>
"@
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
        $html = Render-IndexPage -RootFull $RootFull -Folders $Folders
        Send-ResponseHtml -Response $res -Html $html
        continue
      }

      if ($path -eq "/shutdown" -and $req.HttpMethod -eq "POST") {
        $ServerRunning = $false
        Send-ResponseHtml -Response $res -Html "<html><body>Server beendet</body></html>"
        break
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

      if ($path -eq "/delete" -and $req.HttpMethod -eq "POST") {
        $body = Read-RequestBody -Request $req
        $form = Parse-FormUrlEncoded -Body $body

        if (-not $form.ContainsKey("confirm") -or $form["confirm"] -ne "1") {
          $html = Render-IndexPage -RootFull $RootFull -Folders $Folders -Msg "Löschen abgebrochen (keine Bestätigung)."
          Send-ResponseHtml -Response $res -Html $html
          continue
        }

        $selected = @()
        if ($form.ContainsKey("folder")) {
          if ($form["folder"] -is [System.Collections.IList]) { $selected = @($form["folder"]) }
          else { $selected = @($form["folder"]) }
        }

        if ($selected.Count -eq 0) {
          $html = Render-IndexPage -RootFull $RootFull -Folders $Folders -Msg "Keine Ordner ausgewählt."
          Send-ResponseHtml -Response $res -Html $html
          continue
        }

        $ok = 0
        $fail = 0
        $errors = @()

        foreach ($relFolder in $selected) {
          try {
            Delete-FolderSafe -RootFull $RootFull -RelFolder $relFolder -HardDelete:$HardDelete
            $ok++
          } catch {
            $fail++
            $errors += "E040 $relFolder : $($_.Exception.Message)"
          }
        }

        $Folders = Scan-ImageFolders -Root $RootFull -ImageExt $ImageExt

        $msg = "Gelöscht: OK=$ok | FAIL=$fail"
        if ($errors.Count -gt 0) {
          $msg += " | Fehler: " + ($errors -join " || ")
        }

        $html = Render-IndexPage -RootFull $RootFull -Folders $Folders -Msg $msg
        Send-ResponseHtml -Response $res -Html $html
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
