# Claude Code Configuration

## Project Scope
- **Root Directory**: `D:\MGS\DEV\LLM-AutoHotkey-Assistant`
- **Project Name**: LLM-AutoHotkey-Assistant

## Safety Rules

### ❌ FORBIDDEN OPERATIONS
- **NO file deletion** outside of this project
- **NO file modification** outside of this project directory
- **NO execution** of dangerous system commands (rm -rf, format, etc.)

### ✅ ALLOWED OPERATIONS
- Read/write files **within** this project only
- Create new files in project directories
- Execute safe scripts and commands
- Modify configuration files within the project

## Boundaries
```
PROTECTED (Cannot modify):
├── C:\
├── C:\Windows\**
├── C:\Program Files\**
├── D:\MGS\
├── D:\MGS\DEV\
└── ..\ (parent directories)

ALLOWED (Can modify):
└── D:\MGS\DEV\LLM-AutoHotkey-Assistant\
    ├── *.js, *.py, *.ahk files
    ├── config files
    ├── node_modules
    └── project subdirectories
```

## Guidelines
1. Always ask for confirmation before destructive operations
2. Keep all work within the project directory
3. Never modify files outside this scope
4. Validate all file operations before executing

---
**Version**: 1.0.0
**Last Updated**: 2026-02-14
