---
name: codebase-analysis
description: Systematic methodology for rapidly understanding unfamiliar codebases. Covers search strategies, dependency mapping, entry-point tracing, architecture recognition, and documentation generation. Use when first encountering a new project (like SillyTavern, pi, or Claude Code) and needing to build a mental model quickly.
---

# Codebase Analysis Methodology

## Phase 1: Landscape Survey (5-10 min)

### 1.1 Top-level scan
```bash
ls -la                    # Root structure
find . -maxdepth 2 -type f -name "*.json" | head -20  # Config files
find . -maxdepth 1 -type f | head -20                   # Root files
```

What to look for:
- `package.json` / `Cargo.toml` / `go.mod` → language + dependencies
- `README.md` / `CONTRIBUTING.md` → project intent
- `tsconfig.json` / `.babelrc` / `vite.config.*` → build system
- `docker-compose.yml` / `Dockerfile` → deployment
- `.gitignore` → generated vs. source files

### 1.2 Entry points
```bash
grep -rn '"main"' package.json  # Node
grep -rn 'entry' webpack.config.* vite.config.*  # Bundler
# Look for: server.js, main.ts, index.ts, app.py, main.go
```

### 1.3 Directory structure tree
```bash
find . -type d -not -path '*/node_modules/*' -not -path '*/.git/*' | sort
```

## Phase 2: Architecture Recognition

### Pattern 1: MVC / Layered
```
src/
├── controllers/  → HTTP handlers
├── models/       → Data layer
├── views/        → Templates
└── services/     → Business logic
```

### Pattern 2: Feature-based
```
src/
├── features/
│   ├── auth/     → Everything auth-related
│   ├── chat/     → Everything chat-related
│   └── billing/
└── shared/       → Cross-cutting concerns
```

### Pattern 3: Plugin/Extension Architecture
```
src/
├── core/         → Extension host
├── extensions/   → Pluggable modules
└── api/          → Extension API surface
```

### Identifying the pattern
```bash
# Find the most important files by import count
rg -l "import.*from" src/ | head -20

# Find shared utilities (high fan-in)
rg "from.*utils" src/ --stats

# Find key abstractions (interfaces/types)
rg "^export (interface|type|abstract class)" src/ -l
```

## Phase 3: Data Flow Tracing

### Trace a single user action end-to-end
1. Start from UI event or API endpoint
2. Follow the call chain: handler → service → model/db
3. Note middleware/side-effects along the way
4. Document the return path

### Quick tracing commands
```bash
# Find where a function/class is defined
rg "export (function|class|const) targetName" --type ts

# Find all callers
rg "targetFunction\(" --type ts

# Find all implementations of an interface
rg "implements TargetInterface" --type ts
```

## Phase 4: Key Files Documentation

For each key module found, document:
- **Purpose**: What problem does it solve?
- **Input/Output**: What data flows in/out?
- **Dependencies**: What does it depend on?
- **Dependents**: What depends on it?
- **Gotchas**: Any surprises found while reading?

## Phase 5: Build and Run

```bash
# Node.js
npm install && npm run dev

# Python
pip install -r requirements.txt && python main.py

# Go
go run .
```

Then interact with the running system:
- Check browser DevTools Network tab for API calls
- Note the actual API endpoints being called
- Observe the data shapes in requests/responses

## Common Anti-patterns to Document

- Global mutable state (debugging nightmare)
- Implicit dependencies (not in imports but assumed to exist)
- Magic strings/numbers without constants
- Race conditions in async code
- Missing error handling in critical paths

## Tool Reference

| Tool | Command | Use Case |
|------|---------|----------|
| ripgrep | `rg "pattern" --type ts` | Search codebase |
| find | `find . -name "*.ts" -not -path "*/node_modules/*"` | Find files |
| git | `git log --oneline -20` | Recent changes |
| git | `git log --format="%an" \| sort \| uniq -c \| sort -rn` | Active contributors |
| cloc | `npx cloc src/` | Lines of code per language |
| madge | `npx madge --image graph.png src/index.ts` | Dependency graph |
