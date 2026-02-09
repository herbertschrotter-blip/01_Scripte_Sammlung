<# 
ManifestHint:
  ExportFunctions = @(
    "HtmlEncode","UrlEncode","UrlDecode",
    "Read-RequestBody","Parse-FormUrlEncoded",
    "Send-ResponseHtml","Send-ResponseText","Send-ResponseBytes",
    "Start-WebServer","Stop-WebServer","Send-ResponseFile"
  )
  Description     = "Web/HTTP Helper + Server-Layer für HttpListener"
  Category        = "Media"
  Tags            = @("HttpListener","HTML","Response","FormUrlEncoded","Encoding","WebServer","Streaming")
  Dependencies    = @()

Zweck:
  - Helper-Funktionen für HttpListener
  - Server-Betrieb (Start/Stop)
  - Datei-Streaming (z.B. /img)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Encoding Helper
# ------------------------------------------------------------
function HtmlEncode([string]$s) { [System.Net.WebUtility]::HtmlEncode($s) }
function UrlEncode([string]$s)  { [System.Net.WebUtility]::UrlEncode($s) }
function UrlDecode([string]$s)  { [System.Net.WebUtility]::UrlDecode($s) }

# ------------------------------------------------------------
# Request Body lesen
# ------------------------------------------------------------
function Read-RequestBody {
  param([System.Net.HttpListenerRequest]$Request)

  $sr = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
  try { return $sr.ReadToEnd() }
  finally { $sr.Close() }
}

# ------------------------------------------------------------
# application/x-www-form-urlencoded parsen
# ------------------------------------------------------------
function Parse-FormUrlEncoded {
  param([string]$Body)

  $dict = @{}
  foreach ($pair in ($Body -split "&")) {
    if ([string]::IsNullOrWhiteSpace($pair)) { continue }

    $kv = $pair -split "=", 2
    $k = UrlDecode($kv[0])
    $v = if ($kv.Count -gt 1) { UrlDecode($kv[1]) } else { "" }

    if ($dict.ContainsKey($k)) {
      if ($dict[$k] -is [System.Collections.IList]) {
        $dict[$k].Add($v) | Out-Null
      } else {
        $arr = New-Object System.Collections.ArrayList
        $arr.Add($dict[$k]) | Out-Null
        $arr.Add($v) | Out-Null
        $dict[$k] = $arr
      }
    } else {
      $dict[$k] = $v
    }
  }
  return $dict
}

# ------------------------------------------------------------
# Responses
# ------------------------------------------------------------
function Send-ResponseHtml {
  param(
    [System.Net.HttpListenerResponse]$Response,
    [string]$Html,
    [int]$StatusCode = 200
  )

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Html)
  $Response.StatusCode = $StatusCode
  $Response.ContentType = "text/html; charset=utf-8"
  $Response.ContentLength64 = $bytes.Length
  $Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $Response.OutputStream.Close()
}

function Send-ResponseText {
  param(
    [System.Net.HttpListenerResponse]$Response,
    [string]$Text,
    [int]$StatusCode = 200,
    [string]$ContentType = "text/plain; charset=utf-8"
  )

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $Response.StatusCode = $StatusCode
  $Response.ContentType = $ContentType
  $Response.ContentLength64 = $bytes.Length
  $Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $Response.OutputStream.Close()
}

function Send-ResponseBytes {
  param(
    [System.Net.HttpListenerResponse]$Response,
    [byte[]]$Bytes,
    [string]$ContentType,
    [int]$StatusCode = 200
  )

  $Response.StatusCode = $StatusCode
  $Response.ContentType = $ContentType
  $Response.ContentLength64 = $Bytes.Length
  $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
  $Response.OutputStream.Close()
}

# ------------------------------------------------------------
# Server-Layer (aus PhotoFolder ausgelagert)
# ------------------------------------------------------------
$script:WebListener = $null

function Start-WebServer {
  param(
    [Parameter(Mandatory)]
    [int]$Port,

    [Parameter(Mandatory)]
    [scriptblock]$OnRequest
  )

  if ($script:WebListener) {
    throw "E001 WebServer läuft bereits"
  }

  $listener = [System.Net.HttpListener]::new()
  $listener.Prefixes.Add("http://localhost:$Port/")
  $listener.Start()

  $script:WebListener = $listener
  Write-Host "[WEB] Server gestartet auf http://localhost:$Port"

  try {
    while ($listener.IsListening) {
      $context = $listener.GetContext()
      & $OnRequest $context
    }
  }
  catch {
    if ($listener.IsListening) {
      Write-Host "[WEB] Fehler: $($_.Exception.Message)"
    }
  }
  finally {
    try { $listener.Stop() } catch {}
    try { $listener.Close() } catch {}
    $script:WebListener = $null
    Write-Host "[WEB] Server gestoppt"
  }
}

function Stop-WebServer {
  if ($script:WebListener -and $script:WebListener.IsListening) {
    try { $script:WebListener.Stop() } catch {}
    try { $script:WebListener.Close() } catch {}
    $script:WebListener = $null
    Write-Host "[WEB] Server manuell gestoppt"
  }
}

# ------------------------------------------------------------
# Datei-Streaming (z.B. /img)
# ------------------------------------------------------------
function Send-ResponseFile {
  param(
    [System.Net.HttpListenerResponse]$Response,
    [string]$FilePath,
    [string]$ContentType
  )

  if (-not (Test-Path $FilePath)) {
    $Response.StatusCode = 404
    $Response.OutputStream.Close()
    return
  }

  $fs = [System.IO.File]::OpenRead($FilePath)
  try {
    $Response.StatusCode = 200
    $Response.ContentType = $ContentType
    $Response.ContentLength64 = $fs.Length
    $fs.CopyTo($Response.OutputStream)
  }
  finally {
    $fs.Close()
    $Response.OutputStream.Close()
  }
}
