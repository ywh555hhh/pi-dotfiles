---
name: typescript-tooling
description: TypeScript and Node.js project configuration and tooling reference. Covers tsconfig best practices, ESM vs CJS modules, testing frameworks (Jest/Vitest), linting, formatting, npm publishing, and monorepo patterns. Use when setting up, debugging, or modernizing TypeScript projects including pi extensions, SillyTavern modules, or any Node.js codebase.
---

# TypeScript & Node.js Tooling

## tsconfig.json Best Practices

### Modern Node.js (ESM)
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "outDir": "dist",
    "rootDir": "src",
    "declaration": true,
    "sourceMap": true
  },
  "include": ["src"],
  "exclude": ["node_modules", "dist", "**/*.test.ts"]
}
```

### Key Compiler Options
| Option | When to use |
|--------|-------------|
| `strict: true` | Always. Catches null/undefined bugs |
| `noUncheckedIndexedAccess` | Adds undefined to indexed access types |
| `exactOptionalPropertyTypes` | Stricter optional property checks |
| `noUnusedLocals` | Clean code, but annoying during prototyping |
| `paths` | Monorepo path aliases (needs runtime resolver) |

## ESM vs CJS

### ESM (Modern)
```typescript
// package.json: "type": "module"
import { foo } from "./bar.js";  // Note: .js extension required
export default function() {}
```

### CJS (Legacy - what SillyTavern uses)
```typescript
// package.json: "type": "commonjs" or not set
const { foo } = require("./bar");
module.exports = function() {};
```

### Dual publishing (both ESM + CJS)
```json
{
  "exports": {
    ".": {
      "import": "./dist/index.mjs",
      "require": "./dist/index.cjs"
    }
  }
}
```

## Testing

### Vitest (recommended for new projects)
```bash
npm install -D vitest
```
```typescript
// vitest.config.ts
import { defineConfig } from "vitest/config";
export default defineConfig({
  test: { globals: true }
});
```

### Jest (what many existing projects use)
```typescript
// jest.config.ts
export default {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/src"],
};
```

## Linting & Formatting

```bash
# Essential setup
npm install -D eslint prettier eslint-config-prettier

# Run
npx eslint src/ --fix
npx prettier src/ --write
```

## Debugging Node.js

```bash
# Attach debugger
node --inspect-brk server.js
# Then open chrome://inspect in Chrome

# Quick inspect
node --inspect server.js
```

## npm Publishing Checklist

1. `"files"` in package.json to whitelist dist/
2. `"main"` / `"exports"` point to compiled output
3. `.npmignore` or `"files"` excludes src/, tests, config
4. `prepublishOnly` script runs build + test
5. `CHANGELOG.md` updated
6. `npm pack --dry-run` to verify contents

## Common Pi/SillyTavern Patterns

### Pi Extension Module Format
```typescript
// Extensions use ESM
export default function activate(pi: Pi) { ... }
```

### SillyTavern Module Format
```typescript
// ST uses CommonJS with jQuery globals
const { something } = require("../other-module");
// jQuery is global: $("#id").on("click", ...)
```
