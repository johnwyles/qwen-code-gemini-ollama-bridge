# 🔧 Troubleshooting Guide

[← Configuration](CONFIGURATION.md) | [Back to README](../README.md)

This guide helps you diagnose and fix common issues with Qwen-Code Docker.

## 📋 Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Connection Issues](#connection-issues)
- [Docker Problems](#docker-problems)
- [Configuration Issues](#configuration-issues)
- [Bridge Issues](#bridge-issues)
- [Performance Problems](#performance-problems)
- [FAQ](#faq)

## 🩺 Quick Diagnostics

### Health Check Script

Use the [diagnostic script](../scripts/utils/diagnose.sh) to quickly identify issues:

```bash
./scripts/utils/diagnose.sh
```

Or run manual checks:

```bash
#!/bin/bash
echo "🔍 Qwen-Code Docker Health Check"
echo "=================================="

# Check Docker
echo "📦 Docker Status:"
docker --version && echo "✅ Docker installed" || echo "❌ Docker not found"
docker info >/dev/null 2>&1 && echo "✅ Docker running" || echo "❌ Docker not running"

# Check container
echo "🐳 Container Status:"
docker ps | grep qwen-code && echo "✅ Container running" || echo "❌ Container not running"

# Check environment
echo "🔧 Environment Variables:"
if [ -f .env ]; then
    echo "✅ .env file exists"
    grep -E "OPENAI_(BASE_URL|API_KEY|MODEL)" .env | sed 's/OPENAI_API_KEY=.*/OPENAI_API_KEY=***HIDDEN***/'
else
    echo "❌ .env file missing"
fi

# Test API connection
if [ -f .env ]; then
    source .env
    if [ -n "$OPENAI_BASE_URL" ]; then
        echo "🌐 API Connection:"
        curl -s -o /dev/null -w "Status: %{http_code}" "$OPENAI_BASE_URL/models" && echo " ✅" || echo " ❌"
    fi
fi
```

### Container Logs

Check what's happening inside:

```bash
# View recent logs
docker compose logs --tail=50 qwen-code

# Follow logs in real-time
docker compose logs -f qwen-code

# Check system logs
journalctl -u docker -n 20
```

## 🌐 Connection Issues

### Error: "Connection error"

**Symptoms:**
- Qwen-code shows "Connection error" when trying to use AI
- Cannot reach the API endpoint

**Diagnosis:**
```bash
# Test from host
curl -v http://your-api-server:11434/v1/models

# Test from container
docker exec qwen-code curl -v $OPENAI_BASE_URL/models
```

**Solutions:**

1. **Check API server is running:**
   ```bash
   # For Ollama
   ollama list  # Should show your models
   curl http://localhost:11434/api/version
   ```

2. **Verify network connectivity:**
   ```bash
   # Ping the server
   ping your-api-server
   
   # Check port is open
   telnet your-api-server 11434
   ```

3. **Fix Docker networking:**
   ```bash
   # For localhost APIs (Docker Desktop)
   OPENAI_BASE_URL=http://host.docker.internal:11434/v1
   
   # For localhost APIs (Linux)
   OPENAI_BASE_URL=http://172.17.0.1:11434/v1
   
   # Or use host networking
   # Add to docker-compose.yml:
   network_mode: "host"
   ```

### Error: "400 status code (no body)" or "Model not found"

**Symptoms:**
- Connection works but requests fail
- 400 or 404 HTTP errors
- qwen-code shows "400 status code (no body)"

**Most Common Cause: Gemini Format Incompatibility**

qwen-code sends requests in Gemini format with fields like `generationConfig` and `safetySettings` that Ollama doesn't understand. **Enable the bridge to fix this:**

```bash
# Add to .env file
USE_GEMINI_BRIDGE=true
BRIDGE_TARGET_URL=http://your-ollama-server:11434/v1
BRIDGE_PORT=8080
GEMINI_DEFAULT_AUTH_TYPE=openai

# Restart container
docker compose restart
```

**Additional Diagnosis:**
```bash
# Check available models
curl $OPENAI_BASE_URL/models | jq '.data[].id'

# Test bridge health (if enabled)
curl http://localhost:8080/health

# Test with a simple request
curl -X POST $OPENAI_BASE_URL/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen3-coder:latest", "messages": [{"role": "user", "content": "test"}]}'
```

**Other Solutions:**

1. **Fix model name:**
   ```bash
   # Check exact model name
   ollama list
   
   # Update .env with correct name
   OPENAI_MODEL=qwen3-coder:latest  # Must match exactly
   ```

2. **Verify API endpoint:**
   ```bash
   # Must end with /v1
   OPENAI_BASE_URL=http://localhost:11434/v1  # ✅ Correct
   OPENAI_BASE_URL=http://localhost:11434     # ❌ Wrong
   ```

3. **Check authentication:**
   ```bash
   # For Ollama (no auth needed)
   OPENAI_API_KEY=
   
   # For OpenAI
   OPENAI_API_KEY=sk-your-real-key-here
   ```

### SSL/TLS Errors

**Symptoms:**
- "TLS connect error"
- "certificate verify failed"

**Solutions:**

1. **For self-signed certificates:**
   ```dockerfile
   # Add to Dockerfile
   ENV NODE_TLS_REJECT_UNAUTHORIZED=0
   ```

2. **Use HTTP instead of HTTPS:**
   ```bash
   # Change from https to http
   OPENAI_BASE_URL=http://your-server:8443/v1
   ```

3. **Add custom CA certificate:**
   ```dockerfile
   COPY your-ca-cert.crt /usr/local/share/ca-certificates/
   RUN update-ca-certificates
   ```

## 🐳 Docker Problems

### Error: "permission denied" (Docker socket)

**Symptoms:**
- Cannot run docker commands
- "dial unix /var/run/docker.sock: connect: permission denied"

**Solutions:**

1. **Add user to docker group:**
   ```bash
   sudo usermod -aG docker $USER
   
   # Log out and back in, or run:
   newgrp docker
   ```

2. **Start Docker service:**
   ```bash
   sudo systemctl start docker
   sudo systemctl enable docker
   ```

### Container Won't Start

**Symptoms:**
- `./start.sh` fails
- "Container exited with code 1"

**Diagnosis:**
```bash
# Check container logs
docker logs qwen-code

# Try to start manually
docker run -it --name debug-qwen qwen-code-docker-qwen-code bash
```

**Solutions:**

1. **Rebuild from scratch:**
   ```bash
   docker compose down
   docker system prune -f
   docker compose build --no-cache
   ```

2. **Check Dockerfile syntax:**
   ```bash
   docker build -t test-build .
   ```

3. **Fix file permissions:**
   ```bash
   chmod +x start.sh
   sudo chown -R $USER:$USER ./workspace ./config
   ```

### Port Already in Use

**Symptoms:**
- "Port is already allocated"
- "Address already in use"

**Solutions:**

1. **Find and kill process:**
   ```bash
   sudo lsof -i :11434
   sudo kill -9 <PID>
   ```

2. **Use different port:**
   ```bash
   # Edit docker-compose.yml
   ports:
     - "11435:11434"  # Changed from 11434
   ```

## 🌉 Bridge Issues

### Bridge Not Starting

**Symptoms:**
- Bridge health check fails: `curl http://localhost:8080/health`
- No bridge logs in container output
- Still getting 400 errors with Ollama

**Diagnosis:**
```bash
# Check if bridge is enabled
docker exec qwen-code env | grep BRIDGE

# Check bridge process
docker exec qwen-code ps aux | grep bridge

# Check bridge logs
docker logs qwen-code | grep -i bridge
```

**Solutions:**

1. **Verify bridge configuration:**
   ```bash
   # Required variables in .env
   USE_GEMINI_BRIDGE=true
   BRIDGE_TARGET_URL=http://your-server:11434/v1
   BRIDGE_PORT=8080
   ```

2. **Restart container:**
   ```bash
   docker compose restart qwen-code
   ```

3. **Enable debug logging:**
   ```bash
   # Add to .env
   BRIDGE_DEBUG=true
   
   # Restart and check logs
   docker compose restart qwen-code
   docker logs qwen-code | grep Bridge
   ```

### Bridge Connection Issues

**Symptoms:**
- Bridge starts but can't reach target server
- Bridge health shows target unreachable

**Solutions:**

1. **Fix target URL:**
   ```bash
   # For Docker Desktop
   BRIDGE_TARGET_URL=http://host.docker.internal:11434/v1
   
   # For Linux host networking
   BRIDGE_TARGET_URL=http://172.17.0.1:11434/v1
   ```

2. **Test target directly:**
   ```bash
   # From container
   docker exec qwen-code curl -v $BRIDGE_TARGET_URL/models
   ```

3. **Check firewall/networking:**
   ```bash
   # Test from host
   curl -v http://your-server:11434/v1/models
   ```

## ⚙️ Configuration Issues

### Environment Variables Not Loading

**Symptoms:**
- Container shows empty environment variables
- Settings not taking effect

**Diagnosis:**
```bash
# Check container environment
docker exec qwen-code env | grep OPENAI

# Verify .env file format
cat .env | grep -v '^#' | grep '='
```

**Solutions:**

1. **Fix .env file format:**
   ```bash
   # ✅ Correct format
   OPENAI_BASE_URL=http://localhost:11434/v1
   OPENAI_API_KEY=sk-key-here
   
   # ❌ Wrong format (spaces around =)
   OPENAI_BASE_URL = http://localhost:11434/v1
   ```

2. **Recreate container:**
   ```bash
   docker compose down
   docker compose up --build
   ```

3. **Check file location:**
   ```bash
   # .env must be in same directory as docker-compose.yml
   ls -la .env docker-compose.yml
   ```

### Qwen-Code Not Using Configuration

**Symptoms:**
- Qwen-code asks for configuration again
- Settings don't persist

**Solutions:**

1. **Clear qwen-code cache:**
   ```bash
   docker exec qwen-code rm -rf /workspace/.config/qwen-code/*
   docker restart qwen-code
   ```

2. **Check volume mounts:**
   ```bash
   # Verify config directory exists
   ls -la ./config/
   
   # Check mount is working
   docker exec qwen-code ls -la /workspace/.config/qwen-code/
   ```

3. **Re-run setup:**
   ```bash
   # Start fresh
   ./start.sh
   # Choose "OpenAI" when prompted
   ```

## 🚀 Performance Problems

### Slow Response Times

**Symptoms:**
- Long delays for AI responses
- Timeouts

**Solutions:**

1. **Use faster model:**
   ```bash
   # Switch to smaller/faster model
   OPENAI_MODEL=qwen3-coder:7b  # Instead of 14b or 30b
   ```

2. **Increase timeouts:**
   ```bash
   # Add to docker-compose.yml
   environment:
     - OLLAMA_REQUEST_TIMEOUT=300
   ```

3. **Check system resources:**
   ```bash
   # Monitor usage
   docker stats qwen-code
   htop
   ```

### High Memory Usage

**Symptoms:**
- System running out of RAM
- Container killed by OOM

**Solutions:**

1. **Set memory limits:**
   ```yaml
   # docker-compose.yml
   services:
     qwen-code:
       deploy:
         resources:
           limits:
             memory: 4G
   ```

2. **Use smaller model:**
   ```bash
   OPENAI_MODEL=qwen3-coder:1.5b  # Lightest option
   ```

3. **Configure Ollama:**
   ```bash
   # Limit Ollama memory
   export OLLAMA_NUM_PARALLEL=1
   export OLLAMA_MAX_LOADED_MODELS=1
   ```

## ❓ FAQ

### Q: Why do I get "Choose OpenAI or Qwen OAuth"?

**A:** Always choose **OpenAI** for self-hosted setups. Qwen OAuth is only for Qwen's cloud service.

### Q: Should I use the Gemini-OpenAI bridge?

**A:** Use the bridge if:
- ✅ Using Ollama (local or remote)
- ✅ Getting 400 status code errors
- ✅ API expects pure OpenAI format

Don't use bridge if:
- ❌ Using OpenAI official API
- ❌ API handles Gemini format natively

### Q: How do I know if the bridge is working?

**A:** Test bridge health:
```bash
curl http://localhost:8080/health

# Expected response:
{
  "status": "healthy",
  "bridge": "gemini-openai-bridge",
  "target": "http://your-server:11434/v1",
  "uptime": 123.45
}
```

### Q: What does the bridge actually do?

**A:** The bridge transforms qwen-code's Gemini-format requests into clean OpenAI format by:
- Removing `generationConfig`, `safetySettings`, `tools`
- Converting `systemInstruction` to system messages
- Capping excessive token limits (200k+ → 4k)
- Preserving OpenAI-compatible fields

### Q: Can I use multiple models?

**A:** Yes, just change the `OPENAI_MODEL` environment variable and restart:
```bash
export OPENAI_MODEL=llama3:8b
docker restart qwen-code
```

### Q: How do I update to the latest qwen-code version?

**A:**
```bash
docker compose build --no-cache --pull
```

### Q: Can I run this on Windows?

**A:** Yes, with Docker Desktop:
```bash
# Use Windows paths
OPENAI_BASE_URL=http://host.docker.internal:11434/v1
```

### Q: How do I backup my configuration?

**A:**
```bash
# Backup workspace and config
tar -czf qwen-backup.tar.gz workspace/ config/ .env

# Restore
tar -xzf qwen-backup.tar.gz
```

### Q: Can I use this with VS Code?

**A:** Yes! Mount your project directory:
```yaml
volumes:
  - /path/to/your/project:/workspace/project
```

### Q: How do I enable debug logging?

**A:**
```bash
# For qwen-code debug
DEBUG=qwen*

# For bridge debug
BRIDGE_DEBUG=true

# Or run container with debug
docker compose run --rm -e DEBUG=* -e BRIDGE_DEBUG=true qwen-code
```

## 🆘 Still Need Help?

### Gather Debug Information

Before asking for help, collect this information:

```bash
# System info
uname -a
docker --version
docker compose version

# Container status
docker ps -a | grep qwen
docker logs --tail=50 qwen-code

# Configuration
cat .env | sed 's/OPENAI_API_KEY=.*/OPENAI_API_KEY=***HIDDEN***/'

# Network test
curl -v $OPENAI_BASE_URL/models 2>&1 | head -20
```

### Get Support

1. 📖 **Documentation:**
   - [Configuration Guide](CONFIGURATION.md)
   - [Qwen-Code Documentation](https://github.com/QwenLM/Qwen3-Coder)
   
2. 💬 **Community:**
   - [GitHub Issues](https://github.com/your-username/qwen-code-docker/issues)
   - Include debug information from above
   
3. 🔍 **Search existing issues:**
   - Someone might have already solved your problem!

---

**Remember:** Most issues are configuration-related. Double-check your `.env` file and API endpoint accessibility! 🎯
## 🌉 Bridge Issues

### Bridge Not Starting

**Symptoms:**
- "Bridge failed to start" in logs
- Port 8080 not listening

**Solutions:**

1. Check bridge logs:
   ```bash
   docker exec qwen-code cat /workspace/logs/bridge.log
   ```

2. Verify bridge files exist:
   ```bash
   docker exec qwen-code ls -la /bridge/
   ```

3. Test bridge health:
   ```bash
   docker exec qwen-code curl http://localhost:8080/health
   ```

### Authentication Errors Through Bridge

**Symptoms:**
- "Not authenticated" errors
- 401 responses

**Solutions:**

1. Verify API key is set:
   ```bash
   docker exec qwen-code printenv OPENAI_API_KEY
   ```

2. Test direct connection:
   ```bash
   docker exec qwen-code curl -H "Authorization: Bearer $OPENAI_API_KEY" \
     http://your-target-server/v1/models
   ```

3. Check bridge is forwarding auth:
   ```bash
   docker exec qwen-code cat /workspace/logs/bridge.log | grep Authorization
   ```

See [Bridge Configuration](CONFIGURATION.md#-bridge-configuration) for setup details.

---

[← Back to top](#-troubleshooting-guide) | [Configuration →](CONFIGURATION.md) | [README →](../README.md)
