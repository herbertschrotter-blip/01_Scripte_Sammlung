<#
ManifestHint:
  ExportFunctions = @("Get-PhotoGalleryHTML")
  Description     = "HTML/CSS/JS Template für Photo & Video Gallery UI mit Viewer, Lightbox, Preview, Keyboard Navigation, Video-Player"
  Category        = "Media"
  Tags            = @("HTML","Gallery","UI","Template","Lightbox","Viewer","Keyboard","Preview","Video","VideoPlayer")
  Dependencies    = @()

Zweck:
  - HTML/CSS/JS Template für PhotoFolder Gallery (Bilder + Videos)
  - Responsive Design mit Inter Font
  - Lightbox Viewer mit Navigation für Bilder und Videos
  - Video-Player mit Play/Pause/Seek
  - Keyboard Shortcuts (Arrows, Space, Enter, Ctrl+A)
  - Preview-Modus mit 10 zufälligen Thumbnails
  - Collapse/Expand Ordner
  - Filter, Selection, Thumbnail-Größen
  - Video-Icon auf Video-Thumbnails
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-PhotoGalleryHTML {
  param(
    [Parameter(Mandatory)]
    [string]$RootPath,
    
    [Parameter(Mandatory)]
    [string]$CardRowsHTML,
    
    [string]$Message = "",
    
    [bool]$HardDelete = $false
  )

  $msgHtml = ""
  if (-not [string]::IsNullOrWhiteSpace($Message)) {
    $msgHtml = "<div class='msg'>$Message</div>"
  }

  $hardInfo = if ($HardDelete) { "<b>HARD DELETE</b> (ohne Papierkorb!)" } else { "Papierkorb" }

  return @"
<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Foto & Video-Ordner Review & Delete</title>
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

  img.t, video.t{
    width:var(--thumb); height:var(--thumb);
    object-fit:cover;
    border-radius:var(--radius-sm);
    background:#e5e7eb;
    cursor:zoom-in;
    transition:transform var(--transition), box-shadow var(--transition);
  }
  img.t:hover, video.t:hover{
    transform:scale(1.04);
    box-shadow:0 4px 16px rgba(0,0,0,.12);
  }

  /* --- Selektierbare Medien --- */
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
  .imgWrap.selected img.t,
  .imgWrap.selected video.t{
    outline:3px solid var(--c-danger);
    outline-offset:-3px;
    opacity:.75;
  }
  .imgWrap.focused{
    outline:2px solid var(--c-accent);
    outline-offset:2px;
    border-radius:var(--radius-sm);
  }

  /* --- Video Play Icon --- */
  .playIcon{
    position:absolute;
    top:50%;
    left:50%;
    transform:translate(-50%, -50%);
    width:48px;
    height:48px;
    background:rgba(0,0,0,.7);
    border-radius:50%;
    display:flex;
    align-items:center;
    justify-content:center;
    color:#fff;
    font-size:20px;
    pointer-events:none;
    z-index:1;
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
  max-width:98vw;
  max-height:98vh;
  border-radius:var(--radius);
  display:block;
  cursor:pointer;
}
#viewerVideo{
  max-width:98vw;
  max-height:98vh;
  border-radius:var(--radius);
  display:none;
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

  #viewerDel{
    position:fixed;
    top:20px;
    left:20px;
    width:44px;
    height:44px;
    border-radius:50%;
    border:0;
    background:var(--c-danger);
    color:#fff;
    font-size:20px;
    cursor:pointer;
    box-shadow:0 2px 8px rgba(0,0,0,.3);
    display:inline-flex;
    align-items:center;
    justify-content:center;
    transition:background var(--transition), transform 100ms ease;
    z-index:10000;
  }
  #viewerDel:hover{background:var(--c-danger-hover);}
  #viewerDel:active{transform:scale(.9);}

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

  #viewerVLC{
  display:inline-block;
  margin-left:10px;
  padding:10px 20px;
  border-radius:var(--radius-sm);
  background:rgba(255,255,255,.15);
  color:#fff;
  border:none;
  font-weight:600;
  font-size:14px;
  backdrop-filter:blur(4px);
  cursor:pointer;
  transition:background var(--transition);
}
#viewerVLC:hover{background:rgba(255,255,255,.25);}

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

  /* --- Lade-Overlay --- */
  #loadOverlay{
    position:fixed;
    inset:0;
    background:rgba(0,0,0,.5);
    backdrop-filter:blur(4px);
    display:none;
    align-items:center;
    justify-content:center;
    z-index:10000;
  }
  #loadOverlay.active{display:flex;}
  .loadBox{
    background:var(--c-surface);
    padding:28px 40px;
    border-radius:var(--radius);
    box-shadow:var(--shadow-md);
    text-align:center;
    font-size:15px;
    font-weight:500;
  }
  .spinner{
    display:inline-block;
    width:28px; height:28px;
    border:3px solid var(--c-border);
    border-top-color:var(--c-accent);
    border-radius:50%;
    animation:spin .7s linear infinite;
    margin-bottom:12px;
  }
  @keyframes spin{to{transform:rotate(360deg);}}
</style>
</head>
<body>
  <div class="box top">
    <div class="rootInfo">
      <div><b>Root:</b> $RootPath</div>
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

    <button class="neutral" type="button" onclick="submitMove()">Verschieben</button>
    <button class="danger"  type="button" onclick="submitDelete()">Löschen</button>
    <button class="neutral" type="button" onclick="openRecycleBin()" title="Papierkorb öffnen">🗑️</button>
    <button class="closeBtn" title="Beenden" onclick="shutdown()">✕</button>
  </div>

  $msgHtml

  <form id="delForm" method="post" action="/delete">
    <input type="hidden" name="confirm" value="0" />
    <div id="list" class="grid">
      $CardRowsHTML
    </div>
  </form>

  <div id="viewer" onclick="closeViewer()">
    <button id="viewerDel" type="button" onclick="event.stopPropagation(); viewerDelete()" title="Medium löschen">🗑️</button>
    <div id="viewerInner" onclick="event.stopPropagation()">
      <button id="viewerX" type="button" onclick="closeViewer()">X</button>
      <img id="viewerImg" src="" title="Links klicken = zurück | Rechts klicken = vorwärts" />
      <video id="viewerVideo" controls></video>
<div id="viewerBar">
  <a id="viewerOpen" href="" target="_blank" rel="noopener">In neuem Tab öffnen</a>
  <button id="viewerVLC" type="button" onclick="openWithVLC()" style="display:none;">📂 Mit VLC öffnen</button>
</div>   
      </div>
    
  </div>

  <div id="loadOverlay">
    <div class="loadBox">
      <div class="spinner"></div>
      <div id="loadMsg">Lösche…</div>
    </div>
  </div>

<script>
// --- Video Detection ---
function isVideo(src) {
  return src.match(/\/videothumb\?path=/i);
}

function getOriginalMediaSrc(thumbSrc) {
  if (isVideo(thumbSrc)) {
    // /videothumb?path=xxx -> /img?path=xxx (Original-Video)
    return thumbSrc.replace('/videothumb?', '/img?');
  }
  return thumbSrc;
}

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
  selectAll(false);
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

// Intelligenter Scroll-Anker: Nächster Ordner nach dem letzten gelöschten
const allCards = Array.from(document.querySelectorAll('.card'));
const selectedFolders = folders.map(cb => cb.value); // Pfade der zu löschenden Ordner
const selectedImgFolders = new Set();

// Finde Ordner die Bilder enthalten die gelöscht werden
imgs.forEach(cb => {
  const wrap = cb.closest('.imgWrap');
  if (wrap) {
    const folderKey = wrap.dataset.folderKey;
    if (folderKey) selectedImgFolders.add(folderKey);
  }
});

// Alle zu löschenden Ordner kombinieren
const allDeletedFolders = new Set([...selectedFolders, ...selectedImgFolders]);

// Finde den LETZTEN (untersten) zu löschenden Ordner
let lastDeletedCard = null;
let lastDeletedIndex = -1;

allCards.forEach((card, index) => {
  const path = card.dataset.path;
  if (allDeletedFolders.has(path)) {
    if (index > lastDeletedIndex) {
      lastDeletedIndex = index;
      lastDeletedCard = card;
    }
  }
});

// Finde den NÄCHSTEN Ordner nach dem letzten gelöschten
let nextCard = null;
if (lastDeletedCard && lastDeletedIndex < allCards.length - 1) {
  // Es gibt einen Ordner danach
  nextCard = allCards[lastDeletedIndex + 1];
} else if (lastDeletedIndex > 0) {
  // Kein Ordner danach → Nimm den davor
  nextCard = allCards[lastDeletedIndex - 1];
} else {
  // Fallback: Erster Ordner
  nextCard = allCards[0];
}

if (nextCard) {
  sessionStorage.setItem('scrollAnchor', nextCard.dataset.path);
  console.log('Scroll-Anker gesetzt:', nextCard.dataset.path);
}

  let msg = "";
  if(folders.length > 0) msg += folders.length + " Ordner";
  if(folders.length > 0 && imgs.length > 0) msg += " und ";
  if(imgs.length > 0) msg += imgs.length + " Medien";
  msg += " löschen?";

  if(!confirm(msg)) return;

  const overlay = document.getElementById("loadOverlay");
  const loadMsg = document.getElementById("loadMsg");
  overlay.classList.add("active");
  loadMsg.textContent = "Lösche " + (folders.length + imgs.length) + " Elemente…";

  const params = new URLSearchParams();
  params.append("confirm", "1");
  folders.forEach(cb => params.append("folder", cb.value));
  imgs.forEach(cb => params.append("img", cb.dataset.rel));

fetch("/delete", {
    method: "POST",
    headers: {"Content-Type": "application/x-www-form-urlencoded"},
    body: params.toString()
  })
  .then(r => {
    console.log("Delete Response Status:", r.status);
    return r.json();
  })
  .then(data => {
    console.log("Delete Response Data:", data);
    overlay.classList.remove("active");
    
    // Cache leeren
    if ('caches' in window) {
      caches.keys().then(names => {
        names.forEach(name => caches.delete(name));
      });
    }
    
    // Hard Reload mit Timestamp
    setTimeout(() => {
      window.location.href = window.location.pathname + "?t=" + Date.now();
    }, 500);
  })
  .catch(err => {
    console.error("Delete Error:", err);
    overlay.classList.remove("active");
    
    if(confirm("Fehler beim Löschen: " + err + "\n\nSeite trotzdem neu laden?")) {
      if ('caches' in window) {
        caches.keys().then(names => {
          names.forEach(name => caches.delete(name));
        });
      }
      window.location.href = window.location.pathname + "?t=" + Date.now();
    }
  });
}

function toggleFolderRow(ev, hdrEl){
  const t = ev.target;
  if (!t) return;

  const tag = (t.tagName || "").toLowerCase();
  if (tag === "input" || tag === "button" || tag === "a") return;

  const card = hdrEl.closest(".card");
  const btn = card.querySelector(".toggleBtn");
  toggleFolder(btn);
}

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
window.folderTypes = window.folderTypes || {};
window.viewerState = { folderKey:null, urls:[], types:[], idx:0 };

function openViewerBy(folderKey, idx){
  const urls = window.folderImages[folderKey] || [];
  const types = window.folderTypes[folderKey] || [];
  openViewerWith(folderKey, urls, types, idx);
}

function openViewerWith(folderKey, urls, types, idx){
  if (!urls.length) return;

  window.viewerState.folderKey = folderKey;
  window.viewerState.urls = urls;
  window.viewerState.types = types;
  window.viewerState.idx = Math.max(0, Math.min(idx, urls.length - 1));

  const src = urls[window.viewerState.idx];
  const currentType = types[window.viewerState.idx];

  const v = document.getElementById("viewer");
  const viewerImg = document.getElementById("viewerImg");
  const viewerVideo = document.getElementById("viewerVideo");
  const a = document.getElementById("viewerOpen");
  const vlcBtn = document.getElementById("viewerVLC");  // ← NEU

  if (currentType === 'video') {
    // Video anzeigen - mit Lazy Conversion Check
    viewerImg.style.display = 'none';
    viewerVideo.style.display = 'block';
    
    // Conversion-Check starten
    const videoRel = urlToRel(getOriginalMediaSrc(src));
    checkAndConvertVideo(videoRel, viewerVideo, a);
    vlcBtn.style.display = 'inline-block';  // ← NEU: VLC-Button zeigen
  } else {   
    // Bild anzeigen
    viewerVideo.style.display = 'none';
    viewerVideo.pause();
    viewerVideo.src = '';
const cacheBust = "?v=" + Date.now();
    const imgSrc = src.includes("?") ? src + "&v=" + Date.now() : src + cacheBust;
    
    viewerImg.style.display = 'block';
    viewerImg.src = imgSrc;
    a.href = src;

    vlcBtn.style.display = 'none';  // ← NEU: VLC-Button verstecken
  }

  v.style.display = "flex";
  preloadAround(urls, types, window.viewerState.idx, 5);
}
  
window._preloaded = window._preloaded || new Set();

function preloadAround(urls, types, center, range){
  for(let offset = 1; offset <= range; offset++){
    const fwd = (center + offset) % urls.length;
    const bwd = (center - offset + urls.length) % urls.length;
    if (types[fwd] !== 'video') preloadOne(urls[fwd]);
    if (types[bwd] !== 'video') preloadOne(urls[bwd]);
  }
}

function preloadOne(src){
  if(!src || window._preloaded.has(src)) return;
  window._preloaded.add(src);
  const img = new Image();
  img.src = src;
}

function viewerPrev(){
  const st = window.viewerState;
  if (!st.urls.length) return;
  st.idx = (st.idx - 1 + st.urls.length) % st.urls.length;
  
  const viewerImg = document.getElementById("viewerImg");
  const viewerVideo = document.getElementById("viewerVideo");
  const a = document.getElementById("viewerOpen");
  const currentType = st.types[st.idx];

if (currentType === 'video') {
    viewerImg.style.display = 'none';
    viewerVideo.style.display = 'block';
    
    const videoRel = urlToRel(getOriginalMediaSrc(st.urls[st.idx]));
    checkAndConvertVideo(videoRel, viewerVideo, a);
  } else {

    viewerVideo.style.display = 'none';
    viewerVideo.pause();
    viewerVideo.src = '';
const cacheBust = "?v=" + Date.now();
    const imgSrc = st.urls[st.idx].includes("?") ? st.urls[st.idx] + "&v=" + Date.now() : st.urls[st.idx] + cacheBust;
    
    viewerImg.style.display = 'block';
    viewerImg.src = imgSrc;
    a.href = st.urls[st.idx];    
  }
  
  preloadAround(st.urls, st.types, st.idx, 3);
}

function viewerNext(){
  const st = window.viewerState;
  if (!st.urls.length) return;
  st.idx = (st.idx + 1) % st.urls.length;
  
  const viewerImg = document.getElementById("viewerImg");
  const viewerVideo = document.getElementById("viewerVideo");
  const a = document.getElementById("viewerOpen");
  const currentType = st.types[st.idx];

if (currentType === 'video') {
    viewerImg.style.display = 'none';
    viewerVideo.style.display = 'block';
    
    const videoRel = urlToRel(getOriginalMediaSrc(st.urls[st.idx]));
    checkAndConvertVideo(videoRel, viewerVideo, a);
  } else {

    viewerVideo.style.display = 'none';
    viewerVideo.pause();
    viewerVideo.src = '';
const cacheBust = "?v=" + Date.now();
    const imgSrc = st.urls[st.idx].includes("?") ? st.urls[st.idx] + "&v=" + Date.now() : st.urls[st.idx] + cacheBust;
    
    viewerImg.style.display = 'block';
    viewerImg.src = imgSrc;
    a.href = st.urls[st.idx];    
  }
  
  preloadAround(st.urls, st.types, st.idx, 3);
}

function closeViewer(){
  const v = document.getElementById("viewer");
  const viewerImg = document.getElementById("viewerImg");
  const viewerVideo = document.getElementById("viewerVideo");
  v.style.display = "none";
  viewerImg.src = "";
  viewerVideo.pause();
  viewerVideo.src = "";
}

function urlToRel(src){
  try {
    const u = new URL(src, location.origin);
    return u.searchParams.get("path") || "";
  } catch(e){ return ""; }
}

function viewerDelete(){
  const st = window.viewerState;
  if(!st.urls.length) return;

  const src = st.urls[st.idx];
  const rel = urlToRel(isVideo(src) ? getOriginalMediaSrc(src) : src);
  if(!rel) return;

// Scroll-Position speichern (KEIN Reload, nur für Konsistenz)
  sessionStorage.setItem('scrollPosition', window.scrollY);

  const params = new URLSearchParams();
  params.append("confirm", "1");
  params.append("img", rel);

  fetch("/delete", {
    method: "POST",
    headers: {"Content-Type": "application/x-www-form-urlencoded"},
    body: params.toString()
  }).catch(() => {});

  st.urls.splice(st.idx, 1);
  st.types.splice(st.idx, 1);

  if(window.folderImages[st.folderKey]){
    const fi = window.folderImages[st.folderKey];
    const fiIdx = fi.indexOf(src);
    if(fiIdx >= 0) {
      fi.splice(fiIdx, 1);
      window.folderTypes[st.folderKey].splice(fiIdx, 1);
    }
  }

  document.querySelectorAll(".imgCb").forEach(cb => {
    if(cb.dataset.rel === rel){
      const w = cb.closest(".imgWrap");
      if(w) w.remove();
    }
  });

  document.querySelectorAll(".card").forEach(card => {
    if(card.getAttribute("data-path") === st.folderKey){
      const meta = card.querySelector(".meta");
      if(meta){
        const cnt = (window.folderImages[st.folderKey] || []).length;
        meta.textContent = "(" + cnt + ")";
      }
    }
  });

  if(!st.urls.length){
    closeViewer();
    return;
  }

  if(st.idx >= st.urls.length) st.idx = 0;

  const viewerImg = document.getElementById("viewerImg");
  const viewerVideo = document.getElementById("viewerVideo");
  const viewerOpen = document.getElementById("viewerOpen");
  const newSrc = st.urls[st.idx];
  const newType = st.types[st.idx];
  
  if (newType === 'video') {
    viewerImg.style.display = 'none';
    viewerVideo.style.display = 'block';
    viewerVideo.src = '';
    requestAnimationFrame(() => {
      viewerVideo.src = getOriginalMediaSrc(newSrc);
      viewerVideo.load();
      viewerVideo.play().catch(() => {});
      viewerOpen.href = getOriginalMediaSrc(newSrc);
    });
  } else {
    viewerVideo.style.display = 'none';
    viewerVideo.pause();
    viewerVideo.src = '';
const cacheBust = "?v=" + Date.now();
    const imgSrc = newSrc.includes("?") ? newSrc + "&v=" + Date.now() : newSrc + cacheBust;
    
    viewerImg.style.display = 'block';
    viewerImg.src = "";
    requestAnimationFrame(() => {
      viewerImg.src = imgSrc;
      viewerOpen.href = newSrc;
    });    
  }
}

document.getElementById("viewerImg").addEventListener("click", (e) => {
  const rect = e.target.getBoundingClientRect();
  const x = e.clientX - rect.left;
  if (x < rect.width / 2) viewerPrev();
  else viewerNext();
});

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
  const types = (preview.dataset.mediaTypes || "").split("|").filter(Boolean);
  
  if (!urls.length){
    preview.dataset.previewLoaded = "1";
    return;
  }

  const folderKey = card.getAttribute("data-path");

  if (!window.folderImages[folderKey] || window.folderImages[folderKey].length === 0) {
    window.folderImages[folderKey] = urls;
    window.folderTypes[folderKey] = types;
  }

  const sampleIdxs = pickRandomUnique(Array.from(urls.keys()), 10);
  const previewUrls = sampleIdxs.map(i => urls[i]);
  const previewTypes = sampleIdxs.map(i => types[i]);

  window.previewImages = window.previewImages || {};
  window.previewTypes = window.previewTypes || {};
  window.previewImages[folderKey] = previewUrls;
  window.previewTypes[folderKey] = previewTypes;

  const frag = document.createDocumentFragment();
  sampleIdxs.forEach((idx) => {
    const src = urls[idx];
    const rel = rels[idx] || "";
    const type = types[idx] || "image";
    const wrap = createImgWrap(src, rel, type, folderKey, idx, true);
    frag.appendChild(wrap);
  });

  preview.appendChild(frag);
  preview.dataset.previewLoaded = "1";
}

window.selState = { lastClicked: null, focused: null };

function getAllWraps(){
  return Array.from(document.querySelectorAll(".imgWrap"));
}

function getVisibleWraps(){
  return getAllWraps().filter(w => {
    const card = w.closest(".card");
    if(!card || card.style.display === "none") return false;
    const container = w.closest(".thumbs, .previewRow");
    if(!container) return false;
    return !container.classList.contains("isCollapsed") && !container.classList.contains("isHidden");
  });
}

function setWrapSelected(wrap, state){
  const cb = wrap.querySelector(".imgCb");
  if(cb) cb.checked = state;
  wrap.classList.toggle("selected", state);
}

function setFocus(wrap){
  const old = window.selState.focused;
  if(old) old.classList.remove("focused");
  if(wrap){
    wrap.classList.add("focused");
    wrap.scrollIntoView({block:"nearest",behavior:"smooth"});
  }
  window.selState.focused = wrap;
}

function handleImgClick(ev, wrap){
  ev.stopPropagation();
  const wraps = getVisibleWraps();
  const idx = wraps.indexOf(wrap);

  if(ev.shiftKey && window.selState.lastClicked !== null){
    const lastIdx = wraps.indexOf(window.selState.lastClicked);
    if(lastIdx >= 0){
      const from = Math.min(lastIdx, idx);
      const to = Math.max(lastIdx, idx);
      for(let i = from; i <= to; i++){
        setWrapSelected(wraps[i], true);
      }
    }
  } else if(ev.ctrlKey || ev.metaKey){
    const cb = wrap.querySelector(".imgCb");
    setWrapSelected(wrap, !cb.checked);
  } else {
    wraps.forEach(w => setWrapSelected(w, false));
    setWrapSelected(wrap, true);
  }

  window.selState.lastClicked = wrap;
  setFocus(wrap);
}

function createImgWrap(src, rel, type, folderKey, idx, isPreview){
  const wrap = document.createElement("div");
  wrap.className = "imgWrap";
  wrap.dataset.folderKey = folderKey;
  wrap.dataset.idx = idx;
  wrap.dataset.mediaType = type;
  if(isPreview) wrap.dataset.preview = "1";

  const cb = document.createElement("input");
  cb.type = "checkbox";
  cb.className = "imgCb";
  cb.dataset.rel = rel;
  cb.addEventListener("change", (ev) => {
    ev.stopPropagation();
    wrap.classList.toggle("selected", cb.checked);
  });
  cb.addEventListener("click", (ev) => ev.stopPropagation());

const cacheBust = "?v=" + Date.now();
  const imgSrc = src.includes("?") ? src + "&v=" + Date.now() : src + cacheBust;
  
  const img = document.createElement("img");
  img.className = "t";
  img.loading = "lazy";
  img.src = imgSrc;

  img.addEventListener("click", (ev) => {
    handleImgClick(ev, wrap);
  });

  img.addEventListener("dblclick", (ev) => {
    ev.stopPropagation();
    if(isPreview){
      const pUrls = (window.previewImages || {})[folderKey] || [];
      const pTypes = (window.previewTypes || {})[folderKey] || [];
      const pIdx = pUrls.indexOf(src);
      openViewerWith(folderKey, pUrls, pTypes, pIdx >= 0 ? pIdx : 0);
    } else {
      const all = window.folderImages[folderKey] || [src];
      const allTypes = window.folderTypes[folderKey] || [type];
      const i = all.indexOf(src);
      openViewerWith(folderKey, all, allTypes, i >= 0 ? i : 0);
    }
  });

  wrap.appendChild(cb);
  wrap.appendChild(img);

  // Video-Icon hinzufügen
  if (type === 'video') {
    const playIcon = document.createElement("div");
    playIcon.className = "playIcon";
    playIcon.innerHTML = "▶";
    wrap.appendChild(playIcon);
  }

  return wrap;
}

document.addEventListener("keydown", (e) => {
  const viewer = document.getElementById("viewer");
  const viewerVideo = document.getElementById("viewerVideo");
  
  if(viewer.style.display === "flex"){
    if(e.key === "Escape") closeViewer();
    if(e.key === "ArrowLeft") viewerPrev();
    if(e.key === "ArrowRight") viewerNext();
    if(e.key === "Delete") viewerDelete();
    
    // Space = Play/Pause (nur bei Videos)
    if(e.key === " " && viewerVideo.style.display === 'block'){
      e.preventDefault();
      if(viewerVideo.paused) viewerVideo.play();
      else viewerVideo.pause();
    }
    return;
  }

  if(document.activeElement && document.activeElement.tagName === "INPUT") return;

  const wraps = getVisibleWraps();
  if(!wraps.length) return;

  const cur = window.selState.focused;
  const curIdx = cur ? wraps.indexOf(cur) : -1;

  if(e.key === "ArrowRight" || e.key === "ArrowLeft" ||
     e.key === "ArrowDown" || e.key === "ArrowUp"){
    e.preventDefault();
    let nextIdx;
    if(e.key === "ArrowRight" || e.key === "ArrowDown"){
      nextIdx = curIdx < 0 ? 0 : Math.min(curIdx + 1, wraps.length - 1);
    } else {
      nextIdx = curIdx < 0 ? 0 : Math.max(curIdx - 1, 0);
    }
    const next = wraps[nextIdx];

    if(e.shiftKey){
      setWrapSelected(next, true);
    }
    setFocus(next);
    return;
  }

  if(e.key === " " && cur){
    e.preventDefault();
    const cb = cur.querySelector(".imgCb");
    setWrapSelected(cur, !cb.checked);
    return;
  }

  if(e.key === "Enter" && cur){
    e.preventDefault();
    const folderKey = cur.dataset.folderKey;
    const mediaType = cur.dataset.mediaType || "image";
    const img = cur.querySelector("img.t");
    const src = img ? img.src : "";
    
    if(cur.dataset.preview === "1"){
      const pUrls = (window.previewImages || {})[folderKey] || [];
      const pTypes = (window.previewTypes || {})[folderKey] || [];
      const pIdx = pUrls.indexOf(src);
      openViewerWith(folderKey, pUrls, pTypes, pIdx >= 0 ? pIdx : 0);
    } else {
      const idx = parseInt(cur.dataset.idx, 10);
      openViewerBy(folderKey, idx);
    }
    return;
  }

  if((e.ctrlKey || e.metaKey) && e.key === "a"){
    e.preventDefault();
    wraps.forEach(w => setWrapSelected(w, true));
    return;
  }
});

function initPreviews(){
  const cards = Array.from(document.querySelectorAll(".card"));
  let i = 0;

  function step(){
    const batch = 10;
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

// Scroll-Position nach Reload wiederherstellen
window.addEventListener('load', function() {
  const savedAnchor = sessionStorage.getItem('scrollAnchor');
  
  if (savedAnchor) {
    console.log('Scroll-Anker gefunden:', savedAnchor);
    
    // Warte bis DOM vollständig geladen
    setTimeout(function() {
      const card = document.querySelector('.card[data-path="' + savedAnchor + '"]');
      
      if (card) {
        console.log('Scrolle zu:', savedAnchor);
        
        // Scrolle so dass der Ordner oben sichtbar ist (mit kleinem Abstand)
        card.scrollIntoView({ behavior: 'smooth', block: 'start' });
        
        // Optional: Highlight-Effekt (kurz aufblinken)
        card.style.transition = 'background 0.3s ease';
        card.style.background = '#e0f2fe';
        setTimeout(function() {
          card.style.background = '';
        }, 1000);
      } else {
        console.log('Ordner nicht gefunden:', savedAnchor);
        // Ordner existiert nicht mehr - scrolle zum ersten
        const firstCard = document.querySelector('.card');
        if (firstCard) {
          firstCard.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
      }
      
      sessionStorage.removeItem('scrollAnchor');
    }, 200); // Kurze Verzögerung für DOM-Rendering
  }
});

function toggleFolder(btn){
  const card = btn.closest(".card");
  const thumbs = card.querySelector(".thumbs");
  const preview = card.querySelector(".previewRow");

  if (!thumbs.classList.contains("isCollapsed")) {
    thumbs.classList.add("isCollapsed");
    unloadThumbs(thumbs);
    thumbs.dataset.loaded = "0";

    if (preview) preview.classList.remove("isHidden");
    btn.textContent = "▸";
    return;
  }

  thumbs.classList.remove("isCollapsed");
  if (preview) preview.classList.add("isHidden");
  btn.textContent = "▾";

  if (thumbs.dataset.loaded === "1") return;

  const data = thumbs.dataset.images || "";
  const urls = data.split("|").filter(Boolean);
  const rels = (thumbs.dataset.imagesRel || "").split("|").filter(Boolean);
  const types = (thumbs.dataset.mediaTypes || "").split("|").filter(Boolean);
  const folderKey = card.getAttribute("data-path");

  window.folderImages[folderKey] = urls;
  window.folderTypes[folderKey] = types;

  const frag = document.createDocumentFragment();
  urls.forEach((src, i) => {
    const rel = rels[i] || "";
    const type = types[i] || "image";
    const wrap = createImgWrap(src, rel, type, folderKey, i);
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
    .then(r => r.json())
    .then(data => {
      if(data.cancelled) return;
      
      // Cache leeren
      if ('caches' in window) {
        caches.keys().then(names => {
          names.forEach(name => caches.delete(name));
        });
      }
      
      // Hard Reload mit Timestamp
      window.location.href = window.location.pathname + "?t=" + Date.now();
    })
    .catch(e => alert("Fehler: " + e));
}

function openRecycleBin(){
  fetch("/openrecyclebin", { method:"POST" });
}

function submitMove(){
  const folders = Array.from(document.querySelectorAll("input[type=checkbox][name=folder]:checked"));
  const imgs = Array.from(document.querySelectorAll(".imgCb:checked"));

  if(folders.length === 0 && imgs.length === 0){
    alert("Nichts ausgewählt.");
    return;
  }

// Intelligenter Scroll-Anker: Nächster Ordner nach dem letzten verschobenen
  const allCards = Array.from(document.querySelectorAll('.card'));
  const selectedFolders = folders.map(cb => cb.value);
  const selectedImgFolders = new Set();

  imgs.forEach(cb => {
    const wrap = cb.closest('.imgWrap');
    if (wrap) {
      const folderKey = wrap.dataset.folderKey;
      if (folderKey) selectedImgFolders.add(folderKey);
    }
  });

  const allMovedFolders = new Set([...selectedFolders, ...selectedImgFolders]);

  let lastMovedCard = null;
  let lastMovedIndex = -1;

  allCards.forEach((card, index) => {
    const path = card.dataset.path;
    if (allMovedFolders.has(path)) {
      if (index > lastMovedIndex) {
        lastMovedIndex = index;
        lastMovedCard = card;
      }
    }
  });

  let nextCard = null;
  if (lastMovedCard && lastMovedIndex < allCards.length - 1) {
    nextCard = allCards[lastMovedIndex + 1];
  } else if (lastMovedIndex > 0) {
    nextCard = allCards[lastMovedIndex - 1];
  } else {
    nextCard = allCards[0];
  }

  if (nextCard) {
    sessionStorage.setItem('scrollAnchor', nextCard.dataset.path);
    console.log('Move: Scroll-Anker gesetzt:', nextCard.dataset.path);
  }
  const overlay = document.getElementById("loadOverlay");
  const loadMsg = document.getElementById("loadMsg");
  overlay.classList.add("active");
  loadMsg.textContent = "Zielordner wählen…";

  const params = new URLSearchParams();
  folders.forEach(cb => params.append("folder", cb.value));
  imgs.forEach(cb => params.append("img", cb.dataset.rel));

fetch("/move", {
    method: "POST",
    headers: {"Content-Type": "application/x-www-form-urlencoded"},
    body: params.toString()
  })
  .then(r => {
    console.log("Move Response Status:", r.status);
    return r.json();
  })
  .then(data => {
    console.log("Move Response Data:", data);
    overlay.classList.remove("active");
    if(data.cancelled) return;
    
    // Cache leeren
    if ('caches' in window) {
      caches.keys().then(names => {
        names.forEach(name => caches.delete(name));
      });
    }
    
    // Hard Reload mit Timestamp
    setTimeout(() => {
      window.location.href = window.location.pathname + "?t=" + Date.now();
    }, 500);
  })
  .catch(err => {
    console.error("Move Error:", err);
    overlay.classList.remove("active");
    
    if(confirm("Fehler beim Verschieben: " + err + "\n\nSeite trotzdem neu laden?")) {
      if ('caches' in window) {
        caches.keys().then(names => {
          names.forEach(name => caches.delete(name));
        });
      }
      window.location.href = window.location.pathname + "?t=" + Date.now();
    }
  });
}

// --- Lazy Video Conversion ---
function checkAndConvertVideo(videoRel, videoElement, linkElement) {
  // Loading-Overlay erstellen
  const overlay = document.getElementById("loadOverlay");
  const loadMsg = document.getElementById("loadMsg");
  
  overlay.classList.add("active");
  loadMsg.textContent = "Video wird geladen...";
  
  // Conversion-Check
  fetch("/videoconvert", {
    method: "POST",
    headers: {"Content-Type": "application/x-www-form-urlencoded"},
    body: "path=" + encodeURIComponent(videoRel)
  })
  .then(r => r.json())
  .then(data => {
    if (data.status === "ready" || data.status === "not_needed") {
      // Video ist bereit
      overlay.classList.remove("active");
      videoElement.src = data.url;
      linkElement.href = data.url;
      videoElement.load();
      videoElement.play().catch(() => {});
    } else if (data.status === "converting") {
      // Conversion läuft - Status pollen
      loadMsg.textContent = "Video wird konvertiert (DivX → H.264)...";
      pollConversionStatus(videoRel, videoElement, linkElement);
    } else {
      overlay.classList.remove("active");
      alert("Fehler: " + (data.error || "Unbekannter Fehler"));
    }
  })
  .catch(err => {
    overlay.classList.remove("active");
    alert("Fehler beim Laden: " + err);
  });
}

function pollConversionStatus(videoRel, videoElement, linkElement) {
  const overlay = document.getElementById("loadOverlay");
  const loadMsg = document.getElementById("loadMsg");
  
  let pollCount = 0;
  const maxPolls = 120; // 2 Minuten (120 * 1 Sekunde)
  
  const interval = setInterval(() => {
    pollCount++;
    
    if (pollCount > maxPolls) {
      clearInterval(interval);
      overlay.classList.remove("active");
      alert("Timeout: Conversion dauert zu lange. Bitte versuche es später nochmal.");
      return;
    }
    
    fetch("/videoconvert/status?path=" + encodeURIComponent(videoRel))
      .then(r => r.json())
      .then(data => {
        if (data.status === "ready") {
          clearInterval(interval);
          overlay.classList.remove("active");
          
          // Video laden
          videoElement.src = data.url;
          linkElement.href = data.url;
          videoElement.load();
          videoElement.play().catch(() => {});
        } else {
          // Noch am konvertieren - Countdown anzeigen
          const remaining = Math.ceil((maxPolls - pollCount) / 2);
          loadMsg.textContent = "Video wird konvertiert... (" + remaining + "s)";
        }
      })
      .catch(() => {
        // Fehler beim Polling - weitermachen
      });
  }, 1000); // Alle 1 Sekunde prüfen
}

function openWithVLC() {
  const st = window.viewerState;
  if (!st.urls.length) return;
  
  const src = st.urls[st.idx];
  const rel = urlToRel(isVideo(src) ? getOriginalMediaSrc(src) : src);
  if (!rel) return;
  
  fetch("/openvlc", {
    method: "POST",
    headers: {"Content-Type": "application/x-www-form-urlencoded"},
    body: "path=" + encodeURIComponent(rel)
  })
  .then(r => r.json())
  .then(data => {
    if (data.error) {
      alert("Fehler: " + data.error);
    }
  })
  .catch(err => {
    alert("Fehler: " + err);
  });
}


</script>
</body>
</html>
"@
}