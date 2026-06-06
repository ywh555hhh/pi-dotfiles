---
name: pi-extension-dev
description: Develop extensions for the pi coding agent. Covers extension architecture, lifecycle hooks, custom tools, slash commands, TUI overlay components, RPC integration, and packaging. Use when building or modifying pi extensions, creating custom tools, or integrating external services into pi.
---

# Pi Extension Development

## Extension Structure (minimal)

```typescript
// my-extension.ts
import type { Pi } from "@earendil-works/pi-coding-agent";

export default function activate(pi: Pi) {
  // Register hooks, tools, commands, UI here
}
```

## Lifecycle Hooks

### Core hooks
```typescript
pi.on("tool:before", async (event) => {
  // Intercept tool calls before execution
  // Can modify, block, or log tool invocations
});

pi.on("tool:after", async (event) => {
  // React to completed tool calls
});

pi.on("message:before", async (event, ctx) => {
  // Modify outgoing messages (to model)
});

pi.on("message:after", async (event, ctx) => {
  // Process incoming messages (from model)
});

pi.on("session:before_compact", async (event) => {
  // Custom compaction logic
});

pi.on("session:before_tree", async (event) => {
  // Custom branch summarization
});
```

Full hook reference: see `docs/extensions.md`

## Custom Tools

```typescript
pi.addTool({
  name: "my_tool",
  description: "What this tool does and when to use it",
  parameters: {
    type: "object",
    properties: {
      query: { type: "string", description: "Search query" }
    },
    required: ["query"]
  },
  async handler(params, ctx) {
    // params: validated against schema
    // ctx: tool context (session, signal, etc.)
    return "Tool result string";
  }
});
```

## Slash Commands

```typescript
pi.addCommand({
  name: "mycommand",
  description: "My custom command",
  async handler(args, ctx) {
    // args: string after /mycommand
    return "Command output";
  }
});
```

## TUI Components

Extensions can render custom UI. See `docs/tui.md` for the full component API.

### Overlay example
```typescript
pi.addOverlay({
  id: "my-overlay",
  render: (props) => ({
    type: "box",
    children: [
      { type: "text", content: "Hello from overlay!" }
    ]
  })
});
```

## Key Extension Examples (see examples/extensions/)

| File | What it demonstrates |
|------|---------------------|
| `todo.ts` | Custom tool with persistent state |
| `custom-compaction.ts` | Override compaction with custom model |
| `minimal-mode.ts` | Complex UI overlay |
| `interactive-shell.ts` | Bash integration |
| `bookmark.ts` | Stateful command |
| `confirm-destructive.ts` | Safety gate on tool calls |
| `tools.ts` | Multiple custom tools registration |
| `handoff.ts` | Session handoff between agents |

## Packaging for distribution

See `docs/packages.md` for pi package format. Key files:
- `package.json` with `pi.extensions`, `pi.skills`, `pi.prompts`, `pi.themes`
- Extension .ts files (loaded as ES modules)
