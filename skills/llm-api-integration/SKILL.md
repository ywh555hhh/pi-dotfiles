---
name: llm-api-integration
description: Patterns and best practices for integrating with LLM APIs (OpenAI, Anthropic, Google, local). Covers Chat Completions, streaming, tool calling, token estimation, error handling, rate limiting, and provider abstraction. Use when building or debugging LLM API clients, adding new providers to SillyTavern, or working with AI roleplay infrastructure.
---

# LLM API Integration

## Provider API Comparison

| Feature | OpenAI | Anthropic | Google (Gemini) | KoboldCPP | Ollama |
|---------|--------|-----------|-----------------|-----------|--------|
| Protocol | REST + SSE | REST + SSE | REST + SSE | REST + SSE | REST |
| Streaming | SSE | SSE | SSE | SSE | NDJSON |
| Tool calling | Native | Native | Native | Limited | Limited |
| Vision | GPT-4o+ | Claude 3+ | Gemini all | No | Some |
| Max context | 128K-200K | 200K | 1M+ | Configurable | Configurable |

## Common API Patterns

### Chat Completion (OpenAI format - de facto standard)
```typescript
const response = await fetch("https://api.openai.com/v1/chat/completions", {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Authorization": `Bearer ${apiKey}`
  },
  body: JSON.stringify({
    model: "gpt-4o",
    messages: [
      { role: "system", content: "You are a helpful assistant." },
      { role: "user", content: "Hello!" }
    ],
    temperature: 0.7,
    stream: true
  })
});
```

### Streaming Response Parsing (SSE)
```typescript
const reader = response.body.getReader();
const decoder = new TextDecoder();
let buffer = "";

while (true) {
  const { done, value } = await reader.read();
  if (done) break;
  
  buffer += decoder.decode(value, { stream: true });
  const lines = buffer.split("\n");
  buffer = lines.pop() || "";  // Keep incomplete line
  
  for (const line of lines) {
    if (line.startsWith("data: ")) {
      const data = line.slice(6);
      if (data === "[DONE]") return;
      const chunk = JSON.parse(data);
      const delta = chunk.choices[0]?.delta?.content;
      if (delta) onToken(delta);
    }
  }
}
```

### Anthropic Messages API
```typescript
const response = await fetch("https://api.anthropic.com/v1/messages", {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "x-api-key": apiKey,
    "anthropic-version": "2023-06-01"
  },
  body: JSON.stringify({
    model: "claude-sonnet-4-20250514",
    max_tokens: 1024,
    system: "You are a helpful assistant.",
    messages: [{ role: "user", content: "Hello!" }]
  })
});
```

## Provider Abstraction Pattern

SillyTavern uses a provider adapter pattern. Key interface:

```typescript
interface TextCompletionProvider {
  name: string;
  sendMessage(params: CompletionParams): AsyncGenerator<string>;
  getModels?(): Promise<Model[]>;
  checkConnection?(): Promise<boolean>;
}

interface CompletionParams {
  messages: Message[];
  model: string;
  temperature: number;
  maxTokens: number;
  stop: string[];
  stream: boolean;
  // Provider-specific extras:
  topP?: number;
  frequencyPenalty?: number;
  presencePenalty?: number;
}
```

## Error Handling

```typescript
try {
  const response = await fetch(apiUrl, options);
  
  if (response.status === 429) {
    // Rate limited - exponential backoff
    const retryAfter = response.headers.get("Retry-After");
    await sleep(parseInt(retryAfter || "5") * 1000);
    return retry();
  }
  
  if (response.status === 401 || response.status === 403) {
    throw new AuthError("Invalid or expired API key");
  }
  
  if (!response.ok) {
    const body = await response.text();
    throw new ApiError(response.status, body);
  }
  
  return parseStream(response.body);
} catch (e) {
  if (e.name === "AbortError") {
    // User cancelled
    return;
  }
  throw e;
}
```

## Token Estimation (approximate)

```
English text: ~1.3 tokens per word
Code: ~0.5 tokens per character
1 token ≈ 4 characters (English) or ¾ word
```

For accurate counting, use `tiktoken` (OpenAI models) or provider-specific tokenizers.
