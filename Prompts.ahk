; ----------------------------------------------------
; Ollama Configuration (secure runtime loader)
; ----------------------------------------------------

OllamaConfig := loadOllamaConfig()
BaseURL := OllamaConfig.BaseURL
APIKey := (OllamaConfig.HasProp("APIKey") ? OllamaConfig.APIKey : "")

; ----------------------------------------------------
; Load configuration from hidden file under %AppData%\LLM-AutoHotkey-Assistant, or prompt user.
; Supports Local (localhost:11434) and Cloud modes.
; Returns { BaseURL: "...", APIKey: "..." }
loadOllamaConfig() {
    configDir := A_AppData "\LLM-AutoHotkey-Assistant"
    configFile := configDir "\ollama_config.json"
    
    ; 1) Try environment variables first
    envUrl := EnvGet("LLM_AHK_BASE_URL")
    envKey := EnvGet("LLM_AHK_API_KEY")
    if (envUrl != "") {
        return { BaseURL: envUrl, APIKey: envKey }
    }

    ; 2) Try loading from file
    if FileExist(configFile) {
        try {
            content := FileRead(configFile, "UTF-8")
            loadedConfig := jsongo.Parse(content)
            ; Convert Map to Object if necessary
            if (Type(loadedConfig) = "Map" && loadedConfig.Has("BaseURL")) {
                return {
                    BaseURL: loadedConfig["BaseURL"], 
                    APIKey: (loadedConfig.Has("APIKey") ? loadedConfig["APIKey"] : "")
                }
            } else if (loadedConfig.HasProp("BaseURL")) {
                return loadedConfig
            }
        } catch {
             ; Fall through if parse fails
        }
    }

    ; 3) Prompt the user
    g := Gui("+AlwaysOnTop +Owner", "Ollama Configuration")
    g.SetFont("s9", "Segoe UI")
    
    g.Add("Text", "x10 y10 w380", "Select Ollama Backend Mode:")
    
    modeLocal := g.Add("Radio", "x20 y35 w150 Checked", "Local (localhost:11434)")
    modeCloud := g.Add("Radio", "x180 y35 w150", "Cloud / Custom URL")
    
    g.Add("Text", "x10 y65 w380", "Base URL:")
    editUrl := g.Add("Edit", "x10 y85 w380 vBaseURL", "http://localhost:11434")
    
    g.Add("Text", "x10 y115 w380", "API Key (Optional / For Cloud):")
    editKey := g.Add("Edit", "x10 y135 w380 Password vAPIKey", "")
    
    saveCb := g.Add("CheckBox", "x10 y170 Checked vSave", "Save configuration")
    
    btnOk := g.Add("Button", "x220 y200 w80 Default", "OK")
    btnCancel := g.Add("Button", "x310 y200 w80", "Cancel")

    ; Events
    modeLocal.OnEvent("Click", (*) => (editUrl.Value := "http://localhost:11434", editKey.Enabled := false, editKey.Value := ""))
    modeCloud.OnEvent("Click", (*) => (editUrl.Value := "https://api.ollama.com", editKey.Enabled := true, editKey.Focus()))
    
    guiDone := false
    isCancelled := false
    
    btnOk.OnEvent("Click", (*) => (guiDone := true, isCancelled := false, g.Hide()))
    btnCancel.OnEvent("Click", (*) => (guiDone := true, isCancelled := true, g.Hide()))
    
    g.Show("AutoSize Center")
    
    ; Initial state check
    if (modeLocal.Value)
        editKey.Enabled := false
    
    while !guiDone
        Sleep 40
        
    if (isCancelled) {
        g.Destroy()
        return { BaseURL: "", APIKey: "" }
    }
        
    finalUrl := editUrl.Value
    finalKey := editKey.Value
    doSave := saveCb.Value
    g.Destroy()
    
    conf := { BaseURL: finalUrl, APIKey: finalKey }
    
    if (doSave && finalUrl != "") {
        if !DirExist(configDir)
            DirCreate(configDir)
        try {
            FileOpen(configFile, "w", "UTF-8").Write(jsongo.Stringify(conf))
        } catch as e {
             MsgBox("Unable to save config: " (HasProp(e, "Message") ? e.Message : e), "Error", 48)
        }
    }
    
    return conf
}

; Prompts
; ----------------------------------------------------

prompts := [{
    promptName: "Multi-model combo",
    menuText: "&1 - Universal Assistant (Llama 3.1)",
    systemPrompt: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask. My first query is the following:",
    APIModels: "
    (
    llama3.1:latest
    )",
    isCustomPrompt: true,
    customPromptInitialMessage: "How can I help you today?",
    tags: ["&Custom prompts", "&Multi-models", "&General"]
}, {
    promptName: "Rephrase (Fast)",
    menuText: "&1 - Rephrase (Fast)",
    systemPrompt: "Your task is to rephrase the following text or paragraph in English to ensure clarity, conciseness, and a natural flow. If there are abbreviations present, expand it when it's used for the first time, like so: OCR (Optical Character Recognition). The revision should preserve the tone, style, and formatting of the original text. If possible, split it into paragraphs to improve readability. Additionally, correct any grammar and spelling errors you come across. You should also answer follow-up questions if asked. Respond with the rephrased text only:",
    APIModels: "
    (
    qwen2.5-coder:7b
    )",
    tags: ["&Text manipulation", "&General"]
}, {
    promptName: "Summarize (Powerful)",
    menuText: "&2 - Summarize (Powerful)",
    systemPrompt: "Your task is to summarize the following article in English to ensure clarity, conciseness, and a natural flow. If there are abbreviations present, expand it when it's used for the first time, like so: OCR (Optical Character Recognition). The summary should preserve the tone, style, and formatting of the original text, and should be in its original language. If possible, split it into paragraphs to improve readability. Additionally, correct any grammar and spelling errors you come across. You should also answer follow-up questions if asked. Respond with the summary only:",
    APIModels: "
    (
    llama3.1:latest
    )",
    tags: ["&Text manipulation", "&Articles", "&General"]
}, {
    promptName: "Translate to English",
    menuText: "&3 - Translate to English",
    systemPrompt: "Generate an English translation for the following text or paragraph, ensuring the translation accurately conveys the intended meaning or idea without excessive deviation. If there are abbreviations present, expand it when it's used for the first time, like so: OCR (Optical Character Recognition). The translation should preserve the tone, style, and formatting of the original text. If possible, split it into paragraphs to improve readability. Additionally, correct any grammar and spelling errors you come across. You should also answer follow-up questions if asked. Respond with the translation only:",
    APIModels: "
    (
    llama3.1:latest
    )",
    tags: ["&Text manipulation", "Language", "&General"]
}, {
    promptName: "Define (Fast)",
    menuText: "&4 - Define (Fast)",
    systemPrompt: "Provide and explain the definition of the following, providing analogies if needed. In addition, answer follow-up questions if asked:",
    APIModels: "
    (
    qwen2.5-coder:7b
    )",
    tags: ["&Text manipulation", "Learning", "&General"]
}, {
    promptName: "Custom Prompt",
    menuText: "&5 - Custom Prompt (Balanced)",
    systemPrompt: "You are a helpful assistant. Follow the instructions that I will provide or answer any questions that I will ask.",
    APIModels: "
    (
    llama3.1:latest
    )",
    isCustomPrompt: true,
    isAutoPaste: true,
    tags: ["&Custom prompts", "&Auto paste", "&General"]
}, {
    promptName: "Quick Answer",
    menuText: "&6 - Quick Answer (Ultra Fast)",
    systemPrompt: "Provide a quick, concise answer to the following. Be brief and direct:",
    APIModels: "
    (
    qwen2.5-coder:7b
    )",
    isCustomPrompt: true,
    tags: ["&Custom prompts", "&Fast responses", "&General"]
}, {
    promptName: "Detailed Analysis",
    menuText: "&7 - Detailed Analysis (Powerful)",
    systemPrompt: "Provide a thorough and detailed analysis of the following. Think deeply about the topic and provide comprehensive insights:",
    APIModels: "
    (
    llama3.1:latest
    )",
    isCustomPrompt: true,
    tags: ["&Custom prompts", "&Deep analysis", "&General"]
}, {
    promptName: "Multi-line prompt example",
    menuText: "Multi-line prompt example",
    systemPrompt: "
    (
    This prompt is broken down into multiple lines.

    Here is the second sentence.

    And the third one.

    As long as the prompt is inside the quotes and the opening and closing parenthesis,

    it will be valid.
    )",
    APIModels: "
    (
    llama3.1:latest
    )",
    tags: ["&Examples"]
}]