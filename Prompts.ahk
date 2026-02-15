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
    g := Gui("+AlwaysOnTop +Owner", "Configuration Ollama")
    g.SetFont("s9", "Segoe UI")
    
    g.Add("Text", "x10 y10 w380", "Sélectionnez le mode backend Ollama :")
    
    modeLocal := g.Add("Radio", "x20 y35 w150 Checked", "Local (localhost:11434)")
    modeCloud := g.Add("Radio", "x180 y35 w150", "Cloud / URL personnalisée")
    
    g.Add("Text", "x10 y65 w380", "URL de base :")
    editUrl := g.Add("Edit", "x10 y85 w380 vBaseURL", "http://localhost:11434")
    
    g.Add("Text", "x10 y115 w380", "Clé API (Optionnel / Pour Cloud) :")
    editKey := g.Add("Edit", "x10 y135 w380 Password vAPIKey", "")
    
    saveCb := g.Add("CheckBox", "x10 y170 Checked vSave", "Enregistrer la configuration")
    
    btnOk := g.Add("Button", "x220 y200 w80 Default", "OK")
    btnCancel := g.Add("Button", "x310 y200 w80", "Annuler")

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
             MsgBox("Impossible d'enregistrer la configuration : " (HasProp(e, "Message") ? e.Message : e), "Erreur", 48)
        }
    }
    
    return conf
}

; Prompts
; ----------------------------------------------------

prompts := [{
    promptName: "Combo multi-modèles",
    menuText: "&1 - Assistant Universel (Gemma 3)",
    systemPrompt: "Tu es un assistant utile. Suis les instructions que je vais fournir ou réponds aux questions que je vais poser. Ma première requête est la suivante :",
    APIModels: "
    (
    gemma3:4b
    )",
    isCustomPrompt: true,
    customPromptInitialMessage: "Comment puis-je vous aider aujourd'hui ?",
    tags: ["&Prompts personnalisés", "&Multi-modèles", "&Général"]
}, {
    promptName: "Reformuler (Rapide)",
    menuText: "&1 - Reformuler (Rapide)",
    systemPrompt: "Ta tâche est de reformuler le texte ou paragraphe suivant pour garantir clarté, concision et fluidité naturelle. Si des abréviations sont présentes, développe-les lors de leur première utilisation, comme ceci : OCR (Reconnaissance Optique de Caractères). La révision doit préserver le ton, le style et le formatage du texte original. Si possible, divise-le en paragraphes pour améliorer la lisibilité. De plus, corrige toutes les erreurs de grammaire et d'orthographe que tu rencontres. Tu dois également répondre aux questions de suivi si demandé. Réponds uniquement avec le texte reformulé :",
    APIModels: "
    (
    gemma3:4b
    )",
    tags: ["&Manipulation de texte", "&Général"]
}, {
    promptName: "Résumer (Puissant)",
    menuText: "&2 - Résumer (Puissant)",
    systemPrompt: "Ta tâche est de résumer l'article suivant pour garantir clarté, concision et fluidité naturelle. Si des abréviations sont présentes, développe-les lors de leur première utilisation, comme ceci : OCR (Reconnaissance Optique de Caractères). Le résumé doit préserver le ton, le style et le formatage du texte original, et doit être dans sa langue d'origine. Si possible, divise-le en paragraphes pour améliorer la lisibilité. De plus, corrige toutes les erreurs de grammaire et d'orthographe que tu rencontres. Tu dois également répondre aux questions de suivi si demandé. Réponds uniquement avec le résumé :",
    APIModels: "
    (
    gemma3:4b
    )",
    tags: ["&Manipulation de texte", "&Articles", "&Général"]
}, {
    promptName: "Traduire en français",
    menuText: "&3 - Traduire en français",
    systemPrompt: "Génère une traduction en français pour le texte ou paragraphe suivant, en veillant à ce que la traduction transmette fidèlement le sens ou l'idée prévue sans déviation excessive. Si des abréviations sont présentes, développe-les lors de leur première utilisation, comme ceci : OCR (Reconnaissance Optique de Caractères). La traduction doit préserver le ton, le style et le formatage du texte original. Si possible, divise-la en paragraphes pour améliorer la lisibilité. De plus, corrige toutes les erreurs de grammaire et d'orthographe que tu rencontres. Tu dois également répondre aux questions de suivi si demandé. Réponds uniquement avec la traduction :",
    APIModels: "
    (
    gemma3:4b
    )",
    tags: ["&Manipulation de texte", "Langue", "&Général"]
}, {
    promptName: "Définir (Rapide)",
    menuText: "&4 - Définir (Rapide)",
    systemPrompt: "Fournis et explique la définition du terme suivant, en fournissant des analogies si nécessaire. De plus, réponds aux questions de suivi si demandé :",
    APIModels: "
    (
    gemma3:4b
    )",
    tags: ["&Manipulation de texte", "Apprentissage", "&Général"]
}, {
    promptName: "Prompt personnalisé",
    menuText: "&5 - Prompt personnalisé (Équilibré)",
    systemPrompt: "Tu es un assistant utile. Suis les instructions que je vais fournir ou réponds aux questions que je vais poser.",
    APIModels: "
    (
    gemma3:4b
    )",
    isCustomPrompt: true,
    isAutoPaste: true,
    tags: ["&Prompts personnalisés", "&Collage auto", "&Général"]
}, {
    promptName: "Réponse rapide",
    menuText: "&6 - Réponse rapide (Ultra rapide)",
    systemPrompt: "Fournis une réponse rapide et concise au texte suivant. Sois bref et direct :",
    APIModels: "
    (
    gemma3:4b
    )",
    isCustomPrompt: true,
    tags: ["&Prompts personnalisés", "&Réponses rapides", "&Général"]
}, {
    promptName: "Analyse détaillée",
    menuText: "&7 - Analyse détaillée (Puissant)",
    systemPrompt: "Fournis une analyse approfondie et détaillée du texte suivant. Réfléchis profondément au sujet et fournis des insights complets :",
    APIModels: "
    (
    gemma3:4b
    )",
    isCustomPrompt: true,
    tags: ["&Prompts personnalisés", "&Analyse approfondie", "&Général"]
}, {
    promptName: "Exemple de prompt multiligne",
    menuText: "Exemple de prompt multiligne",
    systemPrompt: "
    (
    Ceci est un prompt décomposé sur plusieurs lignes.

    Voici la deuxième phrase.

    Et la troisième.

    Tant que le prompt est entre guillemets et les parenthèses d'ouverture et de fermeture,

    il sera valide.
    )",
    APIModels: "
    (
    gemma3:4b
    )",
    tags: ["&Exemples"]
}]