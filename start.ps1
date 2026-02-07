# start.ps1
# Zweck: Zentrales Startmenü für die Skriptesammlung (bleibt aktiv bis Beenden)

do {
    Clear-Host

    Write-Host "================================="
    Write-Host " PowerShell Skripte Sammlung"
    Write-Host "================================="
    Write-Host ""
    Write-Host "1) Fotos gruppieren (group-photos)"
    Write-Host "2) Preview-Ordner erstellen (create-photo-preview)"
    Write-Host "3) Archive entpacken & bereinigen (Extract-And-CleanupArchives)"
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

            # 3) zuerst entpacken/cleanup mit dem selben Root (ohne 2. Dialog)
            . "$PSScriptRoot\Module\Extract-And-CleanupArchives.ps1" -RootPath $root

            # 2) danach Preview im selben Root (ohne 2. Dialog)
            . "$PSScriptRoot\Module\create-photo-preview.ps1" -RootPath $root

            Read-Host "`nEnter für Rückkehr ins Menü"
        }

        "3" {
            Clear-Host
            . "$PSScriptRoot\Module\Extract-And-CleanupArchives.ps1"
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
