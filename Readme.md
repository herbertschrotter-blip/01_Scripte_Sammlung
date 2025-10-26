# 🧩 TOOL_BatchRename.ps1

Interaktives PowerShell-Tool zum sicheren Massen-Umbenennen  
mit JSON-Logging, Restore-Funktion und Analyse.

## Funktionen
- Menü mit 5 Optionen (Dateien, Ordner, Beides, Restore, Analyse)
- Automatische Suffixe (_1, _2, …)
- Kollisionserkennung & eindeutige Namen
- Sitzungs-Logging (max. 10)
- Wiederherstellung einzelner Sitzungen
- Analyse fehlender Nummern

## Nutzung
```powershell
.\TOOL_BatchRename.ps1
