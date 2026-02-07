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
            . "$PSScriptRoot\Module\create-photo-preview.ps1"
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
