# Gemini-OpenAI Bridge

A transparent translation layer that enables qwen-code (Gemini-based) to work with OpenAI-compatible APIs like Ollama.

[![Test Coverage](https://img.shields.io/badge/coverage-93.61%25-brightgreen)](./coverage)
[![Tests](https://img.shields.io/badge/tests-10%20passing-brightgreen)](#testing)

## Problem Statement

The qwen-code CLI is forked from Google's Gemini CLI and sends requests in a hybrid Gemini/OpenAI format that includes:
- Gemini-specific fields (`generationConfig`, `safetySettings`, etc.)
- Excessive token requests (often 200,000+ tokens)
- Different message format structures

This causes 400 errors when connecting to pure OpenAI-compatible servers like Ollama.

## Solution

This bridge acts as a middleware that:
1. Intercepts requests from qwen-code
2. Removes Gemini-specific fields
3. Fixes unreasonable values (token limits)
4. Forwards clean OpenAI-format requests
5. Returns responses qwen-code understands

## Architecture

```
qwen-code → Bridge (port 8080) → Ollama/OpenAI (your server)
         ↓
    [Gemini format]
         ↓
    [Translation]
         ↓
    [OpenAI format]
```

## Configuration

Set these environment variables:

- `USE_GEMINI_BRIDGE=true` - Enable the bridge
- `BRIDGE_TARGET_URL` - Where to forward requests (defaults to OPENAI_BASE_URL)
- `BRIDGE_PORT` - Bridge listening port (default: 8080)
- `BRIDGE_DEBUG=true` - Enable debug logging

## Quick Start

1. **Enable in your .env file:**
```bash
USE_GEMINI_BRIDGE=true
OPENAI_BASE_URL=http://your-ollama-server:11434/v1
BRIDGE_TARGET_URL=http://your-ollama-server:11434/v1
BRIDGE_PORT=8080
OPENAI_API_KEY=your-api-key
OPENAI_MODEL=qwen3-coder:latest
GEMINI_DEFAULT_AUTH_TYPE=openai
```

2. **Start the container:**
```bash
docker compose up -d
```

3. **The bridge automatically starts and qwen-code connects through it**

## Testing

```bash
# Run unit tests
npm test

# Run with coverage
npm run test:coverage

# Run in watch mode during development
npm run test:watch
```

### Test Results
- ✅ **10/10 tests passing**
- ✅ **93.61% code coverage**
- ✅ **100% function coverage**

## API Compatibility

### Supported Transformations

| Gemini Field | OpenAI Equivalent | Action |
|--------------|-------------------|--------|
| `generationConfig.temperature` | `temperature` | Extracted |
| `generationConfig.maxOutputTokens` | `max_tokens` | Extracted & capped |
| `systemInstruction` | System message | Converted |
| `safetySettings` | - | Removed |
| `tools` | - | Removed |
| `toolConfig` | - | Removed |
| `max_tokens: 229018` | `max_tokens: 4096` | Capped at reasonable limit |

### Request Example

**Input (from qwen-code):**
```json
{
  "model": "qwen3-coder:latest",
  "messages": [{"role": "user", "content": "Hello"}],
  "max_tokens": 229018,
  "generationConfig": {
    "temperature": 0.7,
    "maxOutputTokens": 8192
  },
  "safetySettings": [{"category": "HARM", "threshold": "HIGH"}],
  "systemInstruction": {
    "parts": [{"text": "You are a helpful assistant."}]
  }
}
```

**Output (to Ollama):**
```json
{
  "model": "qwen3-coder:latest",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Hello"}
  ],
  "max_tokens": 4096,
  "temperature": 0.7
}
```

## Debugging

### Enable Debug Mode
```bash
BRIDGE_DEBUG=true docker-compose up
```

### Check Bridge Health
```bash
curl http://localhost:8080/health
```

Expected response:
```json
{
  "status": "healthy",
  "bridge": "gemini-openai-bridge",
  "target": "http://your-server:8443/v1",
  "uptime": 123.45
}
```

### Test Direct Connection
```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-api-key" \
  -d '{
    "model": "qwen3-coder:latest",
    "messages": [{"role": "user", "content": "Hello"}],
    "generationConfig": {"temperature": 0.7}
  }'
```

## Performance

- **Latency**: +5-10ms per request
- **Memory**: ~50MB RAM usage
- **Throughput**: Handles concurrent requests
- **Streaming**: Supports Server-Sent Events (SSE)

## Development

### Running Tests
```bash
# Install dependencies
npm install

# Run tests once
npm test

# Run tests with coverage
npm run test:coverage

# Watch mode for development
npm run test:watch
```

### Adding Features

This project follows **Test-Driven Development (TDD)**:

1. 🔴 **RED**: Write a failing test
2. 🟢 **GREEN**: Write minimal code to pass
3. 🔵 **REFACTOR**: Improve while keeping tests green

Example:
```javascript
// 1. Write failing test
test('should handle new Gemini field', () => {
    const request = { newGeminiField: 'value' };
    const result = cleanRequest(request);
    expect(result.newGeminiField).toBeUndefined();
});

// 2. Make it pass
function cleanRequest(req) {
    delete req.newGeminiField;
    return req;
}

// 3. Refactor for all cases
```

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for common issues and solutions.

## License

MIT