<#
ManifestHint:
  ExportFunctions = @("Show-FolderDialog")
  Description     = "Dialog-Helper für Folder/File-Auswahl mit TopMost-Support"
  Category        = "UI"
  Tags            = @("Dialog","FolderBrowser","FileBrowser","UI","TopMost","Windows.Forms")
  Dependencies    = @("System.Windows.Forms")

Zweck:
  - Wiederverwendbare Dialog-Funktionen
  - FolderBrowserDialog mit TopMost-Support
  - Konsistente Dialog-Handhabung über alle Scripts
  - Dummy-Form für Vordergrund-Darstellung
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Assembly laden
Add-Type -AssemblyName System.Windows.Forms | Out-Null

# ------------------------------------------------------------
# Folder-Dialog anzeigen (mit TopMost-Support)
# ------------------------------------------------------------
function Show-FolderDialog {
  <#
  .SYNOPSIS
  Zeigt einen Ordner-Auswahl-Dialog an
  
  .PARAMETER Description
  Beschreibungstext für den Dialog
  
  .PARAMETER ShowNewFolderButton
  Zeigt den "Neuer Ordner"-Button an
  
  .PARAMETER TopMost
  Dialog wird im Vordergrund angezeigt (über allen Fenstern)
  
  .PARAMETER SelectedPath
  Vorausgewählter Pfad (optional)
  
  .EXAMPLE
  $path = Show-FolderDialog -Description "Root-Ordner wählen" -TopMost $true
  if ($path) { Write-Host "Gewählt: $path" }
  
  .OUTPUTS
  String - Gewählter Pfad oder $null wenn abgebrochen
  #>
  
  param(
    [string]$Description = "Ordner auswählen",
    [bool]$ShowNewFolderButton = $false,
    [bool]$TopMost = $true,
    [string]$SelectedPath = ""
  )

  $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
  $dialog.Description = $Description
  $dialog.ShowNewFolderButton = $ShowNewFolderButton
  
  if (-not [string]::IsNullOrWhiteSpace($SelectedPath)) {
    $dialog.SelectedPath = $SelectedPath
  }

  if ($TopMost) {
    # Dummy-Form als Owner, damit Dialog im Vordergrund erscheint
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true
    $owner.StartPosition = "Manual"
    $owner.Location = New-Object System.Drawing.Point(-9999, -9999)
    $owner.Size = New-Object System.Drawing.Size(1, 1)
    $owner.Show()
    $owner.BringToFront()

    try {
      $result = $dialog.ShowDialog($owner)
    }
    finally {
      $owner.Close()
      $owner.Dispose()
    }
  }
  else {
    $result = $dialog.ShowDialog()
  }

  if ($result -eq [System.Windows.Forms.DialogResult]::OK -and
      -not [string]::IsNullOrWhiteSpace($dialog.SelectedPath)) {
    return $dialog.SelectedPath
  }

  return $null
}

# ------------------------------------------------------------
# File-Dialog anzeigen (für Zukunft)
# ------------------------------------------------------------
function Show-FileDialog {
  <#
  .SYNOPSIS
  Zeigt einen Datei-Auswahl-Dialog an
  
  .PARAMETER Title
  Titel des Dialogs
  
  .PARAMETER Filter
  Dateifilter (z.B. "Bilder|*.jpg;*.png|Alle|*.*")
  
  .PARAMETER TopMost
  Dialog wird im Vordergrund angezeigt
  
  .EXAMPLE
  $file = Show-FileDialog -Title "Bild wählen" -Filter "Bilder|*.jpg;*.png"
  
  .OUTPUTS
  String - Gewählter Dateipfad oder $null wenn abgebrochen
  #>
  
  param(
    [string]$Title = "Datei auswählen",
    [string]$Filter = "Alle Dateien|*.*",
    [bool]$TopMost = $true,
    [string]$InitialDirectory = ""
  )

  $dialog = New-Object System.Windows.Forms.OpenFileDialog
  $dialog.Title = $Title
  $dialog.Filter = $Filter
  
  if (-not [string]::IsNullOrWhiteSpace($InitialDirectory)) {
    $dialog.InitialDirectory = $InitialDirectory
  }

  if ($TopMost) {
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true
    $owner.StartPosition = "Manual"
    $owner.Location = New-Object System.Drawing.Point(-9999, -9999)
    $owner.Size = New-Object System.Drawing.Size(1, 1)
    $owner.Show()
    $owner.BringToFront()

    try {
      $result = $dialog.ShowDialog($owner)
    }
    finally {
      $owner.Close()
      $owner.Dispose()
    }
  }
  else {
    $result = $dialog.ShowDialog()
  }

  if ($result -eq [System.Windows.Forms.DialogResult]::OK -and
      -not [string]::IsNullOrWhiteSpace($dialog.FileName)) {
    return $dialog.FileName
  }

  return $null
}

# ------------------------------------------------------------
# Save-Dialog anzeigen (für Zukunft)
# ------------------------------------------------------------
function Show-SaveDialog {
  <#
  .SYNOPSIS
  Zeigt einen Speichern-Dialog an
  
  .PARAMETER Title
  Titel des Dialogs
  
  .PARAMETER Filter
  Dateifilter
  
  .PARAMETER DefaultFileName
  Standard-Dateiname
  
  .EXAMPLE
  $file = Show-SaveDialog -Title "Export speichern" -Filter "JSON|*.json" -DefaultFileName "export.json"
  
  .OUTPUTS
  String - Gewählter Speicherpfad oder $null wenn abgebrochen
  #>
  
  param(
    [string]$Title = "Speichern unter",
    [string]$Filter = "Alle Dateien|*.*",
    [string]$DefaultFileName = "",
    [bool]$TopMost = $true
  )

  $dialog = New-Object System.Windows.Forms.SaveFileDialog
  $dialog.Title = $Title
  $dialog.Filter = $Filter
  
  if (-not [string]::IsNullOrWhiteSpace($DefaultFileName)) {
    $dialog.FileName = $DefaultFileName
  }

  if ($TopMost) {
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true
    $owner.StartPosition = "Manual"
    $owner.Location = New-Object System.Drawing.Point(-9999, -9999)
    $owner.Size = New-Object System.Drawing.Size(1, 1)
    $owner.Show()
    $owner.BringToFront()

    try {
      $result = $dialog.ShowDialog($owner)
    }
    finally {
      $owner.Close()
      $owner.Dispose()
    }
  }
  else {
    $result = $dialog.ShowDialog()
  }

  if ($result -eq [System.Windows.Forms.DialogResult]::OK -and
      -not [string]::IsNullOrWhiteSpace($dialog.FileName)) {
    return $dialog.FileName
  }

  return $null
}