#Requires AutoHotkey v2.0
FileAppend "Start test`n", "*"
#Include lib\jsongo.v2.ahk
FileAppend "jsongo loaded`n", "*"
; #Include lib\WebViewToo.ahk
; FileAppend "WebViewToo loaded`n", "*"
#Include lib\Dark_Menu.ahk
FileAppend "Dark_Menu loaded`n", "*"
#Include lib\Dark_MsgBox.ahk
FileAppend "Dark_MsgBox loaded`n", "*"
ExitApp