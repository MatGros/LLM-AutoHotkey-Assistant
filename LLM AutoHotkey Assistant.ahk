#Requires AutoHotkey v2.0.18+
#Include <Config>
#SingleInstance

; ----------------------------------------------------
; Hotkeys
; ----------------------------------------------------

; Trigger on release to match Windows behavior and ensure native menu is blocked
^RButton:: return
^RButton Up:: {
    mainScriptHotkeyActions("showPromptMenu")
}

~^s:: mainScriptHotkeyActions("saveAndReloadScript")
~^w:: mainScriptHotkeyActions("closeWindows")

#SuspendExempt
CapsLock & F12:: mainScriptHotkeyActions("suspendHotkey")

mainScriptHotkeyActions(action) {
    activeModelsCount := getActiveModels().Count

    switch action {
        case "showPromptMenu":
            promptMenu := Menu()
            tagsMap := Map()

            ; Process all active models once to build prompt maps
            if (activeModelsCount > 0) {

                for uniqueID, modelData in getActiveModels() {
                    getActiveModels().%modelData.promptName% := true
                }

                ; Send message to menu
                sendToMenu := Menu()
                promptMenu.Add("Envoyer un message à", sendToMenu)

                for uniqueID, modelData in getActiveModels() {
                    sendToMenu.Add(modelData.promptName, sendToPromptGroupHandler.Bind(modelData.promptName))
                }

                ; If there are more than one Response Windows, add "All" menu option
                if (activeModelsCount > 1) {
                    sendToMenu.Add("Tous", (*) => sendToAllModelsInputWindow.showInputWindow(, , "ahk_id " sendToAllModelsInputWindow
                        .guiObj.hWnd))
                }

                ; Line separator after Activate and Send message to
                promptMenu.Add()
            }

            ; Normal prompts
            for index, prompt in managePromptState("prompts", "get") {

                ; Check if prompt has tags
                hasTags := prompt.HasProp("tags") && prompt.tags && prompt.tags.Length > 0

                ; If no tags, add directly to menu and continue
                if !hasTags {
                    promptMenu.Add(prompt.menuText, promptMenuHandler.Bind(index))
                    continue
                }

                ; Process tags
                for tag in prompt.tags {
                    normalizedTag := StrLower(Trim(tag))

                    ; Create tag menu if doesn't exist
                    if !tagsMap.Has(normalizedTag) {
                        tagsMap[normalizedTag] := { menu: Menu(), displayName: tag }
                        promptMenu.Add(tag, tagsMap[normalizedTag].menu)
                    }

                    ; Add prompt to tag menu
                    tagsMap[normalizedTag].menu.Add(prompt.menuText, promptMenuHandler.Bind(index))
                }
            }

            ; Add menus ("Activate", "Minimize", "Close") that manages Response Windows
            ; after normal prompts if there are active models
            if (activeModelsCount > 0) {

                ; Line separator before managing Response Window menu
                promptMenu.Add()

                ; Define the action types
                actionTypes := ["activer", "réduire", "fermer"]
                actionLabels := ["Activer", "Réduire", "Fermer"]

                ; Create submenus for each action type
                for idx, actionType in actionTypes {

                    actionSubMenu := Menu()
                    promptMenu.Add(actionLabels[idx], actionSubMenu)

                    ; Add menu items for each active model
                    for uniqueID, modelData in getActiveModels() {
                        actionSubMenu.Add(modelData.promptName, managePromptWindows.Bind(actionType, modelData.promptName
                        ))
                    }

                    ; If there are more than one Response Windows, add "All" menu option
                    if (activeModelsCount > 1) {
                        actionSubMenu.Add("Tous", managePromptWindows.Bind(actionType))
                    }
                }
            }

            ; Line separator before Options
            promptMenu.Add()

            ; Help menu
            promptMenu.Add("&Aide", (*) => showHelpDialog())

            ; Options menu
            promptMenu.Add("&Paramètres", optionsMenu := Menu())
            optionsMenu.Add("&1 - Éditer les prompts", (*) => Run("Notepad " A_ScriptDir "\Prompts.ahk"))
            optionsMenu.Add("&2 - Voir la bibliothèque Ollama", (*) => Run("https://ollama.com/library"))
            promptMenu.Show()

        case "suspendHotkey":
            KeyWait "CapsLock", "L"
            SetCapsLockState "Off"
            toggleSuspend(A_IsSuspended)

        case "saveAndReloadScript":
            if !WinActive("Prompts.ahk") {
                return
            }

            ; Small delay to ensure file operations are complete
            Sleep 100

            if (activeModelsCount > 0) {
                MsgBox("Le script se recharge automatiquement une fois toutes les fenêtres de réponse fermées.",
                    "LLM AutoHotkey Assistant", 64)
                responseWindowState(0, 0, "reloadScript", 0)
            } else {
                Reload()
            }

        case "closeWindows":
            switch WinActive("A") {
                case customPromptInputWindow.guiObj.hWnd: customPromptInputWindow.closeButtonAction()
                case sendToPromptNameInputWindow.guiObj.hWnd: sendToPromptNameInputWindow.closeButtonAction()
                case sendToAllModelsInputWindow.guiObj.hWnd: sendToAllModelsInputWindow.closeButtonAction()
            }
    }
}

; ----------------------------------------------------
; Script tray menu
; ----------------------------------------------------

trayMenuItems := [{
    menuText: "&Aide",
    function: (*) => showHelpDialog()
}, {
    menuText: "&Tester l'API",
    description: "Exécuter un test rapide de connectivité + réponse du modèle (pas besoin d'entrée de clé)",
    function: (*) => (TEST_API_MODE := "mock", quickAPIHealthCheck(), TEST_API_MODE := "")
}, {
    menuText: "&Réinitialiser la configuration",
    description: "Effacer la configuration enregistrée pour que l'app la demande à nouveau au prochain démarrage",
    function: (*) => (FileDelete(A_AppData "\LLM-AutoHotkey-Assistant\ollama_config.json"), MsgBox("Configuration effacée. Le script va maintenant recharger et demander la configuration.", "Réinitialiser la configuration", 64), Reload())
}, {
    menuText: "&Recharger le script",
    function: (*) => Reload()
}, {
    menuText: "&Quitter",
    function: (*) => ExitApp()
}]

; ----------------------------------------------------
; Generate tray menu dynamically
; ----------------------------------------------------

TraySetIcon("icons\IconOn.ico")
A_TrayMenu.Delete()
for index, item in trayMenuItems {
    A_TrayMenu.Add(item.menuText, item.function)
}
A_IconTip := "LLM AutoHotkey Assistant"

; ----------------------------------------------------
; Create new instance of OllamaBackend class
; ----------------------------------------------------

router := OllamaBackend(BaseURL, APIKey)

; Quick startup health-check: send a tiny prompt to the first configured model and verify a non-empty reply.
; If the test fails, the user is notified and can reset the configuration via the tray menu.
quickAPIHealthCheck() {
    if (!BaseURL)
        return

    ; If user requested a mock run (via tray menu) or the environment variable is set,
    ; skip the real HTTP/cURL call and report success for UI testing.
    if (EnvGet("LLM_AHK_TEST_MODE") = "mock" || (IsSet(TEST_API_MODE) && TEST_API_MODE = "mock")) {
        showSuccessTooltip("✓ Mock API test passed — GUI flow OK.")
        TraySetIcon("icons\IconOn.ico")
        return
    }

    try {
        promptsList := managePromptState("prompts", "get")
        testModel := ""
        for _, p in promptsList {
            if (p.HasProp("APIModels") && p.APIModels) {
                models := StrSplit(RegExReplace(p.APIModels, "\s+", ""), ",")
                testModel := models[1]
                break
            }
        }
        if (!testModel)
             testModel := "gemma3:4b" ; Default fallback

        req := router.createJSONRequest(testModel, "System: connectivity check.", "hi")
        tmpReq := A_Temp "\llm_test_request.json"
        tmpOut := A_Temp "\llm_test_output.json"
        FileOpen(tmpReq, "w", "UTF-8-RAW").Write(req)
        cmd := router.buildcURLCommand(tmpReq, tmpOut)

        Run(cmd, , "Hide", &pid)
        start := A_TickCount
        timeout := 8000
        while (ProcessExist(pid) && (A_TickCount - start) < timeout)
            Sleep 150

        if (ProcessExist(pid)) {
            ProcessClose(pid)
            TraySetIcon("icons\IconOff.ico")
            MsgBox("Le test de connectivité API a expiré. Le modèle peut être inaccessible ou l'URL de base peut être invalide.", "Test API échoué", "16")
            return
        }

        if !FileExist(tmpOut) {
            TraySetIcon("icons\IconOff.ico")
            MsgBox("Test API échoué : aucun fichier de réponse créé.", "Test API échoué", "16")
            return
        }

        raw := FileOpen(tmpOut, "r", "UTF-8").Read()
        try {
            var := jsongo.Parse(raw)
            respObj := router.extractJSONResponse(var)
           
            if (respObj.HasProp("error")) {
                 throw respObj.error
            }

            resp := respObj.response
            if (!resp || Trim(resp) = "")
                throw Error("empty response")
            showSuccessTooltip("✓ Ollama connection OK — model responded.")
            TraySetIcon("icons\IconOn.ico")
            FileDelete(tmpReq)
            FileDelete(tmpOut)
        } catch as e {
            errDetail := (HasProp(e, "Message") ? e.Message : String(e))
            ; Read the raw response to show it
            rawContent := ""
            try rawContent := FileOpen(tmpOut, "r", "UTF-8").Read()
            TraySetIcon("icons\IconOff.ico")
            MsgBox("Test API échoué. Erreur : " errDetail "`n`nContenu de la réponse :`n" SubStr(rawContent, 1, 500) "`n`nVous pouvez réinitialiser la configuration depuis le menu de la barre d'état.", "Test API échoué", 16)
        }
    } catch {
        ; silently ignore startup test errors
    }
}

; Run the quick health check in background (non-blocking)
SetTimer(quickAPIHealthCheck, -10)

; ----------------------------------------------------
; Create Input Windows
; ----------------------------------------------------

customPromptInputWindow := InputWindow("Prompt personnalisé")
sendToAllModelsInputWindow := InputWindow("Envoyer un message à tous")
sendToPromptNameInputWindow := InputWindow("Envoyer un message au prompt")

; ----------------------------------------------------
; Register sendButtonActions
; ----------------------------------------------------

customPromptInputWindow.sendButtonAction(customPromptSendButtonAction)
sendToAllModelsInputWindow.sendButtonAction(sendToAllModelsSendButtonAction)
sendToPromptNameInputWindow.sendButtonAction(sendToGroupSendButtonAction)

; ----------------------------------------------------
; Input Window actions
; ----------------------------------------------------

customPromptSendButtonAction(*) {
    if !customPromptInputWindow.validateInputAndHide() {
        return
    }

    selectedPrompt := managePromptState("selectedPrompt", "get")
    processInitialRequest(selectedPrompt.promptName, selectedPrompt.menuText, selectedPrompt.systemPrompt,
        selectedPrompt.APIModels,
        selectedPrompt.HasProp("copyAsMarkdown") && selectedPrompt.copyAsMarkdown,
        selectedPrompt.HasProp("isAutoPaste") && selectedPrompt.isAutoPaste,
        selectedPrompt.HasProp("skipConfirmation") && selectedPrompt.skipConfirmation,
        customPromptInputWindow.EditControl.Value
    )
    customPromptInputWindow.EditControl.Value := ""
}

sendToAllModelsSendButtonAction(*) {
    if (getActiveModels().Count = 0) {
        MsgBox "Aucune fenêtre de réponse trouvée. Message non envoyé.", "Envoyer un message à tous les modèles", "IconX"
        sendToAllModelsInputWindow.guiObj.Hide
        return
    }

    if !sendToAllModelsInputWindow.validateInputAndHide() {
        return
    }

    ; The main script must know each Response Window's JSON file
    ; so it can read it, parse it, append the new
    ; user message, then write it back
    for uniqueID, modelData in getActiveModels() {
        JSONStr := FileOpen(modelData.JSONFile, "r", "UTF-8").Read()
        router.appendToChatHistory("user", sendToAllModelsInputWindow.EditControl.Value, &JSONStr, modelData.JSONFile)

        ; Notify the Response Window to re-read the JSON file and call sendRequestToLLM() again
        responseWindowhWnd := modelData.hWnd
        CustomMessages.notifyResponseWindowState(CustomMessages.WM_SEND_TO_ALL_MODELS, uniqueID, responseWindowhWnd
        )
    }
}

sendToGroupSendButtonAction(*) {
    if (getActiveModels().Count = 0) {
        MsgBox "Aucune fenêtre de réponse trouvée. Message non envoyé.", "Envoyer un message à tous les modèles", "IconX"
        sendToAllModelsInputWindow.guiObj.Hide
        return
    }

    if !sendToPromptNameInputWindow.validateInputAndHide() {
        return
    }

    if (!targetPromptName := managePromptState("selectedPromptForMessage", "get")) {
        return
    }

    ; Send message only to active models that belong to this prompt
    for uniqueID, modelData in getActiveModels() {

        ; Check if this model belongs to the selected prompt
        if (modelData.promptName != targetPromptName) {
            continue
        }

        JSONStr := FileOpen(modelData.JSONFile, "r", "UTF-8").Read()
        router.appendToChatHistory("user", sendToPromptNameInputWindow.EditControl.Value, &JSONStr, modelData.JSONFile)

        ; Notify the Response Window to re-read the JSON file and call sendRequestToLLM() again
        responseWindowhWnd := modelData.hWnd
        CustomMessages.notifyResponseWindowState(CustomMessages.WM_SEND_TO_ALL_MODELS, uniqueID, responseWindowhWnd)
    }

    sendToPromptNameInputWindow.EditControl.Value := ""
}

sendToPromptGroupHandler(promptName, *) {
    promptsList := managePromptState("prompts", "get")

    ; Find the prompt with the matching promptName
    for _, prompt in promptsList {

        ; Check if the prompt has the same name as the one we're looking for
        if (prompt.promptName = promptName) {
            selectedPrompt := prompt
            break
        }
    }

    managePromptState("selectedPromptForMessage", "set", promptName)

    ; Check if the prompt has skipConfirmation property and set accordingly
    sendToPromptNameInputWindow.setSkipConfirmation(selectedPrompt.HasProp("skipConfirmation") ? selectedPrompt.skipConfirmation : false)
    sendToPromptNameInputWindow.showInputWindow(, "Envoyer un message à " promptName, "ahk_id " sendToPromptNameInputWindow.guiObj
        .hWnd
    )
}

; Generic function to perform an operation on prompt windows
;
; Parameters:
; - operation (activate, minimize, close): The operation to perform
; - promptName: Optional. If provided, only windows for this prompt will be affected
managePromptWindows(operation, promptName := "", *) {

    ; Create a list of window handles that match our criteria
    hWndsToManage := []

    ; Iterate through all active models
    for uniqueID, modelData in getActiveModels() {
        if (promptName = "All" || modelData.promptName = promptName) {
            hWndsToManage.Push(modelData.hWnd)
        }
    }

    ; Perform the requested operation on each window
    for _, hWnd in hWndsToManage {
        switch operation {
            case "activer": WinActivate("ahk_id " hWnd)
            case "réduire": WinMinimize("ahk_id " hWnd)
            case "fermer": WinClose("ahk_id " hWnd)
        }
    }
}

; ----------------------------------------------------
; Initialize Suspend GUI
; ----------------------------------------------------

scriptSuspendStatus := Gui()
scriptSuspendStatus.SetFont("s10", "Cambria")
scriptSuspendStatus.Add("Text", "cBlack Center", "LLM AutoHotkey Assistant Suspended")
scriptSuspendStatus.BackColor := "0xFFDF00"
scriptSuspendStatus.Opt("-Caption +Owner -SysMenu +AlwaysOnTop")
scriptSuspendStatusWidth := ""
scriptSuspendStatus.GetPos(, , &scriptSuspendStatusWidth)

; ----------------------------------------------------
; Toggle Suspend
; ----------------------------------------------------

toggleSuspend(*) {
    Suspend -1
    if (A_IsSuspended) {
        TraySetIcon("icons\IconOff.ico", , 1)
        A_IconTip := "LLM AutoHotkey Assistant - Suspended)"

        ; Show GUI at the bottom, centered
        scriptSuspendStatus.Show("AutoSize x" (A_ScreenWidth - scriptSuspendStatusWidth) / 2.3 " y990 NA")
    } else {
        TraySetIcon("icons\IconOn.ico")
        A_IconTip := "LLM AutoHotkey Assistant"
        scriptSuspendStatus.Hide()
    }
}

; ----------------------------------------------------
; Prompt menu handler function
; ----------------------------------------------------

promptMenuHandler(index, *) {
    promptsList := managePromptState("prompts", "get")
    selectedPrompt := promptsList[index]
    if (selectedPrompt.HasProp("isCustomPrompt") && selectedPrompt.isCustomPrompt) {

        ; Save the prompt for future reference in customPromptSendButtonAction(*)
        managePromptState("selectedPrompt", "set", selectedPrompt)

        ; Set skipConfirmation property based on the prompt
        customPromptInputWindow.setSkipConfirmation(selectedPrompt.HasProp("skipConfirmation") ? selectedPrompt.skipConfirmation : false)

        customPromptInputWindow.showInputWindow(selectedPrompt.HasProp("customPromptInitialMessage")
            ? selectedPrompt.customPromptInitialMessage : unset, selectedPrompt.promptName, "ahk_id " customPromptInputWindow
        .guiObj.hWnd)
    } else {
        processInitialRequest(selectedPrompt.promptName, selectedPrompt.menuText, selectedPrompt.systemPrompt,
            selectedPrompt.APIModels, selectedPrompt.HasProp("copyAsMarkdown") && selectedPrompt.copyAsMarkdown,
            selectedPrompt.HasProp("isAutoPaste") && selectedPrompt.isAutoPaste,
            selectedPrompt.HasProp("skipConfirmation") && selectedPrompt.skipConfirmation)
    }
}

; ----------------------------------------------------
; Manage prompt states
; ----------------------------------------------------

managePromptState(component, action, data := {}) {
    static state := {
        prompts: prompts,
        selectedPrompt: {},
        selectedPromptForMessage: {}
    }

    switch component {
        case "prompts":
            switch action {
                case "get": return state.prompts
                case "set": state.prompts := data
            }

        case "selectedPrompt":
            switch action {
                case "get": return state.selectedPrompt
                case "set": state.selectedPrompt := data
            }

        case "selectedPromptForMessage":
            switch action {
                case "get": return state.selectedPromptForMessage
                case "set": state.selectedPromptForMessage := data
            }
    }
}

; ----------------------------------------------------
; Connect to LLM API and process request
; ----------------------------------------------------

processInitialRequest(promptName, menuText, systemPrompt, APIModels, copyAsMarkdown, isAutoPaste, skipConfirmation,
    customPromptMessage := unset) {

    ; Handle the copied text
    clipboardBeforeCopy := A_Clipboard
    A_Clipboard := ""
    Send("^c")

    if !ClipWait(1) {
        if IsSet(customPromptMessage) {
            userPrompt := customPromptMessage
        } else {
            manageCursorAndToolTip("Reset")
            MsgBox "Impossible de copier le texte dans le presse-papiers.", "Aucun texte copié", "IconX"
            return
        }
    } else if IsSet(customPromptMessage) {
        userPrompt := customPromptMessage "`n`n" A_Clipboard
    } else {
        userPrompt := A_Clipboard
    }

    A_Clipboard := clipboardBeforeCopy

    ; Removes newlines, spaces, and splits by comma
    APIModels := StrSplit(RegExReplace(APIModels, "\s+", ""), ",")

    ; Automatically disables isAutoPaste if more than one model is present
    isAutoPaste := (APIModels.Length > 1) ? false : isAutoPaste

    for i, fullAPIModelName in APIModels {

        ; Get text before forward slash as providerName
        providerName := SubStr(fullAPIModelName, 1, InStr(fullAPIModelName, "/") - 1)

        ; Get text after forward slash as singleAPIModelName
        singleAPIModelName := SubStr(fullAPIModelName, InStr(fullAPIModelName, "/") + 1)

        uniqueID := A_TickCount

        ; Create the chatHistoryJSONRequest
        chatHistoryJSONRequest := router.createJSONRequest(fullAPIModelName, systemPrompt, userPrompt)

        ; Generate sanitized filenames for chat history, cURL command, and cURL output files
        chatHistoryJSONRequestFile := A_Temp "\" RegExReplace("chatHistoryJSONRequest_" promptName "_" singleAPIModelName "_" uniqueID ".json",
            "[\/\\:*?`"<>|]", "")
        cURLCommandFile := A_Temp "\" RegExReplace("cURLCommand_" promptName "_" singleAPIModelName "_" uniqueID ".txt",
            "[\/\\:*?`"<>|]", "")
        cURLOutputFile := A_Temp "\" RegExReplace("cURLOutput_" promptName "_" singleAPIModelName "_" uniqueID ".json",
            "[\/\\:*?`"<>|]", "")

        ; Write the JSON request and cURL command to files
        FileOpen(chatHistoryJSONRequestFile, "w", "UTF-8-RAW").Write(chatHistoryJSONRequest)
        cURLCommand := router.buildcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile)
        FileOpen(cURLCommandFile, "w").Write(cURLCommand)

        ; Maintain a reference in the global map
        getActiveModels()[uniqueID] := {
            promptName: promptName,
            name: singleAPIModelName,
            provider: router,
            JSONFile: chatHistoryJSONRequestFile,
            cURLFile: cURLCommandFile,
            outputFile: cURLOutputFile,
            isLoading: false
        }

        ; Create an object containing all values for the Response Window
        responseWindowDataObj := {
            baseURL: BaseURL,
            APIKey: APIKey,
            chatHistoryJSONRequestFile: chatHistoryJSONRequestFile,
            cURLCommandFile: cURLCommandFile,
            cURLOutputFile: cURLOutputFile,
            providerName: providerName,
            copyAsMarkdown: copyAsMarkdown,
            isAutoPaste: isAutoPaste,
            skipConfirmation: skipConfirmation,
            mainScriptHiddenhWnd: A_ScriptHwnd,
            responseWindowTitle: promptName " [" singleAPIModelName "]",
            singleAPIModelName: singleAPIModelName,
            numberOfAPIModels: APIModels.Length,
            APIModelsIndex: i,
            uniqueID: uniqueID
        }

        ; Write the object to a file named responseWindowData and run
        ; Response Window.ahk while passing the location of that file
        ; through dataObjToJSONStrFile as the first argument
        dataObjToJSONStr := jsongo.Stringify(responseWindowDataObj)
        dataObjToJSONStrFile := A_Temp "\" RegExReplace("responseWindowData_" promptName "_" singleAPIModelName "_" A_TickCount ".json",
            "[\/\\:*?`"<>|]", "")
        FileOpen(dataObjToJSONStrFile, "w", "UTF-8-RAW").Write(dataObjToJSONStr)
        getActiveModels()[uniqueID].JSONFile := chatHistoryJSONRequestFile
        Run("lib\Response Window.ahk " "`"" dataObjToJSONStrFile)
    }
}

; ----------------------------------------------------
; Tracks active models
; ----------------------------------------------------

getActiveModels() {
    static activeModels := Map()
    return activeModels
}

; ----------------------------------------------------
; Custom messages and handlers for detecting
; Response Window states
; ----------------------------------------------------

CustomMessages.registerHandlers("mainScript", responseWindowState)
responseWindowState(uniqueID, responseWindowhWnd, state, mainScriptHiddenhWnd) {
    static responseWindowLoadingCount := 0
    static reloadScript := false

    switch state {
        case CustomMessages.WM_RESPONSE_WINDOW_OPENED:
            getActiveModels()[uniqueID].hWnd := responseWindowhWnd

        case CustomMessages.WM_RESPONSE_WINDOW_CLOSED:
            if getActiveModels().Has(uniqueID) {
                getActiveModels().Delete(uniqueID)
                manageCursorAndToolTip("Update")
            }

            if (getActiveModels().Count = 0) && reloadScript {
                Reload()
            }
        case CustomMessages.WM_RESPONSE_WINDOW_LOADING_START:
            getActiveModels()[uniqueID].isLoading := true
            responseWindowLoadingCount++
            if (responseWindowLoadingCount = 1) {
                manageCursorAndToolTip("Loading")
            }

            manageCursorAndToolTip("Update")

        case CustomMessages.WM_RESPONSE_WINDOW_LOADING_FINISH:
            if (responseWindowLoadingCount > 0 && getActiveModels().Has(uniqueID)) {
                responseWindowLoadingCount--
                getActiveModels()[uniqueID].isLoading := false
                if (responseWindowLoadingCount = 0) {
                    manageCursorAndToolTip("Reset")
                } else {
                    manageCursorAndToolTip("Update")
                }
            }

        case "reloadScript": reloadScript := true
    }
}

; ----------------------------------------------------
; Help dialog
; ----------------------------------------------------

showHelpDialog() {
    helpText := "LLM AutoHotkey Assistant - Raccourcis Clavier (AZERTY)`n"
    helpText .= "================================================`n`n"
    helpText .= "RACCOURCIS PRINCIPAUX:`n"
    helpText .= "  • Ctrl+Clic droit    - Ouvrir le menu des prompts`n"
    helpText .= "  • Ctrl+S            - Recharger le script (si édition)`n"
    helpText .= "  • Ctrl+W            - Fermer les fenêtres d'entrée`n"
    helpText .= "  • CapsLock + F12    - Suspendre/reprendre les raccourcis`n`n"
    helpText .= "CONSEILS D'UTILISATION:`n"
    helpText .= "  1. Appuyez sur Ctrl+Clic droit pour ouvrir le menu`n"
    helpText .= "  2. Cliquez sur un prompt pour l'utiliser`n"
    helpText .= "  3. Copiez d'abord du texte, puis Ctrl+Clic droit → sélectionnez`n"
    helpText .= "  4. Utilisez Options pour éditer les prompts`n`n"
    helpText .= "================================================`n"
    helpText .= "Clic-droit sur l'icône pour plus d'options!"

    MsgBox helpText, "LLM AutoHotkey Assistant - Aide", 64
}


; ----------------------------------------------------
; Success Tooltip Helper
; ----------------------------------------------------
showSuccessTooltip(message) {
    ; Create a custom success notification GUI
    successGui := Gui("+AlwaysOnTop -Caption +ToolWindow", "Success")
    successGui.BackColor := "28a745"  ; Green background
    successGui.SetFont("s14 cWhite Bold", "Segoe UI")
    
    ; Add success icon (checkmark) and message
    successGui.Add("Text", "x20 y15 w660 Center", "✓ " message)
    
    ; Show centered at top of screen
    successGui.Show("xCenter y50 w700 h60 NoActivate")
    
    ; Auto-close after 3 seconds
    SetTimer(() => successGui.Destroy(), -3000)
}

; Cursor and Tooltip management
; ----------------------------------------------------

manageCursorAndToolTip(action) {
    switch action {
        case "Update":
            activeCount := 0
            for key, data in getActiveModels() {
                if data.isLoading {
                    activeCount++
                }
            }

            if (activeCount = 0) {
                ToolTip
                return
            }

            toolTipMessage := "Retrieving response for the following prompt"

            ; Singular and plural forms of the word "model"
            if (activeCount > 1) {
                toolTipMessage .= "s"
            }

            toolTipMessage .= " (Press ESC to cancel):"
            for key, data in getActiveModels() {
                if (data.isLoading) {
                    toolTipMessage .= "`n- " data.promptName " [" data.name "]"
                }
            }

            ToolTipEX(toolTipMessage, 0)

        case "Loading":
            ; Change default arrow cursor (32512) to "working in background" cursor (32650)
            ; Ensure that other cursors remain unchanged to preserve their functionality
            Cursor := DllCall("LoadCursor", "uint", 0, "uint", 32650)
            DllCall("SetSystemCursor", "Ptr", Cursor, "UInt", 32512)

        case "Reset":
            ToolTip
            DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)
    }
}
