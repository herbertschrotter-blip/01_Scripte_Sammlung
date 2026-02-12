#Requires -Version 5.1

<#
.SYNOPSIS
    HTTP-Hilfsfunktionen für HttpListener-basierte Webserver

.DESCRIPTION
    Stellt grundlegende HTTP-Funktionen bereit für PowerShell-basierte Webserver:
    - Senden von HTML-, JSON- und Datei-Antworten
    - Request-Parameter-Parsing
    - Response-Header-Management
    - Fehlerbehandlung für HTTP-Operationen
    
    Optimiert für PhotoFolder-Anwendung, aber generisch verwendbar.

.EXAMPLE
    # Lib laden
    . .\Lib\Lib_Http.ps1
    
    # HTML senden
    Send-HtmlResponse -Context $context -Html "<h1>Hello</h1>"
    
    # JSON senden
    Send-JsonResponse -Context $context -Data @{status='ok'}

.NOTES
    Autor: Herbert Schrotter
    Version: 1.0.0
    
.LINK
    https://github.com/herbertschrotter-blip/01_Scripte_Sammlung
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# ============================================================================
# HTML RESPONSE
# ============================================================================

function Send-HtmlResponse {
    <#
    .SYNOPSIS
        Sendet eine HTML-Antwort an den Client
    
    .DESCRIPTION
        Sendet HTML-Content mit korrekten UTF-8 Headers und Content-Length.
        Schließt automatisch die Response nach dem Senden.
    
    .PARAMETER Context
        HttpListenerContext-Objekt vom Request
    
    .PARAMETER Html
        HTML-String der gesendet werden soll
    
    .PARAMETER StatusCode
        HTTP-Statuscode (Standard: 200)
    
    .EXAMPLE
        Send-HtmlResponse -Context $context -Html "<h1>Willkommen</h1>"
        
        Sendet einfache HTML-Seite mit Status 200
    
    .EXAMPLE
        Send-HtmlResponse -Context $context -Html $errorPage -StatusCode 404
        
        Sendet Fehlerseite mit Status 404
    
    .NOTES
        Verwendet UTF-8 Encoding für korrekte Umlaute
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,
        
        [Parameter(Mandatory)]
        [string]$Html,
        
        [Parameter()]
        [int]$StatusCode = 200
    )
    
    try {
        $response = $Context.Response
        $response.StatusCode = $StatusCode
        $response.ContentType = "text/html; charset=utf-8"
        
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($Html)
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        
        Write-Verbose "HTML Response gesendet: $StatusCode, $($buffer.Length) Bytes"
    }
    catch {
        Write-Error "Fehler beim Senden der HTML-Response: $_"
        throw
    }
    finally {
        if ($response) {
            $response.Close()
        }
    }
}

# ============================================================================
# JSON RESPONSE
# ============================================================================

function Send-JsonResponse {
    <#
    .SYNOPSIS
        Sendet eine JSON-Antwort an den Client
    
    .DESCRIPTION
        Konvertiert PowerShell-Objekte zu JSON und sendet mit korrekten Headers.
        Schließt automatisch die Response nach dem Senden.
    
    .PARAMETER Context
        HttpListenerContext-Objekt vom Request
    
    .PARAMETER Data
        PowerShell-Objekt das zu JSON konvertiert werden soll
    
    .PARAMETER StatusCode
        HTTP-Statuscode (Standard: 200)
    
    .EXAMPLE
        Send-JsonResponse -Context $context -Data @{status='ok'; count=42}
        
        Sendet: {"status":"ok","count":42}
    
    .EXAMPLE
        $error = @{status='error'; message='Datei nicht gefunden'}
        Send-JsonResponse -Context $context -Data $error -StatusCode 404
        
        Sendet Fehler-JSON mit Status 404
    
    .NOTES
        Verwendet ConvertTo-Json für Serialisierung
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,
        
        [Parameter(Mandatory)]
        [object]$Data,
        
        [Parameter()]
        [int]$StatusCode = 200
    )
    
    try {
        $response = $Context.Response
        $response.StatusCode = $StatusCode
        $response.ContentType = "application/json; charset=utf-8"
        
        $json = $Data | ConvertTo-Json -Depth 10 -Compress
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        
        Write-Verbose "JSON Response gesendet: $StatusCode, $($buffer.Length) Bytes"
    }
    catch {
        Write-Error "Fehler beim Senden der JSON-Response: $_"
        throw
    }
    finally {
        if ($response) {
            $response.Close()
        }
    }
}

# ============================================================================
# FILE STREAM RESPONSE
# ============================================================================

function Send-FileResponse {
    <#
    .SYNOPSIS
        Streamt eine Datei an den Client
    
    .DESCRIPTION
        Streamt Datei-Content mit korrektem MIME-Type.
        Unterstützt automatische MIME-Type-Erkennung basierend auf Dateiendung.
        Optimiert für große Dateien durch Streaming.
    
    .PARAMETER Context
        HttpListenerContext-Objekt vom Request
    
    .PARAMETER FilePath
        Pfad zur zu streamenden Datei
    
    .PARAMETER ContentType
        MIME-Type (optional, wird automatisch erkannt wenn nicht angegeben)
    
    .EXAMPLE
        Send-FileResponse -Context $context -FilePath "C:\Images\photo.jpg"
        
        Streamt JPEG mit automatischem MIME-Type (image/jpeg)
    
    .EXAMPLE
        Send-FileResponse -Context $context -FilePath $file -ContentType "video/mp4"
        
        Streamt Video mit explizitem MIME-Type
    
    .NOTES
        Verwendet 64KB Buffer für effizientes Streaming
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,
        
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -LiteralPath $_ -PathType Leaf})]
        [string]$FilePath,
        
        [Parameter()]
        [string]$ContentType
    )
    
    try {
        # MIME-Type automatisch ermitteln wenn nicht angegeben
        if (-not $ContentType) {
            $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
            $ContentType = switch ($extension) {
                '.jpg'  { 'image/jpeg' }
                '.jpeg' { 'image/jpeg' }
                '.png'  { 'image/png' }
                '.gif'  { 'image/gif' }
                '.webp' { 'image/webp' }
                '.mp4'  { 'video/mp4' }
                '.webm' { 'video/webm' }
                '.css'  { 'text/css' }
                '.js'   { 'application/javascript' }
                '.json' { 'application/json' }
                default { 'application/octet-stream' }
            }
        }
        
        $response = $Context.Response
        $response.StatusCode = 200
        $response.ContentType = $ContentType
        
        $fileInfo = Get-Item -LiteralPath $FilePath
        $response.ContentLength64 = $fileInfo.Length
        
        # Streaming mit 64KB Buffer
        $fileStream = [System.IO.File]::OpenRead($FilePath)
        $buffer = New-Object byte[] 65536
        
        while (($read = $fileStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $response.OutputStream.Write($buffer, 0, $read)
        }
        
        Write-Verbose "Datei gestreamt: $FilePath ($($fileInfo.Length) Bytes)"
    }
    catch {
        Write-Error "Fehler beim Streamen der Datei '$FilePath': $_"
        throw
    }
    finally {
        if ($fileStream) { $fileStream.Close() }
        if ($response) { $response.Close() }
    }
}

# ============================================================================
# REQUEST PARAMETER PARSING
# ============================================================================

function Get-RequestParameters {
    <#
    .SYNOPSIS
        Extrahiert Parameter aus HTTP-Request
    
    .DESCRIPTION
        Parst Query-String-Parameter und POST-Body (JSON oder Form-Data).
        Gibt einheitliche Hashtable zurück unabhängig von Request-Methode.
    
    .PARAMETER Context
        HttpListenerContext-Objekt vom Request
    
    .EXAMPLE
        $params = Get-RequestParameters -Context $context
        $filePath = $params['path']
        
        Extrahiert Parameter aus GET oder POST
    
    .EXAMPLE
        # Bei GET: /api/delete?path=C:\file.jpg
        # Bei POST: {"path":"C:\\file.jpg"}
        # Beide ergeben: @{path='C:\file.jpg'}
    
    .OUTPUTS
        System.Collections.Hashtable
        
        Hashtable mit allen Request-Parametern
    
    .NOTES
        Unterstützt:
        - GET Query-String (?key=value)
        - POST JSON-Body
        - POST Form-Data
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context
    )
    
    $parameters = @{}
    
    try {
        # Query-String-Parameter (GET)
        $query = $Context.Request.Url.Query
        if ($query) {
            $query.TrimStart('?').Split('&') | ForEach-Object {
                $pair = $_.Split('=')
                if ($pair.Length -eq 2) {
                    $key = [System.Web.HttpUtility]::UrlDecode($pair[0])
                    $value = [System.Web.HttpUtility]::UrlDecode($pair[1])
                    $parameters[$key] = $value
                }
            }
        }
        
        # POST-Body-Parameter
        if ($Context.Request.HttpMethod -eq 'POST' -and $Context.Request.HasEntityBody) {
            $reader = New-Object System.IO.StreamReader($Context.Request.InputStream, $Context.Request.ContentEncoding)
            $body = $reader.ReadToEnd()
            $reader.Close()
            
            # JSON-Body
            if ($Context.Request.ContentType -match 'application/json') {
                $jsonData = $body | ConvertFrom-Json
                $jsonData.PSObject.Properties | ForEach-Object {
                    $parameters[$_.Name] = $_.Value
                }
            }
            # Form-Data
            elseif ($Context.Request.ContentType -match 'application/x-www-form-urlencoded') {
                $body.Split('&') | ForEach-Object {
                    $pair = $_.Split('=')
                    if ($pair.Length -eq 2) {
                        $key = [System.Web.HttpUtility]::UrlDecode($pair[0])
                        $value = [System.Web.HttpUtility]::UrlDecode($pair[1])
                        $parameters[$key] = $value
                    }
                }
            }
        }
        
        Write-Verbose "Request-Parameter extrahiert: $($parameters.Count) gefunden"
        return $parameters
    }
    catch {
        Write-Error "Fehler beim Parsen der Request-Parameter: $_"
        throw
    }
}