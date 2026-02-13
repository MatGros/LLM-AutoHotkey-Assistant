# Changelog

All notable changes to this project should be documented in this file.

## [Unreleased]
- fix: migrate references from OpenRouter → OllamaBackend (Response Window and main script)
- fix: ensure `baseURL`/`APIKey` passed to Response Window; instantiate `OllamaBackend` there
- fix: remove conflicting `TraySetIcon` from `lib/Response Window.ahk` and sync tray icon on API health
- docs: update Options menu links (OpenRouter → Ollama/Others)
- chore: add `AUTHORS` and record GPL‑compliance housekeeping items

### Notes for maintainers
- Recommend adding SPDX headers to source files and `LICENSE-COMPLIANCE.md` describing how to obtain Corresponding Source for any binary distribution.
- See commit history for detailed diffs (recent commits: migration and icon-fix).
