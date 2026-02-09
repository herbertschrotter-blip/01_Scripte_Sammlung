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

    # Für Preview + Vollansicht werden URLs als Liste abgelegt (On-Demand)
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
  @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');

  :root{
    --thumb:140px;
    --c-bg:#f0f2f5;
    --c-surface:#fff;
    --c-border:#e2e5ea;
    --c-text:#1a1d23;
    --c-text-soft:#6b7280;
    --c-accent:#4f6ef7;
    --c-accent-hover:#3b5de7;
    --c-danger:#dc2626;
    --c-danger-hover:#b91c1c;
    --c-success:#059669;
    --radius:12px;
    --radius-sm:8px;
    --shadow-sm:0 1px 3px rgba(0,0,0,.06), 0 1px 2px rgba(0,0,0,.04);
    --shadow-md:0 4px 12px rgba(0,0,0,.08);
    --transition:180ms ease;
  }

  *{box-sizing:border-box;}

  body{
    font-family:'Inter',system-ui,-apple-system,sans-serif;
    margin:0; padding:16px 20px;
    background:var(--c-bg);
    color:var(--c-text);
    line-height:1.5;
  }

  /* --- Toolbar --- */
  .top{
    display:flex; gap:10px; align-items:center; flex-wrap:wrap;
    position:sticky; top:0; z-index:100;
    backdrop-filter:blur(12px);
    -webkit-backdrop-filter:blur(12px);
    background:rgba(255,255,255,.82);
    border-bottom:1px solid var(--c-border);
  }
  .box{
    padding:14px 18px;
    border-radius:var(--radius);
    box-shadow:var(--shadow-sm);
  }

  .rootInfo{font-size:13px; line-height:1.6;}
  .rootInfo b{font-weight:600;}

  /* --- Messages --- */
  .msg{
    margin:14px 0; padding:12px 16px;
    border-radius:var(--radius-sm);
    background:#eff6ff;
    border-left:4px solid var(--c-accent);
    font-size:14px;
    color:#1e40af;
  }

  /* --- Grid / Cards --- */
  .grid{display:grid; grid-template-columns:1fr; gap:10px; margin-top:14px;}

  .card{
    background:var(--c-surface);
    padding:14px 16px;
    border-radius:var(--radius);
    box-shadow:var(--shadow-sm);
    border:1px solid var(--c-border);
    transition:box-shadow var(--transition), border-color var(--transition);
  }
  .card:hover{
    box-shadow:var(--shadow-md);
    border-color:#cbd5e1;
  }

  .hdr{display:flex; gap:10px; align-items:center; cursor:pointer; user-select:none;}
  .hdr input[type=checkbox]{
    width:18px; height:18px;
    accent-color:var(--c-accent);
    cursor:pointer;
    flex-shrink:0;
  }
  .path{font-weight:600; font-size:14px; word-break:break-all;}
  .meta{color:var(--c-text-soft); font-size:13px; font-weight:500;}

  /* --- Thumbnails --- */
  .thumbs{display:flex; gap:8px; flex-wrap:wrap; margin-top:10px;}
  .thumbs.isCollapsed{display:none;}

  .previewRow{display:flex; gap:8px; flex-wrap:wrap; margin-top:10px;}
  .previewRow.isHidden{display:none;}

  img.t{
    width:var(--thumb); height:var(--thumb);
    object-fit:cover;
    border-radius:var(--radius-sm);
    background:#e5e7eb;
    cursor:zoom-in;
    transition:transform var(--transition), box-shadow var(--transition);
  }
  img.t:hover{
    transform:scale(1.04);
    box-shadow:0 4px 16px rgba(0,0,0,.12);
  }

  /* --- Selektierbare Bilder --- */
  .imgWrap{
    position:relative;
    display:inline-block;
  }
  .imgWrap .imgCb{
    position:absolute;
    top:6px;
    left:6px;
    width:20px;
    height:20px;
    accent-color:var(--c-danger);
    cursor:pointer;
    z-index:2;
    opacity:0;
    transition:opacity var(--transition);
  }
  .imgWrap:hover .imgCb,
  .imgWrap .imgCb:checked{
    opacity:1;
  }
  .imgWrap.selected img.t{
    outline:3px solid var(--c-danger);
    outline-offset:-3px;
    opacity:.75;
  }

  /* --- Inputs --- */
  input[type=text]{
    padding:9px 14px;
    min-width:260px;
    border:1px solid var(--c-border);
    border-radius:var(--radius-sm);
    font-family:inherit;
    font-size:13px;
    outline:none;
    transition:border-color var(--transition), box-shadow var(--transition);
  }
  input[type=text]:focus{
    border-color:var(--c-accent);
    box-shadow:0 0 0 3px rgba(79,110,247,.15);
  }

  /* --- Buttons --- */
  button{
    padding:8px 16px;
    border:none;
    border-radius:var(--radius-sm);
    cursor:pointer;
    font-family:inherit;
    font-size:13px;
    font-weight:500;
    transition:background var(--transition), transform 100ms ease, box-shadow var(--transition);
  }
  button:active{transform:scale(.97);}

  button.neutral{
    background:#f1f3f5;
    color:var(--c-text);
    border:1px solid var(--c-border);
  }
  button.neutral:hover{
    background:#e5e7eb;
    border-color:#cbd5e1;
  }

  button.accent{
    background:var(--c-accent);
    color:#fff;
  }
  button.accent:hover{background:var(--c-accent-hover);}

  button.danger{
    background:var(--c-danger);
    color:#fff;
  }
  button.danger:hover{background:var(--c-danger-hover);}

  .hint{color:var(--c-text-soft); font-size:12px; font-weight:500;}

  .toggleBtn{
    margin-left:auto;
    padding:6px 12px;
    border-radius:var(--radius-sm);
    background:#f1f3f5;
    border:1px solid var(--c-border);
    cursor:pointer;
    font-weight:600;
    font-size:13px;
    transition:background var(--transition);
  }
  .toggleBtn:hover{background:#e5e7eb;}

  .closeBtn{
    font-size:16px;
    font-weight:700;
    background:var(--c-danger);
    color:#fff;
    border:none;
    border-radius:50%;
    width:34px;
    height:34px;
    cursor:pointer;
    flex-shrink:0;
    transition:background var(--transition), transform 100ms ease;
    display:inline-flex;
    align-items:center;
    justify-content:center;
  }
  .closeBtn:hover{background:var(--c-danger-hover);}
  .closeBtn:active{transform:scale(.92);}

  /* --- Viewer (Lightbox) --- */
  #viewer{
    position:fixed;
    inset:0;
    background:rgba(0,0,0,.88);
    backdrop-filter:blur(4px);
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
    border-radius:var(--radius);
    display:block;
    cursor:pointer;
  }
  #viewerX{
    position:absolute;
    top:-10px;
    right:-10px;
    width:36px;
    height:36px;
    border-radius:50%;
    border:0;
    background:var(--c-danger);
    color:#fff;
    font-weight:700;
    font-size:14px;
    cursor:pointer;
    box-shadow:0 2px 8px rgba(0,0,0,.3);
    display:inline-flex;
    align-items:center;
    justify-content:center;
    transition:background var(--transition), transform 100ms ease;
  }
  #viewerX:hover{background:var(--c-danger-hover);}
  #viewerX:active{transform:scale(.9);}

  #viewerBar{margin-top:12px; text-align:center;}
  #viewerOpen{
    display:inline-block;
    padding:10px 20px;
    border-radius:var(--radius-sm);
    background:rgba(255,255,255,.15);
    color:#fff;
    text-decoration:none;
    font-weight:600;
    font-size:14px;
    backdrop-filter:blur(4px);
    transition:background var(--transition);
  }
  #viewerOpen:hover{background:rgba(255,255,255,.25);}

  /* --- Thumb size button group --- */
  .sizeGroup{
    display:inline-flex;
    border:1px solid var(--c-border);
    border-radius:var(--radius-sm);
    overflow:hidden;
  }
  .sizeGroup button{
    border:none;
    border-radius:0;
    background:#f9fafb;
    color:var(--c-text);
    padding:6px 12px;
    font-size:12px;
    font-weight:500;
    border-right:1px solid var(--c-border);
  }
  .sizeGroup button:last-child{border-right:none;}
  .sizeGroup button:hover{background:#e5e7eb;}

  /* --- Filter + Auswahl-Buttons --- */
  .filterGroup{
    display:flex;
    flex-direction:column;
    gap:6px;
  }
  .filterGroup input[type=text]{
    width:100%;
    min-width:260px;
  }
  .filterActions{
    display:flex;
    gap:0;
    align-items:center;
  }
  .filterActions .sizeGroup{
    display:flex;
    width:100%;
  }
  .filterActions .sizeGroup button{
    flex:1;
  }
</style>
</head>
<body>
  <div class="box top">
    <div class="rootInfo">
      <div><b>Root:</b> $(HtmlEncode($RootFull))</div>
      <div class="hint"><b>Löschmodus:</b> $hardInfo</div>
    </div>
    <button class="neutral" type="button" onclick="changeRoot()" title="Anderen Root-Ordner wählen">📂 Ordner wählen</button>

    <div style="flex:1"></div>

    <div class="filterGroup">
      <input id="filter" type="text" placeholder="Filter (Ordnerpfad)…" oninput="applyFilter()" />
      <div class="filterActions">
        <div class="sizeGroup">
          <button type="button" onclick="selectAll(true)">Alle</button>
          <button type="button" onclick="selectFiltered()">Auswahl</button>
          <button type="button" onclick="selectAll(false)">Keine</button>
        </div>
      </div>
    </div>

    <div class="sizeGroup">
      <button type="button" onclick="setThumbSize('s')">S</button>
      <button type="button" onclick="setThumbSize('m')">M</button>
      <button type="button" onclick="setThumbSize('l')">L</button>
    </div>

    <button class="danger"  type="button" onclick="submitDelete()">Löschen</button>
    <button class="closeBtn" title="Beenden" onclick="shutdown()">✕</button>
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
  document.querySelectorAll(".imgCb").forEach(cb => {
    cb.checked = state;
    cb.closest(".imgWrap").classList.toggle("selected", state);
  });
}
function selectFiltered(){
  // Erst alles abwählen
  selectAll(false);
  // Dann nur sichtbare (gefilterte) Cards anhaken
  document.querySelectorAll(".card").forEach(card => {
    if(card.style.display === "none") return;
    const folderCb = card.querySelector("input[type=checkbox][name=folder]");
    if(folderCb) folderCb.checked = true;
    card.querySelectorAll(".imgCb").forEach(cb => {
      cb.checked = true;
      cb.closest(".imgWrap").classList.add("selected");
    });
  });
}
function applyFilter(){
  const q = document.getElementById("filter").value.toLowerCase();
  document.querySelectorAll(".card").forEach(card => {
    const path = card.getAttribute("data-path").toLowerCase();
    card.style.display = path.includes(q) ? "" : "none";
  });
}
function submitDelete(){
  const folders = Array.from(document.querySelectorAll("input[type=checkbox][name=folder]:checked"));
  const imgs = Array.from(document.querySelectorAll(".imgCb:checked"));

  if(folders.length === 0 && imgs.length === 0){
    alert("Nichts ausgewählt.");
    return;
  }

  let msg = "";
  if(folders.length > 0) msg += folders.length + " Ordner";
  if(folders.length > 0 && imgs.length > 0) msg += " und ";
  if(imgs.length > 0) msg += imgs.length + " Bilder";
  msg += " löschen?";

  if(!confirm(msg)) return;

  // Hidden inputs für Bilder ins Formular einfügen
  const form = document.getElementById("delForm");

  // Alte img-Inputs entfernen
  form.querySelectorAll("input[name=img]").forEach(el => el.remove());

  imgs.forEach(cb => {
    const hidden = document.createElement("input");
    hidden.type = "hidden";
    hidden.name = "img";
    hidden.value = cb.dataset.rel;
    form.appendChild(hidden);
  });

  form.querySelector("input[name=confirm]").value = "1";
  form.submit();
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
function unloadThumbs(container){
  const batchSize = 25;
  function step(){
    let n = 0;
    while(container.firstChild && n < batchSize){
      container.removeChild(container.firstChild);
      n++;
    }
    if(container.firstChild){
      requestAnimationFrame(step);
      return;
    }
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

function closeViewer(){
  const v = document.getElementById("viewer");
  const img = document.getElementById("viewerImg");
  v.style.display = "none";
  img.src = "";
}

// Tastatursteuerung (nur wenn Viewer offen)
document.addEventListener("keydown", (e) => {
  const v = document.getElementById("viewer");
  if (v.style.display !== "flex") return;

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

// --- Preview: 10 zufällige Bilder pro Ordner (im zugeklappten Zustand sichtbar) ---
function pickRandomUnique(arr, n){
  if (arr.length <= n) return arr.slice();
  const out = [];
  const used = new Set();
  while(out.length < n){
    const i = Math.floor(Math.random() * arr.length);
    if (used.has(i)) continue;
    used.add(i);
    out.push(arr[i]);
  }
  return out;
}

function ensurePreview(card){
  const preview = card.querySelector(".previewRow");
  if (!preview || preview.dataset.previewLoaded === "1") return;

  const data = preview.dataset.images || "";
  const urls = data.split("|").filter(Boolean);
  const rels = (preview.dataset.imagesRel || "").split("|").filter(Boolean);
  if (!urls.length){
    preview.dataset.previewLoaded = "1";
    return;
  }

  const folderKey = card.getAttribute("data-path");

  if (!window.folderImages[folderKey] || window.folderImages[folderKey].length === 0) {
    window.folderImages[folderKey] = urls;
  }

  const sample = pickRandomUnique(Array.from(urls.keys()), 10);

  const frag = document.createDocumentFragment();
  sample.forEach((idx) => {
    const src = urls[idx];
    const rel = rels[idx] || "";
    const wrap = createImgWrap(src, rel, folderKey, idx);
    frag.appendChild(wrap);
  });

  preview.appendChild(frag);
  preview.dataset.previewLoaded = "1";
}

function createImgWrap(src, rel, folderKey, idx){
  const wrap = document.createElement("div");
  wrap.className = "imgWrap";

  const cb = document.createElement("input");
  cb.type = "checkbox";
  cb.className = "imgCb";
  cb.dataset.rel = rel;
  cb.addEventListener("change", (ev) => {
    ev.stopPropagation();
    wrap.classList.toggle("selected", cb.checked);
  });
  cb.addEventListener("click", (ev) => ev.stopPropagation());

  const img = document.createElement("img");
  img.className = "t";
  img.loading = "lazy";
  img.src = src;
  img.addEventListener("click", (ev) => {
    ev.stopPropagation();
    const all = window.folderImages[folderKey] || [src];
    const i = all.indexOf(src);
    openViewerBy(folderKey, i >= 0 ? i : 0);
  });

  wrap.appendChild(cb);
  wrap.appendChild(img);
  return wrap;
}

function initPreviews(){
  const cards = Array.from(document.querySelectorAll(".card"));
  let i = 0;

  function step(){
    const batch = 10; // kleine Batches, damit UI nicht laggt
    let n = 0;
    while(i < cards.length && n < batch){
      ensurePreview(cards[i]);
      i++; n++;
    }
    if (i < cards.length) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
}

document.addEventListener("DOMContentLoaded", initPreviews);

// --- Ordner auf/zu: Preview/Full umschalten, Full on-demand laden ---
function toggleFolder(btn){
  const card = btn.closest(".card");
  const thumbs = card.querySelector(".thumbs");
  const preview = card.querySelector(".previewRow");

  // offen -> zuklappen
  if (!thumbs.classList.contains("isCollapsed")) {
    thumbs.classList.add("isCollapsed");
    unloadThumbs(thumbs);
    thumbs.dataset.loaded = "0";

    if (preview) preview.classList.remove("isHidden");
    btn.textContent = "▸";
    return;
  }

  // zu -> aufklappen
  thumbs.classList.remove("isCollapsed");
  if (preview) preview.classList.add("isHidden");
  btn.textContent = "▾";

  if (thumbs.dataset.loaded === "1") return;

  const data = thumbs.dataset.images || "";
  const urls = data.split("|").filter(Boolean);
  const rels = (thumbs.dataset.imagesRel || "").split("|").filter(Boolean);
  const folderKey = card.getAttribute("data-path");

  window.folderImages[folderKey] = urls;

  const frag = document.createDocumentFragment();
  urls.forEach((src, i) => {
    const rel = rels[i] || "";
    const wrap = createImgWrap(src, rel, folderKey, i);
    frag.appendChild(wrap);
  });

  thumbs.appendChild(frag);
  thumbs.dataset.loaded = "1";
}

function shutdown(){
  if(!confirm("HTML-Tool beenden?")) return;
  fetch("/shutdown", { method:"POST" })
    .then(() => window.close())
    .catch(() => window.close());
}

function changeRoot(){
  fetch("/changeroot", { method:"POST" })
    .then(r => { if(r.ok) window.location.reload(); })
    .catch(e => alert("Fehler: " + e));
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

      if ($path -eq "/changeroot" -and $req.HttpMethod -eq "POST") {
        $dlgRoot = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlgRoot.Description = "Neuen Root-Ordner auswählen"
        $dlgRoot.ShowNewFolderButton = $false

        # Dummy-Form als Owner, damit der Dialog im Vordergrund erscheint
        $owner = New-Object System.Windows.Forms.Form
        $owner.TopMost = $true
        $owner.StartPosition = "Manual"
        $owner.Location = New-Object System.Drawing.Point(-9999,-9999)
        $owner.Size = New-Object System.Drawing.Size(1,1)
        $owner.Show()
        $owner.BringToFront()

        $result = $dlgRoot.ShowDialog($owner)
        $owner.Close()
        $owner.Dispose()

        if ($result -eq [System.Windows.Forms.DialogResult]::OK -and
            -not [string]::IsNullOrWhiteSpace($dlgRoot.SelectedPath) -and
            (Test-Path -LiteralPath $dlgRoot.SelectedPath -PathType Container)) {

          $RootFull = [System.IO.Path]::GetFullPath($dlgRoot.SelectedPath)
          $Folders = Scan-ImageFolders -Root $RootFull -ImageExt $ImageExt
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

      if ($path -eq "/delete" -and $req.HttpMethod -eq "POST") {
        $body = Read-RequestBody -Request $req
        $form = Parse-FormUrlEncoded -Body $body

        if (-not $form.ContainsKey("confirm") -or $form["confirm"] -ne "1") {
          $html = Render-IndexPage -RootFull $RootFull -Folders $Folders -Msg "Löschen abgebrochen (keine Bestätigung)."
          Send-ResponseHtml -Response $res -Html $html
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
          $html = Render-IndexPage -RootFull $RootFull -Folders $Folders -Msg "Nichts ausgewählt."
          Send-ResponseHtml -Response $res -Html $html
          continue
        }

        $ok = 0
        $fail = 0
        $errors = @()

        # Ordner löschen
        foreach ($relFolder in $selectedFolders) {
          try {
            Delete-FolderSafe -RootFull $RootFull -RelFolder $relFolder -HardDelete:$HardDelete
            $ok++
          } catch {
            $fail++
            $errors += "E040 $relFolder : $($_.Exception.Message)"
          }
        }

        # Bilder löschen
        foreach ($relImg in $selectedImgs) {
          try {
            $imgFull = Resolve-FullPathSafe -RootFull $RootFull -RelPath $relImg
            if (Test-Path -LiteralPath $imgFull -PathType Leaf) {
              if ($HardDelete) {
                Remove-Item -LiteralPath $imgFull -Force
              } else {
                Add-Type -AssemblyName Microsoft.VisualBasic | Out-Null
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                  $imgFull,
                  [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                  [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                )
              }
              $ok++
            } else {
              $fail++
              $errors += "E040 Bild nicht gefunden: $relImg"
            }
          } catch {
            $fail++
            $errors += "E040 $relImg : $($_.Exception.Message)"
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