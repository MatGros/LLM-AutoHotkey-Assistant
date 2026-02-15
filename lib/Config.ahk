#Requires AutoHotkey v2.0

; ----------------------------------------------------
; Library includes
; ----------------------------------------------------

#Include "jsongo.v2.ahk"
#Include "Promise.ahk"
#Include "ComVar.ahk"
#Include "AutoXYWH.ahk"
#Include "SystemThemeAwareToolTip.ahk"
#Include "ToolTipEx.ahk"
#Include "WebViewToo.ahk"
#Include "Dark_Menu.ahk"
#Include "Dark_MsgBox.ahk"

; NOTE: "Response Window.ahk" is intentionally NOT included here.
; It is launched as a separate process via Run() and reads A_Args[1].

#Include "..\Prompts.ahk"

; ----------------------------------------------------
; Class: OllamaBackend
; Handles API communication with Ollama-compatible backends.
; ----------------------------------------------------

class OllamaBackend {
    baseURL := ""
    apiKey := ""

    __New(url, key := "") {
        this.baseURL := url
        this.apiKey := key
    }

    /**
     * Creates a JSON request string for the Ollama /api/chat endpoint.
     * @param {String} model - Full model name (e.g. "ollama/gemma3:4b")
     * @param {String} system - System prompt
     * @param {String} prompt - User prompt
     * @param {Boolean} stream - Whether to enable streaming (default: false)
     * @returns {String} JSON string
     */
    createJSONRequest(model, system, prompt, stream := false) {
        ; AHK v2 represents true/false as 1/0 (integers).
        ; jsongo serializes them as numbers, but Ollama's Go API
        ; requires a JSON boolean for "stream". We use a placeholder
        ; string and replace it after serialization.
        streamPlaceholder := stream ? "__JSON_TRUE__" : "__JSON_FALSE__"
        obj := {
            model: model,
            messages: [{ role: "system", content: system }, { role: "user", content: prompt }],
            stream: streamPlaceholder
        }
        result := jsongo.Stringify(obj)
        result := StrReplace(result, '"__JSON_TRUE__"', "true")
        result := StrReplace(result, '"__JSON_FALSE__"', "false")
        return result
    }

    /**
     * Builds a cURL command string for the Ollama API.
     * @param {String} requestFile - Path to the JSON request file
     * @param {String} outputFile - Path where the response will be written
     * @returns {String} Complete cURL command
     */
    buildcURLCommand(requestFile, outputFile) {
        url := this.baseURL . "/api/chat"
        cmd := 'curl.exe -s -X POST "' url '"'
        if (this.apiKey != "") {
            cmd .= ' -H "Authorization: Bearer ' this.apiKey '"'
        }
        cmd .= ' -H "Content-Type: application/json"'
        cmd .= ' -d @"' requestFile '"'
        cmd .= ' -o "' outputFile '"'
        return cmd
    }

    /**
     * Extracts the response text from a parsed API JSON response.
     * @param {Map} parsedVar - Parsed JSON response from Ollama
     * @returns {Object} Object with .response and .error properties
     */
    extractJSONResponse(parsedVar) {
        result := { response: "", error: "" }
        if (Type(parsedVar) = "Map") {
            if (parsedVar.Has("error")) {
                result.error := parsedVar["error"]
                return result
            }
            if (parsedVar.Has("message") && parsedVar["message"].Has("content")) {
                result.response := parsedVar["message"]["content"]
            }
        } else {
            if (parsedVar.HasProp("error")) {
                result.error := parsedVar.error
                return result
            }
            if (parsedVar.HasProp("message") && parsedVar.message.HasProp("content")) {
                result.response := parsedVar.message.content
            }
        }
        return result
    }

    /**
     * Appends a message to the chat history JSON and writes it to the file.
     * @param {String} role - "user" or "assistant"
     * @param {String} content - Message content
     * @param {VarRef} jsonStr - Reference to the JSON string (updated in-place)
     * @param {String} filePath - Path to the JSON file to write
     */
    appendToChatHistory(role, content, &jsonStr, filePath) {
        parsed := jsongo.Parse(jsonStr)
        if (Type(parsed) = "Map") {
            parsed["messages"].Push(Map("role", role, "content", content))
        } else {
            parsed.messages.Push({ role: role, content: content })
        }
        jsonStr := jsongo.Stringify(parsed)
        FileOpen(filePath, "w", "UTF-8-RAW").Write(jsonStr)
    }

    /**
     * Removes the last assistant message from the chat history (for Retry).
     * @param {VarRef} jsonStr - Reference to the JSON string (updated in-place)
     */
    removeLastAssistantMessage(&jsonStr) {
        parsed := jsongo.Parse(jsonStr)
        if (Type(parsed) = "Map") {
            messages := parsed["messages"]
            if (messages.Length > 0) {
                lastMsg := messages[messages.Length]
                if (Type(lastMsg) = "Map" && lastMsg.Has("role") && lastMsg["role"] = "assistant") {
                    messages.Pop()
                } else if (lastMsg.HasProp("role") && lastMsg.role = "assistant") {
                    messages.Pop()
                }
            }
        } else {
            messages := parsed.messages
            if (messages.Length > 0 && messages[messages.Length].role = "assistant") {
                messages.Pop()
            }
        }
        jsonStr := jsongo.Stringify(parsed)
    }
}

; ----------------------------------------------------
; Class: InputWindow
; GUI wrapper for text input with Send/Cancel buttons.
; Used for custom prompts and chat messages.
; ----------------------------------------------------

class InputWindow {
    guiObj := ""
    EditControl := ""
    _sendCallback := ""
    _skipConfirmation := false
    _title := ""

    /**
     * @param {String} title - Window title
     * @param {Boolean} skipConfirmation - If true, skips close confirmation
     */
    __New(title, skipConfirmation := false) {
        this._title := title
        this._skipConfirmation := skipConfirmation

        this.guiObj := Gui("+AlwaysOnTop +Resize +MinSize400x210", title)
        this.guiObj.SetFont("s10", "Segoe UI")
        this.guiObj.OnEvent("Close", (*) => this.closeButtonAction())
        this.guiObj.OnEvent("Size", this._onResize.Bind(this))

        this.EditControl := this.guiObj.Add("Edit", "x10 y10 w380 h150 Multi WantReturn vUserInput")

        ; Auto-resize settings for the Edit control
        this._minEditHeight := 80
        this._maxEditHeight := 800
        this._lineHeight := 18 ; px per visual line (approximate)

        ; Adjust height as the user types
        try {
            this.EditControl.OnEvent("Change", this._onEditChange.Bind(this))
        } catch {
            ; ignore if event registration fails
        }

        this._sendBtn := this.guiObj.Add("Button", "x10 y170 w185 h30 Default", "Envoyer")
        this._sendBtn.OnEvent("Click", (*) => this._onSend())

        this._cancelBtn := this.guiObj.Add("Button", "x205 y170 w185 h30", "Annuler")
        this._cancelBtn.OnEvent("Click", (*) => this.closeButtonAction())
    }

    /**
     * Registers the callback function for the Send button.
     * @param {Func} callback - Function to call when Send is clicked
     */
    sendButtonAction(callback) {
        this._sendCallback := callback
    }

    _onSend(*) {
        if (this._sendCallback)
            this._sendCallback()
    }

    _onResize(guiObj, minMax, width, height) {
        if (minMax = -1)
            return

        ; Respect the computed edit height when available; otherwise fill available area
        editHeight := Max(this._minEditHeight, Min(height - 60, this._maxEditHeight))
        this.EditControl.Move(, , width - 20, editHeight)

        ; Position buttons relative to current window height
        this._sendBtn.Move(10, height - 40, (width - 30) // 2)
        this._cancelBtn.Move(20 + (width - 30) // 2, height - 40, (width - 30) // 2)
    }

    /**
     * Shows the input window.
     * @param {String} initialMessage - Optional initial text for the edit field
     * @param {String} windowTitle - Optional override for the window title
     * @param {String} winTitle - Optional WinTitle to activate after showing
     */
    showInputWindow(initialMessage?, windowTitle?, winTitle?) {
        if IsSet(initialMessage) && initialMessage != ""
            this.EditControl.Value := initialMessage

        if IsSet(windowTitle) && windowTitle != ""
            this.guiObj.Title := windowTitle
        else
            this.guiObj.Title := this._title

        ; Show with default size, then adjust Edit height based on content
        this.guiObj.Show("w400 h210")

        ; Adjust Edit control height to fit content (handles pasted initialMessage)
        try {
            this._adjustEditHeight()
        } catch {
        }

        ; Ensure the input window and its Edit control receive focus so the user can type immediately
        try {
            WinActivate("ahk_id " this.guiObj.hWnd)
            this.EditControl.Focus()
        } catch {
            ; ignore if unable to focus
        }

        if IsSet(winTitle)
            WinActivate(winTitle)
    }

    /**
     * Validates that input is not empty, hides the window if valid.
     * @returns {Boolean} true if input is valid
     */
    validateInputAndHide() {
        if (Trim(this.EditControl.Value) = "") {
            MsgBox("Veuillez entrer un message.", this.guiObj.Title, 48)
            return false
        }
        this.guiObj.Hide()
        return true
    }

    _onEditChange(*) {
        try {
            this._adjustEditHeight()
        } catch {
        }
    }

    _adjustEditHeight() {
        ; Compute an approximate visual line count to size the Edit control
        content := this.EditControl.Value
        ; Logical lines
        lines := StrSplit(content, "`n")

        ; Get current window width so we can estimate wrapping
        this.guiObj.GetPos(, , &w, &h)
        charsPerLine := Max(20, (w - 40) // 8) ; rough average char width ≈ 8px

        visualLines := 0
        for _, ln in lines {
            ; treat tabs as several chars
            lnStr := StrReplace(ln, "`t", "    ")
            lnLen := StrLen(lnStr)
            visualLines += Max(1, (lnLen + charsPerLine - 1) // charsPerLine)
        }

        desiredEditHeight := visualLines * this._lineHeight + 12 ; padding
        desiredEditHeight := Max(this._minEditHeight, Min(desiredEditHeight, this._maxEditHeight))

        ; Ensure GUI is tall enough to contain the edit + buttons area
        desiredGuiHeight := desiredEditHeight + 80
        this.guiObj.GetPos(&x, &y, &currW, &currH)
        newW := currW > 0 ? currW : 400
        if (desiredGuiHeight != currH)
            try {
                this.guiObj.Move(, , newW, desiredGuiHeight)
            } catch {
            }

        ; Apply the Edit control height and reposition buttons
        try {
            this.EditControl.Move(, , newW - 20, desiredEditHeight)
            this._sendBtn.Move(10, desiredGuiHeight - 40, (newW - 30) // 2)
            this._cancelBtn.Move(20 + (newW - 30) // 2, desiredGuiHeight - 40, (newW - 30) // 2)
        } catch {
            ; ignore move errors
        }
    }

    /**
     * Closes the input window and clears the edit field.
     */
    closeButtonAction() {
        this.EditControl.Value := ""
        this.guiObj.Hide()
    }

    /**
     * Sets the skip confirmation flag.
     * @param {Boolean} value
     */
    setSkipConfirmation(value) {
        this._skipConfirmation := value
    }
}

; ----------------------------------------------------
; Class: CustomMessages
; Inter-process communication between the main script
; and Response Window sub-scripts via PostMessage.
; ----------------------------------------------------

class CustomMessages {
    ; Custom window message constants (WM_USER + offset)
    static WM_RESPONSE_WINDOW_LOADING_START  := 0x400 + 123
    static WM_RESPONSE_WINDOW_LOADING_FINISH := 0x400 + 124
    static WM_RESPONSE_WINDOW_OPENED         := 0x400 + 125
    static WM_RESPONSE_WINDOW_CLOSED         := 0x400 + 126
    static WM_SEND_TO_ALL_MODELS             := 0x400 + 127

    /**
     * Registers OnMessage handlers for inter-process communication.
     * @param {String} scriptType - "mainScript" or "subScript"
     * @param {Func} callback - Handler function (wParam, lParam, msg, hwnd)
     *   - mainScript: receives OPENED, CLOSED, LOADING_START, LOADING_FINISH
     *   - subScript: receives SEND_TO_ALL_MODELS
     */
    static registerHandlers(scriptType, callback) {
        if (scriptType = "mainScript") {
            OnMessage(this.WM_RESPONSE_WINDOW_OPENED, callback)
            OnMessage(this.WM_RESPONSE_WINDOW_CLOSED, callback)
            OnMessage(this.WM_RESPONSE_WINDOW_LOADING_START, callback)
            OnMessage(this.WM_RESPONSE_WINDOW_LOADING_FINISH, callback)
        } else if (scriptType = "subScript") {
            OnMessage(this.WM_SEND_TO_ALL_MODELS, callback)
        }
    }

    /**
     * Sends a state notification to another script via PostMessage.
     * @param {Integer} msg - One of the WM_ constants
     * @param {Integer} uniqueID - Unique identifier (sent as wParam)
     * @param {Integer} hWnd - Source window handle (sent as lParam), or target if no targetHWnd
     * @param {Integer} targetHWnd - Target window handle to send the message to
     *
     * Usage patterns:
     *   From sub-script → main: notifyResponseWindowState(WM_..., uniqueID, responseHWnd, mainHWnd)
     *   From main → sub-script: notifyResponseWindowState(WM_..., uniqueID, targetHWnd)
     */
    static notifyResponseWindowState(msg, uniqueID, hWnd := 0, targetHWnd := 0) {
        try {
            if (targetHWnd) {
                ; 4-arg form: hWnd is lParam, targetHWnd is the recipient
                PostMessage(msg, uniqueID, hWnd, , "ahk_id " targetHWnd)
            } else {
                ; 3-arg form: hWnd is the recipient, lParam is 0
                PostMessage(msg, uniqueID, 0, , "ahk_id " hWnd)
            }
        }
    }
}
