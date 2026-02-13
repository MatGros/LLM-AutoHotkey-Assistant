; Diagnostic wrapper - captures load errors
#Requires AutoHotkey v2.0

errFile := A_ScriptDir "\diagnostic_result.txt"
try FileDelete(errFile)

try {
    FileAppend("Step 1: Starting diagnostics`n", errFile)
    
    ; Test jsongo
    FileAppend("Step 2: Testing jsongo include...`n", errFile)
    #Include lib\jsongo.v2.ahk
    FileAppend("Step 2: OK`n", errFile)
    
    ; Test Promise
    FileAppend("Step 3: Testing Promise include...`n", errFile)
    #Include lib\Promise.ahk
    FileAppend("Step 3: OK`n", errFile)
    
    ; Test ComVar
    FileAppend("Step 4: Testing ComVar include...`n", errFile)
    #Include lib\ComVar.ahk
    FileAppend("Step 4: OK`n", errFile)
    
    ; Test AutoXYWH
    FileAppend("Step 5: Testing AutoXYWH include...`n", errFile)
    #Include lib\AutoXYWH.ahk
    FileAppend("Step 5: OK`n", errFile)
    
    ; Test SystemThemeAwareToolTip
    FileAppend("Step 6: Testing SystemThemeAwareToolTip include...`n", errFile)
    #Include lib\SystemThemeAwareToolTip.ahk
    FileAppend("Step 6: OK`n", errFile)
    
    ; Test ToolTipEx
    FileAppend("Step 7: Testing ToolTipEx include...`n", errFile)
    #Include lib\ToolTipEx.ahk
    FileAppend("Step 7: OK`n", errFile)
    
    ; Test WebViewToo
    FileAppend("Step 8: Testing WebViewToo include...`n", errFile)
    #Include lib\WebViewToo.ahk
    FileAppend("Step 8: OK`n", errFile)
    
    ; Test Dark_Menu
    FileAppend("Step 9: Testing Dark_Menu include...`n", errFile)
    #Include lib\Dark_Menu.ahk
    FileAppend("Step 9: OK`n", errFile)
    
    ; Test Dark_MsgBox
    FileAppend("Step 10: Testing Dark_MsgBox include...`n", errFile)
    #Include lib\Dark_MsgBox.ahk
    FileAppend("Step 10: OK`n", errFile)
    
    ; Test Prompts
    FileAppend("Step 11: Testing Prompts include...`n", errFile)
    #Include Prompts.ahk
    FileAppend("Step 11: OK`n", errFile)
    
    FileAppend("ALL INCLUDES PASSED`n", errFile)
    
} catch as e {
    FileAppend("ERROR: " e.Message " at line " e.Line "`n", errFile)
}

ExitApp 0