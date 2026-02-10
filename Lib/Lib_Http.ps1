<# 
ManifestHint:
  ExportFunctions = @(
    "HtmlEncode","UrlEncode","UrlDecode",
    "Read-RequestBody","Parse-FormUrlEncoded",
    "Send-ResponseHtml","Send-ResponseText","Send-ResponseFile"
  )
  Description     = "HTTP Helper für HttpListener: Encoding, Request/Response Handling, File Streaming"
  Category        = "Web"
  Tags            = @("HttpListener","HTTP","Response","FormUrlEncoded","Encoding","Streaming")
  Dependencies    = @()

Zweck:
  - Helper-Funktionen für HttpListener
  - Encoding/Decoding (HTML, URL)
  - Request Body Reading + Form Parsing
  - Response Sending (HTML, Text, File)
  - File-Streaming für Bilder/Videos
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
# Response: HTML
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

# ------------------------------------------------------------
# Response: Text (auch für JSON)
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# Response: File Streaming (RAM-schonend)
# ------------------------------------------------------------
function Send-ResponseFile {
  param(
    [System.Net.HttpListenerResponse]$Response,
    [string]$FilePath,
    [string]$ContentType
  )

  if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
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