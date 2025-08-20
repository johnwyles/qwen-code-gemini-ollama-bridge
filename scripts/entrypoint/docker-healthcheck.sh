#!/bin/bash

# Docker HEALTHCHECK script
# Used by Docker to determine container health status

# Check if bridge is enabled
if [ "${USE_GEMINI_BRIDGE:-false}" = "true" ]; then
    # Check bridge health
    curl -f http://localhost:${BRIDGE_PORT:-8080}/health > /dev/null 2>&1 || exit 1
fi

# Always return healthy if bridge is disabled
exit 0