# Pi Global Instructions — Synced from Windows

# Project Instructions (CLAUDE.md content)
## Mutsumi Task Integration

This project uses Mutsumi for task management.
Tasks live in `./mutsumi.json` (fallback: `./tasks.json`).

### Schema
- Required: `id` (unique string), `title` (string), `status` ("pending"|"done")
- Optional: `scope` ("day"|"week"|"month"|"inbox"), `priority` ("high"|"normal"|"low"),
  `tags` (string[]), `children` (Task[]), `due_date` (ISO date), `description` (string)
- **Preserve any fields you don't recognize — do NOT delete them**

### CLI (preferred)
- `mutsumi add "title" --priority high --scope day --tags "dev,urgent"`
- `mutsumi done <id-prefix>` / `mutsumi edit <id-prefix> --title "new"`
- `mutsumi rm <id-prefix>` / `mutsumi list`

### Direct JSON
1. Read `./mutsumi.json`  2. Modify tasks array  3. Write ENTIRE file back
4. Atomic write: temp file + `os.rename()`  5. Generate unique ID for new tasks

The Mutsumi TUI watches this file and re-renders automatically on every save.