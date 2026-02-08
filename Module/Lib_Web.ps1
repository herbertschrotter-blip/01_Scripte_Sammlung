<#
ManifestHint:
  ExportFunctions = @(
    "HtmlEncode","UrlEncode","UrlDecode",
    "Read-RequestBody","Parse-FormUrlEncoded",
    "Send-ResponseHtml","Send-ResponseText","Send-ResponseBytes"
  )
  Description     = "Web/HTTP Helper für HttpListener: Encoding, Body lesen, Form-Parsing, Response senden."
  Category        = "Media"
  Tags            = @("HttpListener","HTML","Response","FormUrlEncoded","Encoding")
  Dependencies    = @()

Zweck:
  - Helper-Funktionen für HttpListener-Server.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function HtmlEncode([string]$s) { [System.Net.WebUtility]::HtmlEncode($s) }
function UrlEncode([string]$s)  { [System.Net.WebUtility]::UrlEncode($s) }
function UrlDecode([string]$s)  { [System.Net.WebUtility]::UrlDecode($s) }

function Read-RequestBody {
  param([System.Net.HttpListenerRequest]$Request)

  $sr = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
  try { return $sr.ReadToEnd() }
  finally { $sr.Close() }
}

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
