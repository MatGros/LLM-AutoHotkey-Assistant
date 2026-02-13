# Specifications Techniques — LLM AutoHotkey Assistant

## NOTA BENE (UTILISATION)

> **Regle de maintenance :** Si une fonctionnalite (feature) disparait ou est retiree, **ne pas supprimer** son texte ou son ID. A la place, il faut **barrer le texte** (ex: `~~[F-00] Feature obsolete~~`) pour conserver l'historique des specifications.

---

## VUE D'ENSEMBLE

| Champ            | Valeur                                                                               |
| :--------------- | :----------------------------------------------------------------------------------- |
| **Nom**          | LLM AutoHotkey Assistant                                                             |
| **Langage**      | AutoHotkey v2 (>= 2.0.18)                                                           |
| **Plateforme**   | Windows                                                                              |
| **Licence**      | GPL-3.0-only                                                                         |
| **Backend LLM**  | Ollama (local ou cloud, endpoint `/api/chat`)                                        |
| **GUI**          | WebView2 (Bootstrap 5 dark theme) + AHK native (menus, tray, InputWindow)            |
| **Upstream**     | Fork de [kdalanon/LLM-AutoHotkey-Assistant](https://github.com/kdalanon/LLM-AutoHotkey-Assistant) (OpenRouter) |

---

## SOMMAIRE DES FONCTIONNALITES (FEATURES)

> **Legende Origine :** `Fork` = herite du projet upstream (kdalanon) · `Fork+` = herite mais modifie · `Nouveau` = cree dans ce fork  
> **Legende Statut :** ✅ Deploye · 🚧 En cours · 📋 Planifie

| ID       | Feature                  | Description Courte                                                         | Origine   | Statut |
| :------- | :----------------------- | :------------------------------------------------------------------------- | :-------- | :----: |
| **F-01** | Prompt Menu              | Menu contextuel F12 avec prompts personnalisables et sous-menus par tags   | Fork+     | ✅     |
| **F-02** | Response Window          | Fenetre WebView2 affichant la reponse Markdown rendue (code, KaTeX, etc.)  | Fork      | ✅     |
| **F-03** | Multi-Model              | Lancement simultane de plusieurs modeles pour un meme prompt               | Fork      | ✅     |
| **F-04** | Chat Session             | Conversation multi-tours avec historique JSON persistant                   | Fork      | ✅     |
| **F-05** | Auto-Paste               | Collage automatique de la reponse dans l'application active                | Fork      | ✅     |
| **F-06** | Custom Prompts           | Saisie libre via InputWindow avant envoi au modele                         | Fork      | ✅     |
| **F-07** | Ollama Backend           | Classe `OllamaBackend` : cURL → `/api/chat`, auth Bearer optionnelle      | Nouveau   | ✅     |
| **F-08** | Configuration GUI        | GUI de configuration BaseURL / APIKey avec sauvegarde `%AppData%`          | Nouveau   | ✅     |
| **F-09** | Health Check             | Test de connectivite au demarrage avec retour visuel (tray icon)           | Nouveau   | ✅     |
| **F-10** | Dark Mode                | Title bar, menus, MsgBox, tooltips et WebView2 en mode sombre             | Fork      | ✅     |
| **F-11** | Hotkeys                  | F12 (menu), Ctrl+S (reload), Ctrl+W (fermer), CapsLock+F12 (suspend)      | Fork+     | ✅     |
| **F-12** | Tray Icon Sync           | Icone tray reflete l'etat : connecte (IconOn) / erreur (IconOff)          | Nouveau   | ✅     |
| **F-13** | Loading Cursor           | Curseur systeme "working in background" pendant les requetes               | Fork      | ✅     |
| **F-14** | Tooltip Tracking         | Tooltip suivant la souris listant les prompts en cours de chargement       | Fork      | ✅     |
| **F-15** | Send to All              | Envoi d'un message a toutes les Response Windows actives simultanement     | Fork      | ✅     |
| **F-16** | Send to Group            | Envoi d'un message cible aux fenetres d'un prompt specifique               | Fork      | ✅     |
| **F-17** | Chat History View        | Basculement Chat History / Latest Response dans la Response Window         | Fork      | ✅     |
| **F-18** | Copy Response            | Copie HTML riche ou Markdown brut selon la configuration du prompt         | Fork      | ✅     |
| **F-19** | Retry                    | Relance de la derniere requete (supprime la derniere reponse assistant)    | Fork      | ✅     |
| **F-20** | Window Layout            | Positionnement automatique des Response Windows (1/2/3/n modeles)         | Fork      | ✅     |
| **F-21** | Tag Submenus             | Organisation des prompts en sous-menus par tags (`&General`, `&Fast`, …)  | Fork      | ✅     |
| **F-22** | Script Suspend           | Barre jaune "Suspended" en bas d'ecran + icone tray modifiee              | Fork+     | ✅     |
| **F-23** | Inter-Process Messaging  | Communication main ↔ Response Windows via `PostMessage` (WM_USER+)       | Fork      | ✅     |

---

## DETAIL DES FEATURES

### [F-01] Prompt Menu (F12) — `Fork+`

- Declenchement par la touche **F12** (upstream utilisait la touche backtick).
- Construction dynamique a partir du tableau `prompts` defini dans `Prompts.ahk`.
- Sous-menus par tags si le prompt possede une propriete `tags`.
- Ajout automatique des menus "Send message to", "Activate", "Minimize", "Close" pour les Response Windows actives.
- Menu "Options" : edition des prompts (Notepad) et lien Ollama library.

### [F-02] Response Window (WebView2)

- Chaque modele s'ouvre dans un script separe (`lib/Response Window.ahk`) lance par `Run()`.
- GUI basee sur **WebView2** (via `WebViewToo.ahk`) affichant du HTML/CSS.
- Rendu Markdown via **markdown-it** avec plugins :
  - `highlight.js` — coloration syntaxique du code.
  - `texmath` + `KaTeX` — equations mathematiques.
- Boutons : **Chat**, **Copy**, **Retry**, **Chat History / Latest Response**, **Close**.
- Dark mode applique via `DwmSetWindowAttribute` (title bar) + Bootstrap `data-bs-theme="dark"`.

### [F-03] Multi-Model Support

- Un prompt peut lister plusieurs modeles dans `APIModels` (separes par des virgules ou des retours a la ligne).
- Chaque modele est lance dans sa propre Response Window.
- Positionnement automatique :
  - 1 modele → centre ecran.
  - 2 modeles → cote a cote.
  - 3 modeles → repartition horizontale.
  - 4+ modeles → stack avec offset vertical.
- `isAutoPaste` est desactive automatiquement si plus d'un modele.

### [F-04] Chat Session

- Historique JSON (`chatHistoryJSONRequestFile`) contenant le tableau `messages` (system, user, assistant).
- Ajout de messages via `router.appendToChatHistory()`.
- Suppression du dernier assistant via `router.removeLastAssistantMessage()` (pour Retry).
- Fichier temporaire dans `A_Temp`, supprime a la fermeture de la fenetre.

### [F-05] Auto-Paste

- Si `isAutoPaste: true` dans le prompt, la reponse est copiee dans `A_Clipboard` et collee via `Send("^v")`.
- La Response Window se ferme automatiquement apres le collage.

### [F-06] Custom Prompts

- Si `isCustomPrompt: true`, une `InputWindow` s'ouvre pour saisir un texte libre.
- Le texte saisi est concatene au texte copie (`customPromptMessage \n\n clipboard`).
- Support d'un message initial optionnel (`customPromptInitialMessage`).

### [F-07] Ollama Backend (`OllamaBackend`) — `Nouveau`

> Remplace la classe `OpenRouter` du projet upstream.

- **Fichier :** `lib/Config.ahk`
- **Constructeur :** `OllamaBackend(BaseURL, APIKey := "")`
- **Commande cURL :** `cURL.exe -s -X POST "{BaseURL}/api/chat" [-H "Authorization: Bearer {APIKey}"] -H "Content-Type: application/json" -d @"{input}" -o "{output}"`
- **createJSONRequest()** : construit le JSON Ollama (model, stream: false, messages).
- **extractJSONResponse()** : supporte 3 formats :
  1. Ollama natif (`message.content`)
  2. Ollama generate (`response`)
  3. OpenAI-compatible (`choices[0].message.content`)
- **extractErrorResponse()** : extrait le champ `error` Ollama.
- **buildcURLCommand()** : genere la commande cURL complete.
- **appendToChatHistory()** / **getMessages()** / **removeLastAssistantMessage()** : gestion de l'historique.

### [F-08] Configuration GUI — `Nouveau`

> Upstream exigeait de coller la cle API directement dans le source. Ce fork introduit une GUI de configuration et un stockage securise.

- **Fichier :** `Prompts.ahk` → fonction `loadOllamaConfig()`
- **Ordre de precedence :**
  1. Variables d'environnement `LLM_AHK_BASE_URL` / `LLM_AHK_API_KEY`
  2. Fichier JSON `%AppData%\LLM-AutoHotkey-Assistant\ollama_config.json`
  3. GUI interactive (Radio Local/Cloud, champs URL et API Key, option Save)
- **Mode Local :** `http://localhost:11434` (API Key desactivee)
- **Mode Cloud :** URL et API Key personnalisables
- **Reset :** menu tray "Reset Configuration" → supprime le fichier JSON et relance.

### [F-09] Health Check (Startup) — `Nouveau`

- Appel `quickAPIHealthCheck()` au demarrage via `SetTimer(..., -10)`.
- Envoie un prompt minimal ("hi") au premier modele configure.
- Timeout de 8 secondes.
- Resultat :
  - **OK →** `TrayTip` de confirmation + `IconOn.ico`
  - **Echec →** `MsgBox` d'erreur + `IconOff.ico`
- Mode mock (`LLM_AHK_TEST_MODE=mock` ou menu tray "Test API") : skip la requete reelle.

### [F-10] Dark Mode

- **Title bar :** `DwmSetWindowAttribute(hWnd, 20, true, 4)` pour toutes les fenetres.
- **Menus :** `Dark_Menu.ahk` — hook sur les menus natifs Windows.
- **MsgBox / InputBox :** `Dark_MsgBox.ahk`.
- **Tooltips :** `SystemThemeAwareToolTip.ahk`.
- **InputWindow :** `BackColor := "0x212529"`, police blanche, theme `DarkMode_Explorer`.
- **WebView2 :** Bootstrap `data-bs-theme="dark"`, CSS `custom.css`, `atom-one-dark.min.css`.

### [F-11] Hotkeys — `Fork+`

> Upstream utilisait la touche backtick (`` ` ``) ; ce fork utilise **F12** pour eviter les conflits avec la saisie de texte.

| Raccourci         | Action                                           | Changement vs upstream      |
| :---------------- | :----------------------------------------------- | :-------------------------- |
| `F12`             | Afficher le menu des prompts                     | Remplace backtick (`` ` ``) |
| `Ctrl+S`          | Sauver et recharger (si `Prompts.ahk` est actif) | Inchange                    |
| `Ctrl+W`          | Fermer la fenetre active (Input ou Response)     | Inchange                    |
| `CapsLock + F12`  | Suspendre / reprendre les hotkeys                | Remplace CapsLock+backtick  |
| `Esc`             | Annuler la requete cURL en cours                 | Inchange                    |

### [F-12] Tray Icon Sync — `Nouveau`

- `IconOn.ico` — etat normal, API connectee.
- `IconOff.ico` — erreur API ou script suspendu.
- Mise a jour automatique apres le health check et lors du toggle suspend.

### [F-13] Loading Cursor

- Pendant une requete : curseur systeme remplace par "working in background" (ID 32650).
- Restauration automatique via `SystemParametersInfo(0x57)` a la fin.

### [F-14] Tooltip Tracking

- `ToolTipEx()` affiche un tooltip suivant la souris avec la liste des prompts en chargement.
- Format : `Retrieving response for the following prompt(s) (Press ESC to cancel):\n- PromptName [model]`
- Disparait automatiquement quand toutes les requetes sont terminees.

### [F-15] Send to All Models

- Menu "Send message to → All" (visible si > 1 Response Window active).
- `InputWindow` dediee ("Send message to all").
- Ajoute le message utilisateur au JSON de chaque fenetre via `router.appendToChatHistory()`.
- Notifie chaque Response Window via `PostMessage(WM_SEND_TO_ALL_MODELS)`.

### [F-16] Send to Group

- Menu "Send message to → [PromptName]".
- Envoie le message uniquement aux fenetres dont `modelData.promptName` correspond.

### [F-17] Chat History View

- Bouton "Chat History" / "Latest Response" dans la Response Window.
- Bascule entre la vue complete de la conversation et la derniere reponse.
- Format Chat History : `🔧 System Prompt` → `🔵 You` → `🟡 ModelName` → …

### [F-18] Copy Response

- Bouton "Copy" dans la Response Window.
- Si `copyAsMarkdown: true` → copie le texte Markdown brut via `A_Clipboard`.
- Sinon → copie le HTML rendu via `navigator.clipboard.write()` (`text/html` + `text/plain`).
- Feedback visuel : bouton affiche "Copied!" pendant 2 secondes.

### [F-19] Retry

- Bouton "Retry" dans la Response Window.
- Supprime la derniere reponse assistant de l'historique JSON.
- Relance la requete cURL avec le meme contexte.

### [F-20] Window Layout

- Calcul automatique de la position (`X`, `Y`, `W`, `H`) en fonction du nombre de modeles et de l'index courant.
- Dimensions par defaut : 600×600 px.
- Flash de la fenetre si elle est en arriere-plan ou minimisee.

### [F-21] Tag Submenus

- Propriete `tags` (tableau de strings) sur chaque prompt.
- Chaque tag unique cree un sous-menu dans le Prompt Menu.
- Un prompt sans tags est ajoute directement au menu racine.
- Convention : prefixe `&` pour acces clavier (ex: `&General`, `&Custom prompts`).

### [F-22] Script Suspend — `Fork+`

- Toggle via `CapsLock + F12` (upstream : `CapsLock + backtick`).
- Affiche une barre jaune "LLM AutoHotkey Assistant Suspended" en bas d'ecran.
- Desactive CapsLock apres l'action (`SetCapsLockState "Off"`).
- Icone tray passe a `IconOff.ico`.

### [F-23] Inter-Process Messaging

- Communication entre le script principal et les Response Windows via `PostMessage` / `OnMessage`.
- Messages personnalises (base `WM_USER + 123`) :
  - `WM_RESPONSE_WINDOW_OPENED` (0x400+125)
  - `WM_RESPONSE_WINDOW_CLOSED` (0x400+126)
  - `WM_SEND_TO_ALL_MODELS` (0x400+127)
  - `WM_RESPONSE_WINDOW_LOADING_START` (0x400+123)
  - `WM_RESPONSE_WINDOW_LOADING_FINISH` (0x400+124)
- La classe `CustomMessages` centralise l'enregistrement et l'envoi.

---

## ARCHITECTURE

### Fichiers principaux

| Fichier                              | Role                                                        |
| :----------------------------------- | :---------------------------------------------------------- |
| `LLM AutoHotkey Assistant.ahk`       | Script principal : hotkeys, menus, orchestration            |
| `Prompts.ahk`                        | Configuration Ollama + definition des prompts               |
| `lib/Config.ahk`                     | Classes `OllamaBackend`, `InputWindow`, `CustomMessages`    |
| `lib/Response Window.ahk`            | Sous-script : GUI WebView2, execution cURL, rendu reponse  |
| `Response Window resources/index.html` | Template HTML de la Response Window                       |
| `Response Window resources/js/main.js` | Rendu Markdown, gestion des boutons cote JavaScript       |

### Bibliotheques tierces (`lib/`)

| Fichier                    | Role                                              |
| :------------------------- | :------------------------------------------------ |
| `WebViewToo.ahk`           | Wrapper AHK pour Microsoft WebView2               |
| `WebView2.ahk`             | Bindings COM WebView2                              |
| `jsongo.v2.ahk`            | Parsing / Stringify JSON                           |
| `AutoXYWH.ahk`             | Redimensionnement automatique des controles GUI    |
| `ToolTipEx.ahk`            | Tooltip avance avec suivi souris et drag           |
| `Dark_MsgBox.ahk`          | Mode sombre pour MsgBox / InputBox                 |
| `Dark_Menu.ahk`            | Mode sombre pour les menus natifs                  |
| `SystemThemeAwareToolTip.ahk` | Tooltips respectant le theme systeme            |

### Flux de donnees (requete LLM)

```
[Utilisateur]
     │   F12 → selectionne un prompt
     ▼
[LLM AutoHotkey Assistant.ahk]
     │   1. Copie le texte selectionne (Ctrl+C)
     │   2. Cree le JSON request via OllamaBackend.createJSONRequest()
     │   3. Ecrit les fichiers temporaires (JSON, cURL command)
     │   4. Lance "lib/Response Window.ahk" avec le chemin du fichier data
     ▼
[Response Window.ahk]
     │   1. Lit les parametres depuis le fichier JSON temporaire
     │   2. Instancie OllamaBackend(baseURL, APIKey)
     │   3. Execute la commande cURL en arriere-plan
     │   4. Attend la fin du processus cURL
     │   5. Parse la reponse JSON (extractJSONResponse)
     │   6. Rend le Markdown via WebView2 (markdown-it + highlight.js + KaTeX)
     ▼
[Response Window - WebView2 GUI]
     │   Affiche la reponse formatee
     │   Boutons : Chat / Copy / Retry / Chat History / Close
     ▼
[Utilisateur]
     Chat, Copy, Retry ou Close
```

---

## CONFIGURATION DES PROMPTS (Prompts.ahk)

Chaque prompt est un objet avec les proprietes suivantes :

| Propriete                   | Type       | Requis | Description                                      |
| :-------------------------- | :--------- | :----- | :----------------------------------------------- |
| `promptName`                | String     | Oui    | Identifiant unique du prompt                     |
| `menuText`                  | String     | Oui    | Texte affiche dans le menu (avec `&` pour raccourci) |
| `systemPrompt`              | String     | Oui    | Prompt systeme envoye au modele                  |
| `APIModels`                 | String     | Oui    | Modele(s) Ollama, separes par virgules/newlines  |
| `tags`                      | Array      | Non    | Tags pour sous-menus (ex: `["&General"]`)        |
| `isCustomPrompt`            | Boolean    | Non    | Ouvre une InputWindow avant envoi                 |
| `customPromptInitialMessage` | String    | Non    | Message pre-rempli dans l'InputWindow            |
| `isAutoPaste`               | Boolean    | Non    | Colle automatiquement la reponse                 |
| `copyAsMarkdown`            | Boolean    | Non    | Copie en Markdown brut au lieu de HTML           |
| `skipConfirmation`          | Boolean    | Non    | Pas de confirmation a la fermeture               |

---

## PREREQUIS

- **AutoHotkey v2** >= 2.0.18
- **Windows** (10 ou 11)
- **WebView2 Runtime** (inclus dans Windows 11, installable sur Windows 10)
- **Ollama** installe et accessible (local `http://localhost:11434` ou cloud)
- **cURL** (inclus dans Windows 10+)

---

## HISTORIQUE DES MODIFICATIONS (CHANGELOG)

Ce fork est base sur le tag **v2.0.0** du projet upstream [kdalanon/LLM-AutoHotkey-Assistant](https://github.com/kdalanon/LLM-AutoHotkey-Assistant).

### v2.0.1 — 2026-02-13

| Type   | Description                                                                                          |
| :----- | :--------------------------------------------------------------------------------------------------- |
| fix    | Migration complete de toutes les references OpenRouter → OllamaBackend (Response Window, main script) |
| feat   | `OllamaBackend` : nouvelle classe remplacant `OpenRouter` (`lib/Config.ahk`)                         |
| feat   | GUI de configuration Ollama (BaseURL / APIKey) avec sauvegarde `%AppData%` (`Prompts.ahk`)            |
| feat   | Health check au demarrage avec retour visuel (tray icon, TrayTip)                                    |
| feat   | Synchronisation de l'icone tray avec l'etat de l'API (IconOn / IconOff)                              |
| fix    | `baseURL` et `APIKey` transmis a la Response Window via `responseWindowDataObj`                       |
| fix    | Suppression du `TraySetIcon` en doublon dans `lib/Response Window.ahk`                               |
| change | Hotkey principal : backtick → F12 ; CapsLock+backtick → CapsLock+F12                                |
| change | Menu Options : liens OpenRouter remplaces par lien Ollama library                                    |
| change | Messages d'erreur 401/402 : references OpenRouter retirees                                           |
| chore  | Ajout de `AUTHORS`, `CHANGELOG.md` (fusionne dans `SPEC.md`), `.gitignore`                           |
| chore  | Aide (Help dialog) traduite en francais                                                              |

### Notes pour les mainteneurs

- Recommande : ajouter des en-tetes SPDX aux fichiers sources.
- Recommande : creer `LICENSE-COMPLIANCE.md` decrivant comment obtenir le Corresponding Source pour toute distribution binaire.
- Voir l'historique git pour les diffs detailles.
