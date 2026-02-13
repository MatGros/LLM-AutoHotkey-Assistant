#Requires AutoHotkey v2.0
try {
    #Include lib\Config.ahk
    FileAppend "Config Loaded Successfully`n", "*"
} catch as e {
    FileAppend "Error loading Config: " e.Message "`n", "*"
    ExitApp 1
}
ExitApp 0