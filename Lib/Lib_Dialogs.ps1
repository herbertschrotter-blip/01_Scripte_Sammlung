#Requires -Version 5.1

<#
.SYNOPSIS
    Dialog-Helper für Ordner- und Dateiauswahl mit TopMost-Support

.DESCRIPTION
    Bietet wiederverwendbare Dialog-Funktionen für Windows.Forms Dialoge
    mit optionalem TopMost-Support (Anzeige im Vordergrund über allen Fenstern).
    
    Funktionen:
    - Show-FolderDialog: Ordner-Auswahl mit FolderBrowserDialog
    - Show-FileDialog:   Datei-Öffnen mit OpenFileDialog
    - Show-SaveDialog:   Datei-Speichern mit SaveFileDialog
    
    TopMost-Implementierung:
    - Verwendet versteckte Dummy-Form als Owner
    - Zwingt Dialog in den Vordergrund (über PowerShell-Konsole)
    - Automatische Cleanup von Form-Ressourcen

.PARAMETER None
    Library-Datei - Funktionen via dot-sourcing laden

.EXAMPLE
    PS> . .\Lib_Dialogs.ps1
    PS> $path = Show-FolderDialog -Description "Root-Ordner wählen" -TopMost
    PS> if ($path) { Write-Host "Gewählt: $path" }

.EXAMPLE
    PS> . .\Lib_Dialogs.ps1
    PS> $file = Show-FileDialog -Title "Bild wählen" -Filter "Bilder|*.jpg;*.png"

.NOTES
    Autor: Herbert Schrotter
    Version: 1.0.0
    Erstellt: 2025-02-12
    
    Abhängigkeiten:
    - System.Windows.Forms Assembly
    
    TopMost-Workaround:
    - Dummy-Form wird außerhalb des sichtbaren Bereichs erstellt (-9999, -9999)
    - Form wird nach Dialog-Schließen korrekt disposed

.LINK
    https://github.com/herbertschrotter-blip/01_Scripte_Sammlung
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# Assembly laden (nur einmal pro Session)
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null

# ============================================================================
# Show-FolderDialog - Ordner-Auswahl Dialog
# ============================================================================
function Show-FolderDialog {
    <#
    .SYNOPSIS
        Zeigt einen Ordner-Auswahl-Dialog an
    
    .DESCRIPTION
        Zeigt FolderBrowserDialog mit optionalem TopMost-Support an.
        TopMost zwingt den Dialog in den Vordergrund über allen anderen Fenstern.
    
    .PARAMETER Description
        Beschreibungstext für den Dialog (wird über der Ordner-Auswahl angezeigt)
    
    .PARAMETER ShowNewFolderButton
        Zeigt den "Neuer Ordner"-Button im Dialog an
    
    .PARAMETER TopMost
        Dialog wird im Vordergrund angezeigt (über allen Fenstern)
    
    .PARAMETER SelectedPath
        Vorausgewählter Pfad beim Öffnen des Dialogs (optional)
    
    .EXAMPLE
        PS> $path = Show-FolderDialog -Description "Root-Ordner wählen" -TopMost
        PS> if ($path) { Write-Host "Gewählt: $path" }
    
    .EXAMPLE
        PS> $path = Show-FolderDialog -Description "Backup-Ordner" -ShowNewFolderButton -SelectedPath "C:\Backups"
    
    .OUTPUTS
        String - Gewählter Ordner-Pfad, oder $null wenn Abbruch
    
    .NOTES
        Autor: Herbert Schrotter
        Version: 1.0.0
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Description = 'Ordner auswählen',
        
        [Parameter()]
        [switch]$ShowNewFolderButton,
        
        [Parameter()]
        [switch]$TopMost,
        
        [Parameter()]
        [string]$SelectedPath = ''
    )
    
    # FolderBrowserDialog erstellen und konfigurieren
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $ShowNewFolderButton.IsPresent
    
    # Vorausgewählten Pfad setzen (wenn vorhanden)
    if (-not [string]::IsNullOrWhiteSpace($SelectedPath)) {
        $dialog.SelectedPath = $SelectedPath
    }
    
    # TopMost: Dummy-Form als Owner erstellen (versteckt außerhalb Bildschirm)
    if ($TopMost) {
        $owner = New-Object System.Windows.Forms.Form
        $owner.TopMost = $true
        $owner.StartPosition = 'Manual'
        $owner.Location = New-Object System.Drawing.Point(-9999, -9999)
        $owner.Size = New-Object System.Drawing.Size(1, 1)
        $owner.Show()
        $owner.BringToFront()
        
        try {
            $result = $dialog.ShowDialog($owner)
        }
        finally {
            # Cleanup: Form-Ressourcen freigeben
            $owner.Close()
            $owner.Dispose()
        }
    }
    else {
        # Normaler Dialog ohne TopMost
        $result = $dialog.ShowDialog()
    }
    
    # Rückgabe: Gewählter Pfad oder $null bei Abbruch
    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and
        -not [string]::IsNullOrWhiteSpace($dialog.SelectedPath)) {
        return $dialog.SelectedPath
    }
    
    return $null
}

# ============================================================================
# Show-FileDialog - Datei-Öffnen Dialog
# ============================================================================
function Show-FileDialog {
    <#
    .SYNOPSIS
        Zeigt einen Datei-Auswahl-Dialog an (Öffnen)
    
    .DESCRIPTION
        Zeigt OpenFileDialog mit optionalem TopMost-Support an.
        Unterstützt Dateifilter und Initial-Verzeichnis.
    
    .PARAMETER Title
        Titel des Dialogs (Fenstertitel)
    
    .PARAMETER Filter
        Dateifilter im Format "Beschreibung|*.ext1;*.ext2|Beschreibung2|*.ext3"
        Beispiel: "Bilder|*.jpg;*.png|Alle Dateien|*.*"
    
    .PARAMETER TopMost
        Dialog wird im Vordergrund angezeigt (über allen Fenstern)
    
    .PARAMETER InitialDirectory
        Start-Verzeichnis beim Öffnen des Dialogs (optional)
    
    .EXAMPLE
        PS> $file = Show-FileDialog -Title "Bild wählen" -Filter "Bilder|*.jpg;*.png"
        PS> if ($file) { Write-Host "Gewählt: $file" }
    
    .EXAMPLE
        PS> $csv = Show-FileDialog -Title "CSV Import" -Filter "CSV|*.csv|Alle|*.*" -InitialDirectory "C:\Data"
    
    .OUTPUTS
        String - Gewählter Dateipfad, oder $null wenn Abbruch
    
    .NOTES
        Autor: Herbert Schrotter
        Version: 1.0.0
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Title = 'Datei auswählen',
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Filter = 'Alle Dateien|*.*',
        
        [Parameter()]
        [switch]$TopMost,
        
        [Parameter()]
        [string]$InitialDirectory = ''
    )
    
    # OpenFileDialog erstellen und konfigurieren
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = $Title
    $dialog.Filter = $Filter
    
    # Initial-Verzeichnis setzen (wenn vorhanden)
    if (-not [string]::IsNullOrWhiteSpace($InitialDirectory)) {
        $dialog.InitialDirectory = $InitialDirectory
    }
    
    # TopMost: Dummy-Form als Owner erstellen (versteckt außerhalb Bildschirm)
    if ($TopMost) {
        $owner = New-Object System.Windows.Forms.Form
        $owner.TopMost = $true
        $owner.StartPosition = 'Manual'
        $owner.Location = New-Object System.Drawing.Point(-9999, -9999)
        $owner.Size = New-Object System.Drawing.Size(1, 1)
        $owner.Show()
        $owner.BringToFront()
        
        try {
            $result = $dialog.ShowDialog($owner)
        }
        finally {
            # Cleanup: Form-Ressourcen freigeben
            $owner.Close()
            $owner.Dispose()
        }
    }
    else {
        # Normaler Dialog ohne TopMost
        $result = $dialog.ShowDialog()
    }
    
    # Rückgabe: Gewählter Dateipfad oder $null bei Abbruch
    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and
        -not [string]::IsNullOrWhiteSpace($dialog.FileName)) {
        return $dialog.FileName
    }
    
    return $null
}

# ============================================================================
# Show-SaveDialog - Datei-Speichern Dialog
# ============================================================================
function Show-SaveDialog {
    <#
    .SYNOPSIS
        Zeigt einen Speichern-Dialog an (Datei speichern)
    
    .DESCRIPTION
        Zeigt SaveFileDialog mit optionalem TopMost-Support an.
        Unterstützt Dateifilter und Standard-Dateinamen.
    
    .PARAMETER Title
        Titel des Dialogs (Fenstertitel)
    
    .PARAMETER Filter
        Dateifilter im Format "Beschreibung|*.ext|Beschreibung2|*.ext2"
        Beispiel: "JSON Dateien|*.json|Alle Dateien|*.*"
    
    .PARAMETER DefaultFileName
        Standard-Dateiname (wird im Eingabefeld vorausgefüllt)
    
    .PARAMETER TopMost
        Dialog wird im Vordergrund angezeigt (über allen Fenstern)
    
    .EXAMPLE
        PS> $file = Show-SaveDialog -Title "Export speichern" -Filter "JSON|*.json" -DefaultFileName "export.json"
        PS> if ($file) { Export-Data | ConvertTo-Json | Out-File $file }
    
    .EXAMPLE
        PS> $log = Show-SaveDialog -Title "Log speichern" -Filter "Logs|*.log|Text|*.txt"
    
    .OUTPUTS
        String - Gewählter Speicherpfad, oder $null wenn Abbruch
    
    .NOTES
        Autor: Herbert Schrotter
        Version: 1.0.0
    #>
    
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Title = 'Speichern unter',
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Filter = 'Alle Dateien|*.*',
        
        [Parameter()]
        [string]$DefaultFileName = '',
        
        [Parameter()]
        [switch]$TopMost
    )
    
    # SaveFileDialog erstellen und konfigurieren
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Title = $Title
    $dialog.Filter = $Filter
    
    # Standard-Dateiname setzen (wenn vorhanden)
    if (-not [string]::IsNullOrWhiteSpace($DefaultFileName)) {
        $dialog.FileName = $DefaultFileName
    }
    
    # TopMost: Dummy-Form als Owner erstellen (versteckt außerhalb Bildschirm)
    if ($TopMost) {
        $owner = New-Object System.Windows.Forms.Form
        $owner.TopMost = $true
        $owner.StartPosition = 'Manual'
        $owner.Location = New-Object System.Drawing.Point(-9999, -9999)
        $owner.Size = New-Object System.Drawing.Size(1, 1)
        $owner.Show()
        $owner.BringToFront()
        
        try {
            $result = $dialog.ShowDialog($owner)
        }
        finally {
            # Cleanup: Form-Ressourcen freigeben
            $owner.Close()
            $owner.Dispose()
        }
    }
    else {
        # Normaler Dialog ohne TopMost
        $result = $dialog.ShowDialog()
    }
    
    # Rückgabe: Gewählter Speicherpfad oder $null bei Abbruch
    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and
        -not [string]::IsNullOrWhiteSpace($dialog.FileName)) {
        return $dialog.FileName
    }
    
    return $null
}