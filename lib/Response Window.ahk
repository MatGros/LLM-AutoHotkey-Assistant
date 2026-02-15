#Include Config.ahk
#SingleInstance Off
#NoTrayIcon

; ----------------------------------------------------
; Hotkeys
; ----------------------------------------------------

~Esc:: subScriptHotkeyActions("Esc")
~^w:: subScriptHotkeyActions("closeWindows")

subScriptHotkeyActions(action) {
    switch action {

        ; Handles request cancellation based on Response Window state:
        ;
        ; Background window: Stop request, keep window open
        ; Active window: Stop request, keep window open
        ; Hidden window: Stop request only
        case "Esc":
            switch {
                case WinExist(responseWindow.hWnd) && !(WinActive(responseWindow.hWnd))
                && ProcessExist(manageState("cURL", "get")):
                    manageState("cURL", "close")
                    postWebMessage("responseWindowButtonsEnabled", true)

                case WinActive(responseWindow.hWnd):
                    switch {
                        case ProcessExist(manageState("cURL", "get")):
                            manageState("cURL", "close")
                            postWebMessage("responseWindowButtonsEnabled", true)

                        Default:
                            buttonClickAction("Close")
                    }

                case ProcessExist(manageState("cURL", "get")):
                    manageState("cURL", "close")
            }

        case "closeWindows":
            switch WinActive("A") {
                case responseWindow.hWnd: buttonClickAction("Close")
                case chatInputWindow.guiObj.hWnd: chatInputWindow.closeButtonAction()
            }
    }
}

; ----------------------------------------------------
; Read data from main script and start loading cursor
; ----------------------------------------------------

requestParams := jsongo.Parse(FileOpen(A_Args[1], "r", "UTF-8").Read())

; ----------------------------------------------------
; Debug logging system
; ----------------------------------------------------

DebugLog(msg) {
    global requestParams
    logFile := A_Temp "\ResponseWindow_Debug_" requestParams["uniqueID"] ".log"
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    logLine := "[" timestamp "] " msg "`n"
    try {
        FileAppend(logLine, logFile, "UTF-8")
    } catch {
        ; Ignore write errors
    }
}

; Create log file and show path
logFilePath := A_Temp "\\ResponseWindow_Debug_" requestParams["uniqueID"] ".log"
try {
    FileDelete(logFilePath)  ; Clear previous log
} catch {
}

DebugLog("=== Response Window Started ===")
DebugLog("UniqueID: " requestParams["uniqueID"])
DebugLog("Model: " requestParams["singleAPIModelName"])
DebugLog("cURL Output File: " requestParams["cURLOutputFile"])
DebugLog("Log file: " logFilePath)

; Log location is available in log file if needed, removed tooltip as requested
; ToolTip("Debug log: " logFilePath "`n`nThis will auto-close in 5 seconds", , , 20)
; SetTimer(() => ToolTip(), -5000)

startLoadingCursor(true)

; ----------------------------------------------------
; Change icon based on providerName
; ----------------------------------------------------

; TraySetIcon(FileExist(icon := "..\icons\" requestParams["providerName"] ".ico") ? icon : "..\icons\IconOn.ico")

; ----------------------------------------------------
; Create new instance of OllamaBackend class
; ----------------------------------------------------

router := OllamaBackend(requestParams["baseURL"], requestParams.Has("APIKey") ? requestParams["APIKey"] : "")

; ----------------------------------------------------
; Create Response Window
; ----------------------------------------------------

; Create the Webview Window
responseWindow := WebViewToo(, , ,)
responseWindow.OnEvent("Close", (*) => buttonClickAction("Close"))
responseWindow.Load("..\Response Window resources\index.html")

; Apply "Always On Top" style
WinSetAlwaysOnTop(true, responseWindow.hWnd)

; Apply dark mode to title bar
; Reference: https://www.autohotkey.com/boards/viewtopic.php?p=422034#p422034
DllCall("Dwmapi\DwmSetWindowAttribute", "ptr", responseWindow.hWnd, "int", 20, "int*", true, "int", 4)

; Add event listener for messages from JavaScript
responseWindow.AddHostObjectToScript("ahkHandler", { func: ahkMessageHandler })
ahkMessageHandler(message) {
    try {
        msgObj := jsongo.Parse(message)
        if (msgObj.Has("action") && msgObj["action"] = "removeTransparency") {
            ; Remove transparency when streaming is complete
            WinSetTransparent("Off", responseWindow.hWnd)
        }
        if (msgObj.Has("action") && msgObj["action"] = "resize") {
            ; Auto-resize window to fit content
            newW := msgObj.Has("width") ? Integer(msgObj["width"]) : 0
            newH := msgObj.Has("height") ? Integer(msgObj["height"]) : 0
            if (newW > 0 && newH > 0) {
                responseWindow.hWnd
                WinGetPos(&curX, &curY, &curW, &curH, responseWindow.hWnd)
                ; Only grow, don't shrink below current size for width
                finalW := Max(curW, newW)
                finalH := newH
                ; Keep window on screen
                if (curX + finalW > A_ScreenWidth)
                    curX := Max(0, A_ScreenWidth - finalW)
                if (curY + finalH > A_ScreenHeight)
                    curY := Max(0, A_ScreenHeight - finalH)
                WinMove(curX, curY, finalW, finalH, responseWindow.hWnd)
            }
        }
    } catch {
        ; Ignore invalid messages
    }
}

; Assign actions to click events
responseWindow.AddHostObjectToScript("ButtonClick", { func: buttonClickAction })
buttonClickAction(action) {
    static chatHistoryButtonText := "Chat History"

    switch action {
        case "Chat": chatInputWindow.showInputWindow()
        case "Copy":
            if requestParams["copyAsMarkdown"] {
                chatState := manageState("chat", "get")
                A_Clipboard := (chatHistoryButtonText = "Chat History") ? chatState.latestResponse : chatState.chatHistory
            }

            postWebMessage("responseWindowCopyButtonAction", requestParams["copyAsMarkdown"])

        case "Retry":
            manageState("model", "remove")
            postWebMessage("responseWindowButtonsEnabled", false)
            startLoadingCursor(true)
            ; Show window with transparency for retry streaming
            WinSetTransparent(217, responseWindow.hWnd)
            postWebMessage("streamStart", requestParams["responseWindowTitle"])
            chatHistoryJSONRequest := manageChatHistoryJSON("get")
            router.removeLastAssistantMessage(&chatHistoryJSONRequest)
            FileOpen(requestParams["chatHistoryJSONRequestFile"], "w", "UTF-8-RAW").Write(chatHistoryJSONRequest)
            manageChatHistoryJSON("set", chatHistoryJSONRequest)
            sendRequestToLLM(&chatHistoryJSONRequest)

        case "Chat History", "Latest Response":
            content := manageState("chat", "get")
            data := [(action = "Chat History") ? content.chatHistory : content.latestResponse]
            postWebMessage("renderMarkdown", data)
            chatHistoryButtonText := (chatHistoryButtonText = "Chat History" ? "Latest Response" : "Chat History")

        case "resetChatHistoryButtonText": chatHistoryButtonText := "Chat History"
        case "Close":
            ; Close immediately without confirmation
            if (ProcessExist(manageState("cURL", "get"))) {
                manageState("cURL", "close")

                ; Sometimes the cURLOutputFile is still being accessed
                ; Sleep here to make sure the file is not opened anymore
                Sleep 100
            }

            deleteTempFiles()
            startLoadingCursor(false)
            postWebMessage("toggleButtonText", [true])

            ; Sends a PostMessage to main script saying the
            ; Response Window has been closed, then terminates
            ; the Response Window script afterwards
            CustomMessages.notifyResponseWindowState(CustomMessages.WM_RESPONSE_WINDOW_CLOSED,
                requestParams["uniqueID"],
                responseWindow.hWnd,
                requestParams["mainScriptHiddenhWnd"])
            ExitApp
    }
}

showResponseWindow(responseWindowTextContent, initialRequest, noActivate := false) {
    postWebMessage("renderMarkdown", [responseWindowTextContent, true])
    buttonClickAction("resetChatHistoryButtonText")
    if initialRequest {

        ; Response Window's width and height
        desiredW := 600
        desiredH := 600

        ; Calculate screen center
        screenW := A_ScreenWidth
        screenH := A_ScreenHeight

        ; Define an X and Y coordinate variables
        X := (screenW - desiredW) // 2
        Y := (screenH - desiredH) // 4

        ; Compute the arrangement of Response Windows based on the number of models:
        ; If there is one Response Window, it will be in the center
        ; If there are two, they will be side by side in the center
        ; If there are three, they will be arranged in the center
        ; If there are more than three, it will be the same as three for the first three,
        ; then additional windows will be in the center as a stack and have a slight downward offset
        switch requestParams["numberOfAPIModels"] {
            case 1:
                pos := Format("x{} y{} w{} h{}", X - 100, Y, desiredW, desiredH)

            case 2:
                X := (requestParams["APIModelsIndex"] = 1) ? (screenW // 2) - (desiredW * 1.3) : (screenW // 2)
                pos := Format("x{} y{} w{} h{}", X, Y, desiredW, desiredH)

            case 3:
                switch requestParams["APIModelsIndex"] {
                    case 1:
                        ; Left
                        X := (screenW // 2) - (desiredW * 1.6)

                    case 2:
                        ; Center
                        X := (screenW - desiredW) // 2

                    default:
                        ; Right
                        X := (screenW // 2) + (desiredW * 0.4)
                }

                pos := Format("x{} y{} w{} h{}", X, Y, desiredW, desiredH)

            default:
                if (requestParams["APIModelsIndex"] < 4) {
                    switch requestParams["APIModelsIndex"] {
                        case 1: X := (screenW // 2) - (desiredW * 1.6)
                        case 2: X := (screenW - desiredW) // 2
                        case 3: X := (screenW // 2) + (desiredW * 0.4)
                    }
                } else {
                    X := (screenW - desiredW) // 2
                    Y := Y + (requestParams["APIModelsIndex"] - 3) * 30
                }

                pos := Format("x{} y{} w{} h{}", X, Y, desiredW, desiredH)
        }

        responseWindow.Show(pos, requestParams["responseWindowTitle"])
    }

    ; Flash the Response Window if it is minimized or not active
    (WinGetMinMax(responseWindow.hWnd) = -1) || noActivate ? responseWindow.Flash() : ""
}

; ----------------------------------------------------
; Create Chat Input Window
; ----------------------------------------------------

chatInputWindow := InputWindow("Envoyer un message à " requestParams["responseWindowTitle"], requestParams[
    "skipConfirmation"])
chatInputWindow.sendButtonAction(chatSendButtonAction)

chatSendButtonAction(*) {
    if !chatInputWindow.validateInputAndHide() {
        return
    }

    startLoadingCursor(true)
    postWebMessage("responseWindowButtonsEnabled", false)
    ; Set transparency for streaming chat response
    WinSetTransparent(217, responseWindow.hWnd)
    postWebMessage("streamStart", requestParams["responseWindowTitle"])
    chatHistoryJSONRequest := manageChatHistoryJSON("get")
    router.appendToChatHistory("user", chatInputWindow.EditControl.Value, &
        chatHistoryJSONRequest, requestParams["chatHistoryJSONRequestFile"])
    manageChatHistoryJSON("set", chatHistoryJSONRequest)
    sendRequestToLLM(&chatHistoryJSONRequest)
}

; ----------------------------------------------------
; Custom messages for detecting Response Windows
; and their open/close state, as well as detecting
; the "Send message to all models" feature
; ----------------------------------------------------

CustomMessages.registerHandlers("subScript", responseWindowSendToAllModels)
CustomMessages.notifyResponseWindowState(CustomMessages.WM_RESPONSE_WINDOW_OPENED, requestParams["uniqueID"],
    responseWindow.hWnd, requestParams["mainScriptHiddenhWnd"])

responseWindowSendToAllModels(uniqueID, lParam, msg, responseWindowhWnd) {
    if (ProcessExist(manageState("cURL", "get"))) {
        manageState("cURL", "close")
    }

    ; Re-read the updated JSON file and call sendRequestToLLM() again
    chatHistoryJSONRequest := FileOpen(requestParams["chatHistoryJSONRequestFile"], "r", "UTF-8-RAW").Read()
    startLoadingCursor(true)
    manageChatHistoryJSON("set", chatHistoryJSONRequest)
    postWebMessage("responseWindowButtonsEnabled", false)
    ; Set transparency for streaming
    WinSetTransparent(217, responseWindow.hWnd)
    postWebMessage("streamStart", requestParams["responseWindowTitle"])
    sendRequestToLLM(&chatHistoryJSONRequest)
}

; ----------------------------------------------------
; Run cURL command and process response
; ----------------------------------------------------

chatHistoryJSONRequest := manageChatHistoryJSON("get")

; Show the window immediately with loading message before sending request
showInitialWindow()

sendRequestToLLM(&chatHistoryJSONRequest, true)

sendRequestToLLM(&chatHistoryJSONRequest, initialRequest := false) {

    ; Run the cURL command asynchronously and store the PID
    cURLCommand := FileOpen(requestParams["cURLCommandFile"], "r", "UTF-8").Read()
    DebugLog("Starting cURL command")
    DebugLog("Command: " cURLCommand)
    Run(cURLCommand, , "Hide", &cURLPID)
    manageState("cURL", "set", cURLPID)
    DebugLog("cURL PID: " cURLPID)

    ; Initialize streaming state
    streamedContent := ""
    lastFilePosition := 0
    isFirstChunk := true
    loopCount := 0
    
    ; Initial message
    if initialRequest {
        DebugLog("Sending streamStart message to frontend")
        postWebMessage("streamStart", requestParams["responseWindowTitle"])
    }

    ; Stream processing loop - read file progressively
    DebugLog("Entering streaming loop")
    while (ProcessExist(cURLPID)) {
        loopCount++
        
        ; Try to read new content from the output file
        if FileExist(requestParams["cURLOutputFile"]) {
            if (loopCount = 1)
                DebugLog("Output file detected")
            
            try {
                file := FileOpen(requestParams["cURLOutputFile"], "r", "UTF-8")
                file.Seek(lastFilePosition)
                newContent := file.Read()
                currentPos := file.Pos
                file.Close()
                
                if (newContent != "") {
                    bytesRead := currentPos - lastFilePosition
                    DebugLog("Read " bytesRead " bytes from position " lastFilePosition)
                    lastFilePosition := currentPos
                    
                    ; Process each line (JSON chunk) from the stream
                    lines := StrSplit(newContent, "`n", "`r")
                    DebugLog("Processing " lines.Length " lines")
                    
                    for index, line in lines {
                        trimmedLine := Trim(line)
                        if (trimmedLine = "")
                            continue
                        
                        DebugLog("Line " index ": " SubStr(trimmedLine, 1, 100) (StrLen(trimmedLine) > 100 ? "..." : ""))
                        
                        try {
                            chunk := jsongo.Parse(trimmedLine)
                            chunkType := Type(chunk)
                            DebugLog("  Parsed chunk type: " chunkType)
                            
                            ; Verify chunk is an object, not a string
                            if (chunkType != "Object" && chunkType != "Map") {
                                DebugLog("  WARNING: Chunk is not an object! Type=" chunkType " Value=" String(chunk))
                                continue
                            }
                            
                            ; Log chunk structure
                            if (chunk.Has("message"))
                                DebugLog("  Has 'message' key, type: " Type(chunk["message"]))
                            if (chunk.Has("done"))
                                DebugLog("  Has 'done' key: " chunk["done"])
                            
                            ; Extract content from the chunk
                            if (chunk.Has("message")) {
                                msgObj := chunk["message"]
                                msgType := Type(msgObj)
                                
                                if (msgType != "Object" && msgType != "Map") {
                                    DebugLog("  WARNING: message is not an object! Type=" msgType)
                                    continue
                                }
                                
                                if (msgObj.Has("content")) {
                                    chunkContent := msgObj["content"]
                                    contentLen := StrLen(chunkContent)
                                    DebugLog("  Content length: " contentLen " chars")
                                    streamedContent .= chunkContent
                                    
                                    ; Send chunk to frontend for real-time display
                                    postWebMessage("streamChunk", chunkContent)
                                }
                            }
                            
                            ; Check if stream is done
                            if (chunk.Has("done") && chunk["done"]) {
                                DebugLog("Stream marked as done")
                                ; Store the model name
                                if (chunk.Has("model")) {
                                    modelName := chunk["model"]
                                    DebugLog("  Model name: " modelName)
                                    modelName := StrReplace(SubStr(modelName, InStr(modelName, "/") + 1), ":", "-")
                                    manageState("model", "add", modelName)
                                }
                            }
                        } catch as e {
                            ; Log JSON parsing errors
                            DebugLog("  JSON Parse Error: " e.Message " at line " e.Line)
                            DebugLog("  Raw line: " trimmedLine)
                            continue
                        }
                    }
                }
            } catch as e {
                ; File might still be locked, continue
                DebugLog("File read error: " e.Message)
            }
        } else if (loopCount = 1) {
            DebugLog("Waiting for output file to be created...")
        }
        
        Sleep 50  ; Poll every 50ms for smooth streaming
    }
    
    DebugLog("Stream loop ended. Total loops: " loopCount)
    DebugLog("Total content length: " StrLen(streamedContent) " chars")

    ; If user cancels the process, exit
    if !manageState("cURL", "get") {
        DebugLog("User cancelled the request")
        manageState("cURL", "close")
        startLoadingCursor(false)
        postWebMessage("streamEnd", false)
        if initialRequest {
            deleteTempFiles()

            ; Sends a message to main script saying the Response Window has been closed,
            ; then terminates the Response Window script
            CustomMessages.notifyResponseWindowState(CustomMessages.WM_RESPONSE_WINDOW_CLOSED,
                requestParams["uniqueID"], responseWindow.hWnd, requestParams["mainScriptHiddenhWnd"])
            ExitApp
        }
        Exit
    }

    ; Read the output after the process has completed
    if !FileExist(requestParams["cURLOutputFile"]) {
        DebugLog("ERROR: Output file not found after cURL completion")

        ; Read the cURL command for diagnostics
        curlCmd := ""
        try {
            file := FileOpen(requestParams["cURLCommandFile"], "r")
            curlCmd := file.Read()
            file.Close()
        } catch {
            curlCmd := ""
        }

        responseFromLLM := "**⛔ Error: Output file not found.**`n`nThe API request might have failed to create the response file. Check your Ollama server status or network connection.`n`n"
        if (curlCmd != "")
            responseFromLLM .= "cURL command (copied to clipboard):`n" curlCmd "`n`n"

        responseFromLLM .= "Debug log: " A_Temp "\ResponseWindow_Debug_" requestParams["uniqueID"] ".log"

        ; Copy cURL command to clipboard for manual debugging
        if (curlCmd != "")
            A_Clipboard := curlCmd

        ; Additional diagnostic: run the same cURL command synchronously and capture stderr/stdout to debug files
        try {
            errFile := A_Temp "\cURLDebugErr_" requestParams["uniqueID"] ".txt"
            outFile := A_Temp "\cURLDebugOut_" requestParams["uniqueID"] ".txt"

            ; Build a cmd string that executes the cURL command and redirects stderr/stdout
            ; Use Format() to safely assemble the command and quote the redirect targets
            diagCmd := Format('cmd /c {1} 1> "{2}" 2> "{3}"', curlCmd, outFile, errFile)
            DebugLog("Running diagnostic: " diagCmd)

            RunWait(diagCmd)

            errText := ""
            outText := ""
            try {
                fErr := FileOpen(errFile, "r")
                errText := fErr.Read()
                fErr.Close()
            } catch {
                errText := ""
            }
            try {
                fOut := FileOpen(outFile, "r")
                outText := fOut.Read()
                fOut.Close()
            } catch {
                outText := ""
            }

            DebugLog("cURL diag - exit stderr length: " StrLen(errText) ", stdout length: " StrLen(outText))

            if (StrLen(errText) > 0) {
                responseFromLLM .= "`n`ncURL stderr (truncated):`n" SubStr(errText, 1, 2000)
            }
            if (StrLen(outText) > 0) {
                responseFromLLM .= "`n`ncURL stdout (truncated):`n" SubStr(outText, 1, 2000)
            }
        } catch as e {
            DebugLog("Diagnostic cURL run failed: " (HasProp(e, "Message") ? e.Message : e))
        }

        manageState("cURL", "close")
        startLoadingCursor(false)
        CustomMessages.notifyResponseWindowState(CustomMessages.WM_RESPONSE_WINDOW_CLOSED,
            requestParams["uniqueID"], responseWindow.hWnd, requestParams["mainScriptHiddenhWnd"])

        MsgBox(responseFromLLM, "API Error", 16)
        ExitApp
    }

    ; Finalize the stream
    DebugLog("Finalizing stream")

    ; If streamedContent is empty, attempt to read and extract the final JSON from the cURL output file
    if (StrLen(streamedContent) = 0) {
        DebugLog("streamedContent is empty — attempting to read cURL output file for fallback extraction")
        rawOut := ""
        try {
            f := FileOpen(requestParams["cURLOutputFile"], "r", "UTF-8-RAW")
            rawOut := f.Read()
            f.Close()
        } catch {
            rawOut := ""
        }

        DebugLog("cURL output file length: " StrLen(rawOut) " chars")

        if (StrLen(rawOut) > 0) {
            ; Try to parse JSON and extract response using the same helper as main script
            try {
                parsed := jsongo.Parse(rawOut)
                respObj := router.extractJSONResponse(parsed)
                if (respObj && respObj.response && Trim(respObj.response) != "") {
                    DebugLog("Extracted response from final JSON (fallback)")
                    streamedContent := respObj.response
                } else {
                    DebugLog("Could not extract 'message.content' from final JSON output — showing raw output in debug popup")
                    ; Show the raw output to help debugging
                    MsgBox("Debug: cURL produced output but no streamable chunks were found.\n\nRaw output (truncated):\n" SubStr(rawOut, 1, 4000), "Raw cURL output", 48)
                }
            } catch as e {
                DebugLog("JSON parse error on final output: " (HasProp(e, "Message") ? e.Message : e))
                MsgBox("Debug: Unable to parse cURL output as JSON: " (HasProp(e, "Message") ? e.Message : e) "\n\nRaw output (truncated):\n" SubStr(rawOut, 1, 4000), "Parse error", 16)
            }
        } else {
            DebugLog("cURL output file is empty despite process completion")
            MsgBox("Debug: cURL output file exists but is empty:\n" requestParams["cURLOutputFile"], "Empty output", 48)
        }
    }

    responseFromLLM := streamedContent  ; Set the full response for final processing
    postWebMessage("streamEnd", true)

    ; If we have a final response but no stream chunks were sent to the frontend,
    ; explicitly render the final content so the UI doesn't remain showing only the streaming indicator.
    if (StrLen(responseFromLLM) > 0) {
        postWebMessage("renderMarkdown", [responseFromLLM, true])
    }

    ; Process the final response
    try {
        DebugLog("Final response length: " StrLen(responseFromLLM) " chars")
        
        ; Get model info from state
        modelHistory := manageState("model", "get")
        currentModel := (modelHistory.Length > 0) ? modelHistory[modelHistory.Length] : "unknown"
        DebugLog("Current model: " currentModel)
        
        ; Append to chat history
        router.appendToChatHistory("assistant",
            responseFromLLM, &chatHistoryJSONRequest, requestParams["chatHistoryJSONRequestFile"])
        DebugLog("Appended to chat history")
    } catch as e {
        DebugLog("ERROR processing final response: " e.Message " at line " e.Line)
        responseFromLLM := "**⛔ Error parsing response**`n`n" e.Message
        postWebMessage("renderMarkdown", [responseFromLLM, true])
        postWebMessage("responseWindowButtonsEnabled", true)
        startLoadingCursor(false)
        Exit
    }

    ; Handle auto-paste or finalize UI
    DebugLog("Handling final state")
    if requestParams["isAutoPaste"] {
        A_Clipboard := responseFromLLM
        Send("^v")
        startLoadingCursor(false)
        CustomMessages.notifyResponseWindowState(CustomMessages.WM_RESPONSE_WINDOW_CLOSED, requestParams["uniqueID"],
            responseWindow.hWnd, requestParams["mainScriptHiddenhWnd"])
        deleteTempFiles()
        ExitApp
    } else {
        ; Finalize button states
        buttonClickAction("resetChatHistoryButtonText")
        postWebMessage("responseWindowButtonsEnabled", true)
        startLoadingCursor(false)
    }
}

; ----------------------------------------------------
; Show initial window immediately
; ----------------------------------------------------

showInitialWindow() {
    ; Response Window's initial width and height (smaller, will grow with content)
    desiredW := 450
    desiredH := 300

    ; Get mouse position to show window near cursor/menu
    MouseGetPos(&mouseX, &mouseY)
    
    ; Calculate screen dimensions
    screenW := A_ScreenWidth
    screenH := A_ScreenHeight

    ; Position near mouse cursor, but ensure it stays on screen
    X := mouseX + 20  ; Offset from cursor
    Y := mouseY - 50
    
    ; Ensure window stays within screen bounds
    if (X + desiredW > screenW)
        X := screenW - desiredW - 20
    if (Y + desiredH > screenH)
        Y := screenH - desiredH - 20
    if (X < 0)
        X := 20
    if (Y < 0)
        Y := 20

    ; Adjust position for multiple models (cascade them slightly)
    if (requestParams["numberOfAPIModels"] > 1) {
        offsetX := (requestParams["APIModelsIndex"] - 1) * 30
        offsetY := (requestParams["APIModelsIndex"] - 1) * 30
        X := X + offsetX
        Y := Y + offsetY
        
        ; Re-check bounds after offset
        if (X + desiredW > screenW)
            X := screenW - desiredW - 20
        if (Y + desiredH > screenH)
            Y := screenH - desiredH - 20
    }
    
    pos := Format("x{} y{} w{} h{}", X, Y, desiredW, desiredH)

    ; Show the window immediately with semi-transparency (85% opacity = 217)
    responseWindow.Show(pos, requestParams["responseWindowTitle"])
    WinSetTransparent(217, responseWindow.hWnd)
}

; ----------------------------------------------------
; Manage Chat History requests
; ----------------------------------------------------

manageChatHistoryJSON(action, data := unset) {
    static JSONRequest := FileOpen(requestParams["chatHistoryJSONRequestFile"], "r", "UTF-8-RAW").Read()

    switch action {
        case "get": return JSONRequest
        case "set": JSONRequest := data
    }
}

;--------------------------------------------------
; Combined state management for model history,
; chat history, and cURL process
;--------------------------------------------------

manageState(component, action, data := {}) {
    static state := {
        modelHistory: [],
        chatHistory: { chatHistory: "", latestResponse: "" },
        cURLPID: 0
    }

    switch component {
        case "model":
            switch action {
                case "get": return state.modelHistory
                case "add": state.modelHistory.Push(data)
                case "remove": (state.modelHistory.Length) ? state.modelHistory.Pop() : ""
            }

        case "chat":
            switch action {
                case "get": return state.chatHistory
                case "add":
                    state.chatHistory.chatHistory := data.chatHistory
                    state.chatHistory.latestResponse := data.latestResponse
            }

        case "cURL":
            switch action {
                case "get": return state.cURLPID
                case "set": state.cURLPID := data
                case "close": ProcessClose(state.cURLPID), state.cURLPID := 0
            }
    }
}

; ----------------------------------------------------
; Call main.js functions
; ----------------------------------------------------

postWebMessage(target, data := unset) {
    msgObj := { target: target }

    ; If data is provided, add it to the message object
    msgObj.data := IsSet(data) ? data : unset

    jsonStr := jsongo.Stringify(msgObj)
    responseWindow.PostWebMessageAsJSON(jsonStr)
}

; ----------------------------------------------------
; Deletes the files created by the main script
; ----------------------------------------------------

deleteTempFiles() {
    FileDelete(requestParams["chatHistoryJSONRequestFile"])
    FileDelete(requestParams["cURLCommandFile"])
    FileExist(requestParams["cURLOutputFile"]) ? FileDelete(requestParams["cURLOutputFile"]) : ""
    FileDelete(A_Args[1])
}

; ----------------------------------------------------
; Start or stop loading cursor
; ----------------------------------------------------

startLoadingCursor(status) {
    status ? CustomMessages.notifyResponseWindowState(CustomMessages.WM_RESPONSE_WINDOW_LOADING_START,
        requestParams["uniqueID"], , requestParams["mainScriptHiddenhWnd"])
            : CustomMessages.notifyResponseWindowState(CustomMessages.WM_RESPONSE_WINDOW_LOADING_FINISH,
                requestParams["uniqueID"], , requestParams["mainScriptHiddenhWnd"])
}
