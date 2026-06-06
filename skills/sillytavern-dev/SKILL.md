---
name: sillytavern-dev
description: Navigate and develop the SillyTavern (酒馆) AI roleplay frontend. Covers project structure, key modules (frontend/backend/extensions), debugging, character card handling, API connections, and common modification patterns. Use when working with SillyTavern source code, debugging ST issues, or building ST extensions.
---

# SillyTavern Development

SillyTavern is a Node.js + Express + jQuery frontend for AI roleplay/chat. It connects to various LLM backends (OpenAI, Anthropic, Kobold, Ollama, etc.).

## Quick Architecture

```
SillyTavern/
├── server.js              # Express entry point
├── public/                # Frontend (jQuery SPA)
│   ├── index.html         # Main UI shell
│   ├── scripts/           # Frontend JS modules
│   │   ├── ai.js          # Chat completion API client
│   │   ├── characters.js  # Character management
│   │   ├── world-info.js  # World info/lorebook
│   │   ├── extensions.js  # Extension loader
│   │   └── ...
│   └── css/
├── src/                   # Backend modules
│   ├── endpoints/         # API route handlers
│   │   ├── chat-completions.js
│   │   ├── characters.js
│   │   └── ...
│   ├── middleware/
│   └── util.js
├── extensions/            # Third-party extensions (ST-extras, etc.)
├── default/               # Default user content
└── data/                  # User data (runtime)
    └── default-user/
        └── characters/    # Character cards (.png / .json)
```

## Key Modules

### 1. Chat Pipeline (the core of AI roleplay)

```
User sends message
  → extensions.js (format chat) 
  → ai.js (build prompt)
    → world-info.js (inject lorebook entries)
    → characters.js (inject character card data)
  → Backend endpoint (chat-completions.js)
    → LLM API (streaming/completion)
  → Response parsing
  → Streaming display in UI
```

### 2. Character Cards

- Format: PNG with embedded JSON metadata (v2/v3 spec) or standalone JSON
- Key fields: `name`, `description`, `personality`, `scenario`, `first_mes`, `mes_example`, `system_prompt`, `creator_notes`
- Located in `data/default-user/characters/`

### 3. World Info / Lorebook

- Context injection system: triggers on keyword match
- Entry: `key` (trigger words), `content` (injected text), `constant` (always active)
- Selective injection based on recursion depth and position

### 4. Extensions

- Third-party JS loaded from `extensions/` directory
- Most common: ST-extras (expression packs, vector storage, etc.)

## Common Tasks

### Add a new LLM backend
1. Add provider config to `public/scripts/ai.js`
2. Add endpoint in `src/endpoints/`
3. Register streaming vs. non-streaming handler

### Modify prompt construction
Look in `public/scripts/ai.js` → functions like `generatePrompt()`, `buildChatCompletion()`

### Debug streaming issues
Check `public/scripts/ai.js` streaming handler and `src/endpoints/chat-completions.js`

## Development Setup

```bash
cd SillyTavern
npm install
node server.js --listen --enableIPv4  # default: localhost:8000
```

Use browser DevTools (F12) → Network tab to inspect API calls. Frontend logs go to browser console.
