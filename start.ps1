# start.ps1
# Zweck: Zentrales Startmenü für die Skriptesammlung (bleibt aktiv bis Beenden)

do {
    Clear-Host

    Write-Host "================================="
    Write-Host " PowerShell Skripte Sammlung"
    Write-Host "================================="
    Write-Host ""
    Write-Host "1) Fotos gruppieren (group-photos)"
    Write-Host "2) Cleanup + Foto- & Video-Previews (Gesamtlauf)"
    Write-Host "3) Archive entpacken & bereinigen (Extract-And-CleanupArchives)"
    Write-Host "4) Video-Previews erstellen (create-video-preview)"
    Write-Host "5) Fotos aus mehreren Ordnern verschieben (move-photos-multifolder)"
    Write-Host "6) Foto-Ordner prüfen & löschen (HTML-Übersicht)"
    Write-Host "0) Beenden"
    Write-Host ""

    $choice = Read-Host "Auswahl"

    switch ($choice) {

        "1" {
            Clear-Host

            # group-photos gibt bei Erfolg den Root-Pfad zurück
            $lastRoot = . "$PSScriptRoot\Module\group-photos.ps1"

            if ($lastRoot) {
                $ans = Read-Host "`nPreview-Ordner im selben Root erstellen? (J/N)"
                if ($ans -eq "J") {
                    Clear-Host
                    . "$PSScriptRoot\Module\create-photo-preview.ps1" -RootPath $lastRoot
                }
            }

            Read-Host "`nEnter für Rückkehr ins Menü"
        }

        "2" {
            Clear-Host

            Add-Type -AssemblyName System.Windows.Forms | Out-Null
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = "Root-Ordner auswählen"

            if ($dlg.ShowDialog() -ne "OK") {
                Write-Host "Abgebrochen."
                Read-Host "`nEnter für Rückkehr ins Menü"
                break
            }

            $root = $dlg.SelectedPath

            Write-Host "`n[1/3] Archive entpacken & bereinigen..."
            . "$PSScriptRoot\Module\Extract-And-CleanupArchives.ps1" -RootPath $root

            Write-Host "`n[2/3] Foto-Previews erstellen..."
            . "$PSScriptRoot\Module\create-photo-preview.ps1" -RootPath $root

            Write-Host "`n[3/3] Video-Previews erstellen..."
            . "$PSScriptRoot\Module\create-video-preview.ps1" -RootPath $root

            Write-Host "`nGesamtlauf abgeschlossen."
            Read-Host "`nEnter für Rückkehr ins Menü"
        }

        "3" {
            Clear-Host
            . "$PSScriptRoot\Module\Extract-And-CleanupArchives.ps1"
            Read-Host "`nEnter für Rückkehr ins Menü"
        }

        "4" {
            Clear-Host
            . "$PSScriptRoot\Module\create-video-preview.ps1"
            Read-Host "`nEnter für Rückkehr ins Menü"
        }

        "5" {
            Clear-Host
            . "$PSScriptRoot\Module\move-photos-multifolder.ps1"
            Read-Host "`nEnter für Rückkehr ins Menü"
        }

        "6" {
            Clear-Host

            # HTML-Tool: Ordnerauswahl erfolgt im Script selbst
            . "$PSScriptRoot\Module\PhotoFolder-ReviewAndDelete.ps1"

            Read-Host "`nEnter für Rückkehr ins Menü"
        }

        "0" {
            Write-Host "Beendet."
        }

        default {
            Write-Host "Ungültige Auswahl."
            Start-Sleep -Seconds 1
        }
    }

} while ($choice -ne "0")
