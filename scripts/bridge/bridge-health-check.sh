#!/bin/bash

# Bridge health check script
# Returns 0 if healthy, 1 if unhealthy

BRIDGE_PORT=${BRIDGE_PORT:-8080}
MAX_RETRIES=${1:-1}
RETRY_DELAY=${2:-1}

check_health() {
    # Try to get health status
    response=$(curl -s -f -m 2 http://localhost:${BRIDGE_PORT}/health 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        # Check if response contains expected fields
        if echo "$response" | grep -q '"status".*"healthy"'; then
            return 0
        fi
    fi
    
    return 1
}

# Perform health check with retries
for i in $(seq 1 $MAX_RETRIES); do
    if check_health; then
        echo "✅ Bridge is healthy"
        exit 0
    fi
    
    if [ $i -lt $MAX_RETRIES ]; then
        echo "Health check failed, retrying in ${RETRY_DELAY}s... ($i/$MAX_RETRIES)"
        sleep $RETRY_DELAY
    fi
done

echo "❌ Bridge health check failed after $MAX_RETRIES attempts"
exit 1