#!/bin/bash

# Bridge monitoring script
# Continuously monitors bridge health and restarts if needed

BRIDGE_PORT=${BRIDGE_PORT:-8080}
CHECK_INTERVAL=${CHECK_INTERVAL:-30}
LOG_FILE="/workspace/logs/bridge-monitor.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

restart_bridge() {
    log "Attempting to restart bridge..."
    
    # Kill existing bridge process
    pkill -f "node.*bridge.js" 2>/dev/null
    sleep 2
    
    # Start new bridge process
    cd /bridge
    export BRIDGE_PORT=${BRIDGE_PORT}
    export BRIDGE_TARGET_URL=${BRIDGE_TARGET_URL:-${OPENAI_BASE_URL:-http://localhost:11434/v1}}
    export BRIDGE_DEBUG=${BRIDGE_DEBUG:-false}
    
    node bridge.js >> /workspace/logs/bridge.log 2>&1 &
    local new_pid=$!
    
    log "Bridge restarted with PID: $new_pid"
    
    # Wait for bridge to become healthy
    sleep 3
    if /workspace/bridge-health-check.sh 5 2; then
        log "✅ Bridge restart successful"
        return 0
    else
        log "❌ Bridge restart failed"
        return 1
    fi
}

# Main monitoring loop
log "Starting bridge monitor (checking every ${CHECK_INTERVAL}s)"

while true; do
    if ! /workspace/bridge-health-check.sh 1 1 > /dev/null 2>&1; then
        log "⚠️ Bridge health check failed"
        
        # Try to restart bridge
        if restart_bridge; then
            log "Bridge recovered"
        else
            log "Failed to recover bridge - manual intervention required"
            # Could send alert here
        fi
    fi
    
    sleep $CHECK_INTERVAL
done