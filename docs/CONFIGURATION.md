# ⚙️ Configuration Guide

[← Back to README](../README.md) | [Troubleshooting →](TROUBLESHOOTING.md)

This guide covers all configuration options for Qwen-Code Docker, from basic setup to advanced configurations.

## 📋 Table of Contents

- [Quick Setup](#quick-setup)
- [Environment Variables](#environment-variables)
- [Provider-Specific Setup](#provider-specific-setup)
- [Docker Configuration](#docker-configuration)
- [Advanced Configuration](#advanced-configuration)
- [Bridge Configuration](#bridge-configuration)
- [Troubleshooting](#troubleshooting)

## 🚀 Quick Setup

### 1. Basic Configuration

Copy the [example environment file](../config/.env.example) and customize it:

```bash
cp config/.env.example .env
nano .env
```

### 2. Minimal Local Setup

For a local Ollama instance:

```bash
# .env file
OPENAI_BASE_URL=http://localhost:11434/v1
OPENAI_API_KEY=
OPENAI_MODEL=qwen3-coder:latest
```

### 3. Start the Environment

```bash
./scripts/start.sh
```

Choose **"OpenAI"** when prompted by qwen-code. See the [start.sh script](../scripts/start.sh) for details.

## 🔧 Environment Variables

### Core Variables

| Variable | Description | Required | Example |
|----------|-------------|----------|---------|
| `OPENAI_BASE_URL` | API endpoint URL | ✅ Yes | `http://localhost:11434/v1` |
| `OPENAI_API_KEY` | Authentication key | ❓ Depends | `sk-your-key-here` |
| `OPENAI_MODEL` | Model name to use | ✅ Yes | `qwen3-coder:latest` |

### Bridge Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `USE_GEMINI_BRIDGE` | Enable Gemini-OpenAI bridge | `false` | `true` |
| `BRIDGE_TARGET_URL` | Where bridge forwards requests | `$OPENAI_BASE_URL` | `http://localhost:11434/v1` |
| `BRIDGE_PORT` | Bridge listening port | `8080` | `8080` |
| `BRIDGE_DEBUG` | Enable bridge debug logging | `false` | `true` |
| `GEMINI_DEFAULT_AUTH_TYPE` | Force qwen-code auth type | - | `openai` |

### Additional Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `QWEN_CONFIG_PATH` | Config directory | `/workspace/.config/qwen-code` | Custom path |

### URL Format Requirements

- ✅ **Correct:** `http://localhost:11434/v1`
- ✅ **Correct:** `https://api.openai.com/v1`
- ❌ **Wrong:** `http://localhost:11434` (missing `/v1`)
- ❌ **Wrong:** `http://localhost:11434/` (missing `v1`)

## 🌐 Provider-Specific Setup

### 🦙 Local Ollama

**Prerequisites:**
```bash
# Install and start Ollama
curl -fsSL https://ollama.ai/install.sh | sh
ollama serve

# Pull your model
ollama pull qwen3-coder:latest
```

**Configuration with Bridge (Recommended):**
```bash
USE_GEMINI_BRIDGE=true
OPENAI_BASE_URL=http://localhost:11434/v1
BRIDGE_TARGET_URL=http://localhost:11434/v1
BRIDGE_PORT=8080
OPENAI_API_KEY=
OPENAI_MODEL=qwen3-coder:latest
GEMINI_DEFAULT_AUTH_TYPE=openai
```

**Direct Configuration (if bridge not needed):**
```bash
USE_GEMINI_BRIDGE=false
OPENAI_BASE_URL=http://localhost:11434/v1
OPENAI_API_KEY=
OPENAI_MODEL=qwen3-coder:latest
```

**Verify it works:**
```bash
curl http://localhost:11434/v1/models

# If using bridge, test bridge health:
curl http://localhost:8080/health
```

### 🌐 Remote Ollama

**Server Setup:**
```bash
# On remote server, configure Ollama to accept external connections
export OLLAMA_HOST=0.0.0.0:11434
ollama serve
```

**Client Configuration with Bridge (Recommended):**
```bash
USE_GEMINI_BRIDGE=true
OPENAI_BASE_URL=http://your-server.example.com:11434/v1
BRIDGE_TARGET_URL=http://your-server.example.com:11434/v1
BRIDGE_PORT=8080
OPENAI_API_KEY=your-optional-key
OPENAI_MODEL=qwen3-coder:latest
GEMINI_DEFAULT_AUTH_TYPE=openai
```

**Direct Configuration (if bridge not needed):**
```bash
USE_GEMINI_BRIDGE=false
OPENAI_BASE_URL=http://your-server.example.com:11434/v1
OPENAI_API_KEY=your-optional-key
OPENAI_MODEL=qwen3-coder:latest
```

**Test connection:**
```bash
curl http://your-server.example.com:11434/v1/models

# If using bridge, test bridge health:
curl http://localhost:8080/health
```

### 🧠 OpenAI

**Configuration (No Bridge Needed):**
```bash
USE_GEMINI_BRIDGE=false
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_API_KEY=sk-your-openai-api-key-here
OPENAI_MODEL=gpt-4
```

**Available Models:**
- `gpt-4` - Most capable
- `gpt-3.5-turbo` - Fast and cost-effective
- `gpt-4-turbo` - Latest GPT-4 version

### 🔵 Azure OpenAI

**Configuration (No Bridge Needed):**
```bash
USE_GEMINI_BRIDGE=false
OPENAI_BASE_URL=https://your-resource.openai.azure.com/openai/deployments/your-deployment-name
OPENAI_API_KEY=your-azure-api-key
OPENAI_MODEL=your-deployment-name
```

### 🔗 Custom API Providers

**Generic Setup (try direct first):**
```bash
USE_GEMINI_BRIDGE=false
OPENAI_BASE_URL=https://your-api.example.com/v1
OPENAI_API_KEY=your-api-key
OPENAI_MODEL=your-model-name
```

**If you get 400 errors, try with bridge:**
```bash
USE_GEMINI_BRIDGE=true
OPENAI_BASE_URL=https://your-api.example.com/v1
BRIDGE_TARGET_URL=https://your-api.example.com/v1
BRIDGE_PORT=8080
OPENAI_API_KEY=your-api-key
OPENAI_MODEL=your-model-name
GEMINI_DEFAULT_AUTH_TYPE=openai
```

**Popular Alternatives:**
- **Anthropic Claude:** Via proxy services
- **Google PaLM:** Via OpenAI-compatible proxies
- **Local LLaMA:** Via text-generation-webui or similar

## 🐳 Docker Configuration

### Container Settings

The `docker-compose.yml` file defines:

```yaml
services:
  qwen-code:
    build: .
    container_name: qwen-code
    environment:
      - OPENAI_BASE_URL=${OPENAI_BASE_URL}
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - OPENAI_MODEL=${OPENAI_MODEL}
    volumes:
      - ./workspace:/workspace/code
      - ./config:/workspace/.config/qwen-code
```

### Volume Mounts

| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `./workspace/` | `/workspace/code/` | Your project files |
| `./config/` | `/workspace/.config/qwen-code/` | Qwen-code settings |
| `~/.gitconfig` | `/home/qwen/.gitconfig` | Git configuration |
| `~/.ssh/` | `/home/qwen/.ssh/` | SSH keys |

### Custom Docker Build

To customize the Docker image:

1. **Edit Dockerfile:**
   ```dockerfile
   # Add custom packages
   RUN apt-get update && apt-get install -y \
       your-package-here
   
   # Install additional Node.js packages
   RUN npm install -g your-npm-package
   ```

2. **Rebuild:**
   ```bash
   docker compose build --no-cache
   ```

## 🔧 Advanced Configuration

### Network Configuration

**For Docker Desktop users:**
```bash
# Access host services from container
OPENAI_BASE_URL=http://host.docker.internal:11434/v1
```

**For Linux users:**
```bash
# Use host network mode (edit docker-compose.yml)
network_mode: "host"
```

### SSL/TLS Configuration

**Self-signed certificates:**
```bash
# Disable SSL verification (not recommended for production)
export NODE_TLS_REJECT_UNAUTHORIZED=0
```

**Custom CA certificates:**
```dockerfile
# In Dockerfile
COPY your-ca-cert.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates
```

### Resource Limits

Add to `docker-compose.yml`:

```yaml
services:
  qwen-code:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G
        reservations:
          cpus: '1.0'
          memory: 2G
```

### Environment-Specific Configs

**Development:**
```bash
# .env.development
OPENAI_BASE_URL=http://localhost:11434/v1
OPENAI_API_KEY=
OPENAI_MODEL=qwen3-coder:7b  # Faster model
```

**Production:**
```bash
# .env.production  
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_API_KEY=sk-production-key
OPENAI_MODEL=gpt-4
```

**Load specific config:**
```bash
cp .env.production .env
./start.sh
```

## 🛠️ Troubleshooting

### Configuration Validation

**Check environment variables:**
```bash
docker exec qwen-code env | grep OPENAI
```

**Test API connection:**
```bash
docker exec qwen-code curl -v $OPENAI_BASE_URL/models
```

**Verify model availability:**
```bash
docker exec qwen-code curl $OPENAI_BASE_URL/models | grep $OPENAI_MODEL
```

### Common Issues

**🔴 "400 status code" or "Model not found" errors:**
- If using Ollama, enable bridge: `USE_GEMINI_BRIDGE=true`
- Check model name matches exactly: `curl $OPENAI_BASE_URL/models | jq '.data[].id'`
- Verify model is loaded in Ollama: `ollama list`

**🔴 Bridge not working:**
- Test bridge health: `curl http://localhost:8080/health`
- Check bridge logs: `docker logs qwen-code | grep Bridge`
- Verify bridge environment: `docker exec qwen-code env | grep BRIDGE`

**🔴 SSL certificate errors:**
- For self-signed certs, add to Dockerfile: `ENV NODE_TLS_REJECT_UNAUTHORIZED=0`
- Or provide proper CA certificates

**🔴 Container can't reach API:**
- For localhost APIs, use `host.docker.internal` (Docker Desktop)
- Or use `--network=host` mode (Linux)
- Check firewall settings

**🔴 Permission denied errors:**
- Add user to docker group: `sudo usermod -aG docker $USER`
- Restart Docker service: `sudo systemctl restart docker`

### Configuration Reset

**Reset qwen-code settings:**
```bash
docker exec qwen-code rm -rf /workspace/.config/qwen-code/*
docker restart qwen-code
```

**Complete reset:**
```bash
docker compose down
docker compose build --no-cache
rm -rf ./config/*
./start.sh
```

## 📞 Getting Help

1. **Check logs:**
   ```bash
   docker compose logs -f qwen-code
   ```

2. **Debug container:**
   ```bash
   docker exec -it qwen-code bash
   # Test connections, check files, etc.
   ```

3. **Community support:**
   - 📖 [Troubleshooting Guide](TROUBLESHOOTING.md)
   - 💬 [GitHub Issues](https://github.com/your-username/qwen-code-docker/issues)
   - 🌐 [Qwen-Code Documentation](https://github.com/QwenLM/Qwen3-Coder)

---

**Next steps:** Check out the [Troubleshooting Guide](TROUBLESHOOTING.md) for common issues and solutions.

## 🌉 Bridge Configuration

The Gemini-OpenAI Bridge allows you to route API requests through a proxy. See [bridge source code](../src/bridge/) for implementation details.

### Enabling the Bridge

Set these variables in your `.env`:

```bash
USE_GEMINI_BRIDGE=true
BRIDGE_TARGET_URL=http://your-target-server:port/v1
BRIDGE_PORT=8080
BRIDGE_DEBUG=true  # For troubleshooting
```

### How It Works

1. When enabled, the bridge starts on `localhost:8080`
2. Qwen CLI connects to the bridge instead of the direct API
3. Bridge forwards requests to `BRIDGE_TARGET_URL`
4. Authentication headers are preserved

### Troubleshooting Bridge Issues

Run the [diagnostic script](../scripts/utils/diagnose.sh):

```bash
./scripts/utils/diagnose.sh
```

Check bridge logs:

```bash
docker exec qwen-code cat /workspace/logs/bridge.log
```

---

[← Back to top](#-configuration-guide) | [Troubleshooting →](TROUBLESHOOTING.md)
