# ============================================================
# TOOL_BatchRename.ps1
# Version: TOOL_V1.4.0
# Zweck:   Hauptmodul für interaktives BatchRename-System
# Autor:   Herbert Schrotter
# Datum:   26.10.2025
# ============================================================

Import-Module "$PSScriptRoot\Libs\Lib_Utils.ps1" -Force
Import-Module "$PSScriptRoot\Libs\Lib_Debug.ps1" -Force
Import-Module "$PSScriptRoot\Modules\MOD_Menu.ps1" -Force
Import-Module "$PSScriptRoot\Modules\MOD_Rename.ps1" -Force
Import-Module "$PSScriptRoot\Modules\MOD_Analyse.ps1" -Force
Import-Module "$PSScriptRoot\Modules\MOD_Restore.ps1" -Force
Import-Module "$PSScriptRoot\Modules\MOD_Logging.ps1" -Force

# Hauptablauf
$mode = Show-Menu
switch ($mode) {
    'Analyse'  { Start-Analyse }
    'Restore'  { Start-Restore }
    default    { Invoke-Rename -Mode $mode }
}
