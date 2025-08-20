#!/bin/bash

echo "=== Docker Entrypoint Starting at $(date) ==="

# Note: Running as root initially to set up the bridge
# The user switch happens when exec'ing into the container

# Create log directory
mkdir -p /workspace/logs

# Load .env with better error handling
if [ -f /workspace/.env ]; then
    echo "Loading environment from /workspace/.env..."
    set -a
    source /workspace/.env
    set +a
    echo "Environment loaded successfully"
else
    echo "WARNING: No .env file found at /workspace/.env"
fi

# Log all relevant environment variables
{
    echo "=== Environment Variables at $(date) ==="
    echo "USE_GEMINI_BRIDGE: ${USE_GEMINI_BRIDGE}"
    echo "BRIDGE_TARGET_URL: ${BRIDGE_TARGET_URL}"
    echo "BRIDGE_PORT: ${BRIDGE_PORT}"
    echo "BRIDGE_DEBUG: ${BRIDGE_DEBUG}"
    echo "OPENAI_BASE_URL: ${OPENAI_BASE_URL}"
    echo "OPENAI_API_KEY: ${OPENAI_API_KEY:0:20}..."
    echo "OPENAI_MODEL: ${OPENAI_MODEL}"
    echo "GEMINI_DEFAULT_AUTH_TYPE: ${GEMINI_DEFAULT_AUTH_TYPE}"
    echo "PATH: ${PATH}"
    echo "NODE: $(which node 2>/dev/null || echo 'not found')"
    echo "=================================="
} | tee /workspace/logs/entrypoint.log

# Start bridge if needed
if [ "${USE_GEMINI_BRIDGE:-false}" = "true" ]; then
    echo "Bridge is ENABLED, starting Gemini-OpenAI Bridge..." | tee -a /workspace/logs/entrypoint.log
    
    # Check if bridge directory exists
    if [ ! -d /bridge ]; then
        echo "ERROR: /bridge directory does not exist!" | tee -a /workspace/logs/entrypoint.log
        echo "Bridge cannot start without bridge code" | tee -a /workspace/logs/entrypoint.log
        exit 1
    fi
    
    cd /bridge
    
    # Check if package.json exists
    if [ ! -f package.json ]; then
        echo "ERROR: No package.json in /bridge!" | tee -a /workspace/logs/entrypoint.log
        ls -la /bridge/ | tee -a /workspace/logs/entrypoint.log
        exit 1
    fi
    
    # Check if node_modules exists, install if not
    if [ ! -d node_modules ]; then
        echo "Installing bridge dependencies..." | tee -a /workspace/logs/entrypoint.log
        npm install 2>&1 | tee -a /workspace/logs/entrypoint.log
    fi
    
    # Set bridge environment
    export BRIDGE_PORT=${BRIDGE_PORT:-8080}
    export BRIDGE_TARGET_URL=${BRIDGE_TARGET_URL:-${OPENAI_BASE_URL:-http://localhost:11434/v1}}
    export BRIDGE_DEBUG=${BRIDGE_DEBUG:-false}
    
    echo "Bridge configuration:" | tee -a /workspace/logs/entrypoint.log
    echo "  Target URL: ${BRIDGE_TARGET_URL}" | tee -a /workspace/logs/entrypoint.log
    echo "  Listen Port: ${BRIDGE_PORT}" | tee -a /workspace/logs/entrypoint.log
    echo "  Debug Mode: ${BRIDGE_DEBUG}" | tee -a /workspace/logs/entrypoint.log
    
    # Start bridge with comprehensive logging
    echo "Starting bridge process..." | tee -a /workspace/logs/entrypoint.log
    node bridge.js > /workspace/logs/bridge.log 2>&1 &
    BRIDGE_PID=$!
    echo "Bridge started with PID: $BRIDGE_PID" | tee -a /workspace/logs/entrypoint.log
    
    # Wait for bridge to initialize
    echo "Waiting for bridge to initialize..." | tee -a /workspace/logs/entrypoint.log
    
    # Use health check script if available
    if [ -x /workspace/bridge-health-check.sh ]; then
        if /workspace/bridge-health-check.sh 10 1 | tee -a /workspace/logs/entrypoint.log; then
            BRIDGE_READY=true
        else
            BRIDGE_READY=false
        fi
    else
        # Fallback to inline health check
        BRIDGE_READY=false
        for i in {1..10}; do
            sleep 1
            # Check if process is still running
            if ! ps -p $BRIDGE_PID > /dev/null 2>&1; then
                echo "❌ Bridge process died (attempt $i/10)" | tee -a /workspace/logs/entrypoint.log
                break
            fi
            # Check health endpoint
            if curl -s -f http://localhost:$BRIDGE_PORT/health > /dev/null 2>&1; then
                echo "✅ Bridge health check passed (attempt $i/10)" | tee -a /workspace/logs/entrypoint.log
                BRIDGE_READY=true
                break
            fi
            echo "Waiting for bridge health check... (attempt $i/10)" | tee -a /workspace/logs/entrypoint.log
        done
    fi
    
    if [ "$BRIDGE_READY" = "true" ]; then
        echo "✅ Bridge is running and healthy (PID: $BRIDGE_PID)" | tee -a /workspace/logs/entrypoint.log
        
        # Override OPENAI_BASE_URL to point to bridge
        export OPENAI_BASE_URL="http://localhost:$BRIDGE_PORT/v1"
        echo "OPENAI_BASE_URL overridden to: ${OPENAI_BASE_URL}" | tee -a /workspace/logs/entrypoint.log
        
        # Also write it to a profile file so it persists for all users
        echo "export OPENAI_BASE_URL=\"http://localhost:$BRIDGE_PORT/v1\"" > /etc/profile.d/qwen-bridge.sh
        chmod +x /etc/profile.d/qwen-bridge.sh
    else
        echo "❌ ERROR: Bridge failed to start or become healthy!" | tee -a /workspace/logs/entrypoint.log
        
        # Check if process is still running
        if ps -p $BRIDGE_PID > /dev/null 2>&1; then
            echo "Bridge process is running but not responding to health checks" | tee -a /workspace/logs/entrypoint.log
        else
            echo "Bridge process has died" | tee -a /workspace/logs/entrypoint.log
        fi
        
        echo "Last 20 lines of bridge log:" | tee -a /workspace/logs/entrypoint.log
        tail -20 /workspace/logs/bridge.log 2>/dev/null | tee -a /workspace/logs/entrypoint.log
        echo "Continuing without bridge..." | tee -a /workspace/logs/entrypoint.log
    fi
else
    echo "Bridge is DISABLED, using direct connection" | tee -a /workspace/logs/entrypoint.log
    echo "OPENAI_BASE_URL: ${OPENAI_BASE_URL}" | tee -a /workspace/logs/entrypoint.log
fi

echo "=== Entrypoint setup complete ===" | tee -a /workspace/logs/entrypoint.log

# Fix permissions on mounted volumes
echo "Fixing permissions on /home/qwen..." | tee -a /workspace/logs/entrypoint.log
chown -R qwen:qwen /home/qwen 2>/dev/null || true
chmod 755 /home/qwen/.config 2>/dev/null || true

cd /workspace

# If we have arguments, execute them
if [ $# -gt 0 ]; then
    exec "$@"
else
    # No arguments, keep container running
    echo "Container ready. Keeping alive..." | tee -a /workspace/logs/entrypoint.log
    exec tail -f /dev/null
fi