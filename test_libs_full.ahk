#Requires AutoHotkey v2.0
FileAppend "Start test`n", "test_log.txt"
#Include lib\jsongo.v2.ahk
FileAppend "jsongo loaded`n", "test_log.txt"
#Include lib\WebViewToo.ahk
FileAppend "WebViewToo loaded`n", "test_log.txt"
#Include lib\Dark_Menu.ahk
FileAppend "Dark_Menu loaded`n", "test_log.txt"
#Include lib\Dark_MsgBox.ahk
FileAppend "Dark_MsgBox loaded`n", "test_log.txt"
ExitApp