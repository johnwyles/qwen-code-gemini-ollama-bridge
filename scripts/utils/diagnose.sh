#!/bin/bash

# Comprehensive diagnostic script for Qwen Code Docker setup

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}     QWEN-CODE DOCKER DIAGNOSTIC TOOL${NC}"
echo -e "${BLUE}================================================${NC}"
echo "Running at: $(date)"
echo ""

# 1. Check Docker
echo -e "${YELLOW}1. Docker Status:${NC}"
if docker info >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Docker daemon is running"
    docker version --format "  Docker version: {{.Server.Version}}"
else
    echo -e "  ${RED}✗${NC} Docker daemon not accessible"
    exit 1
fi
echo ""

# 2. Check Image
echo -e "${YELLOW}2. Docker Image:${NC}"
if docker image inspect qwen-code-docker >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Image 'qwen-code-docker' exists"
    IMAGE_CREATED=$(docker image inspect qwen-code-docker -f '{{.Created}}' | cut -d'T' -f1)
    echo "  Created: $IMAGE_CREATED"
    IMAGE_SIZE=$(docker image inspect qwen-code-docker -f '{{.Size}}' | numfmt --to=iec-i --suffix=B)
    echo "  Size: $IMAGE_SIZE"
else
    echo -e "  ${RED}✗${NC} Image 'qwen-code-docker' not found"
    echo "  Run: docker compose build"
fi
echo ""

# 3. Check Container
echo -e "${YELLOW}3. Container Status:${NC}"
if docker container inspect qwen-code >/dev/null 2>&1; then
    STATUS=$(docker container inspect qwen-code -f '{{.State.Status}}')
    if [ "$STATUS" = "running" ]; then
        echo -e "  ${GREEN}✓${NC} Container 'qwen-code' is $STATUS"
        UPTIME=$(docker ps --filter name=qwen-code --format "table {{.Status}}" | tail -1)
        echo "  Status: $UPTIME"
    else
        echo -e "  ${YELLOW}⚠${NC} Container 'qwen-code' is $STATUS"
        echo "  Run: docker start qwen-code"
    fi
else
    echo -e "  ${RED}✗${NC} Container 'qwen-code' does not exist"
    echo "  Run: ./start.sh"
fi
echo ""

# Only continue if container is running
if ! docker ps --format "{{.Names}}" | grep -q "^qwen-code$"; then
    echo -e "${RED}Container not running. Start it with: ./start.sh${NC}"
    exit 0
fi

# 4. Check qwen user IN THE CONTAINER
echo -e "${YELLOW}4. User Configuration (in container):${NC}"
if docker exec qwen-code id qwen 2>/dev/null >/dev/null; then
    echo -e "  ${GREEN}✓${NC} qwen user exists"
    docker exec qwen-code id qwen 2>/dev/null | sed 's/^/    /'
    # Check sudo access
    if docker exec -u qwen qwen-code sudo -n true 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} qwen has passwordless sudo"
    else
        echo -e "  ${YELLOW}⚠${NC} qwen does not have passwordless sudo"
    fi
else
    echo -e "  ${RED}✗${NC} qwen user not found in container"
    echo "  Available users with home directories:"
    docker exec qwen-code grep ":/home/" /etc/passwd | cut -d: -f1,3,6 | sed 's/^/    /'
fi
echo ""

# 5. Check qwen command
echo -e "${YELLOW}5. Qwen Command (in container):${NC}"
if docker exec qwen-code which qwen 2>/dev/null >/dev/null; then
    QWEN_PATH=$(docker exec qwen-code which qwen 2>/dev/null)
    echo -e "  ${GREEN}✓${NC} qwen command found at: $QWEN_PATH"
    # Try to get version
    if docker exec qwen-code qwen --version 2>/dev/null | head -1; then
        docker exec qwen-code qwen --version 2>/dev/null | head -1 | sed 's/^/    Version: /'
    fi
else
    echo -e "  ${RED}✗${NC} qwen command not found in container"
    echo "  Checking npm global packages:"
    docker exec qwen-code npm list -g --depth=0 2>/dev/null | grep -i qwen | sed 's/^/    /' || echo "    No qwen packages found"
fi
echo ""

# 6. Check Bridge
echo -e "${YELLOW}6. Bridge Configuration:${NC}"
USE_BRIDGE=$(docker exec qwen-code printenv USE_GEMINI_BRIDGE 2>/dev/null)
if [ "$USE_BRIDGE" = "true" ]; then
    echo -e "  ${GREEN}✓${NC} Bridge is ENABLED"
    
    # Check bridge files
    if docker exec qwen-code test -f /bridge/bridge.js 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} bridge.js exists"
    else
        echo -e "  ${RED}✗${NC} bridge.js not found"
    fi
    
    # Check if bridge process is running
    if docker exec qwen-code pgrep -f "node.*bridge" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Bridge process is running"
        BRIDGE_PID=$(docker exec qwen-code pgrep -f "node.*bridge" | head -1)
        echo "    PID: $BRIDGE_PID"
    else
        echo -e "  ${RED}✗${NC} Bridge process not running"
    fi
    
    # Check bridge port
    BRIDGE_PORT=$(docker exec qwen-code printenv BRIDGE_PORT 2>/dev/null || echo "8080")
    if docker exec qwen-code netstat -tuln 2>/dev/null | grep -q ":$BRIDGE_PORT "; then
        echo -e "  ${GREEN}✓${NC} Port $BRIDGE_PORT is listening"
    else
        echo -e "  ${YELLOW}⚠${NC} Port $BRIDGE_PORT is not listening"
    fi
    
    # Test bridge health
    if docker exec qwen-code curl -sf http://localhost:$BRIDGE_PORT/health >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Bridge health check passed"
    else
        echo -e "  ${RED}✗${NC} Bridge health check failed"
    fi
else
    echo "  Bridge is DISABLED"
fi
echo ""

# 7. Check Logs
echo -e "${YELLOW}7. Recent Logs:${NC}"
if docker exec qwen-code test -f /workspace/logs/entrypoint.log 2>/dev/null; then
    echo "  Entrypoint log (last 5 lines):"
    docker exec qwen-code tail -5 /workspace/logs/entrypoint.log 2>/dev/null | sed 's/^/    /'
else
    echo "  No entrypoint log found"
fi

if [ "$USE_BRIDGE" = "true" ] && docker exec qwen-code test -f /workspace/logs/bridge.log 2>/dev/null; then
    echo "  Bridge log (last 5 lines):"
    docker exec qwen-code tail -5 /workspace/logs/bridge.log 2>/dev/null | sed 's/^/    /'
fi
echo ""

# 8. Environment Variables
echo -e "${YELLOW}8. Key Environment Variables:${NC}"
docker exec qwen-code printenv | grep -E "OPENAI|BRIDGE|GEMINI" | sed 's/\(API_KEY=\).*/\1***/' | sort | sed 's/^/  /'
echo ""

# 9. Recommendations
echo -e "${BLUE}================================================${NC}"
echo -e "${YELLOW}RECOMMENDATIONS:${NC}"

NEEDS_REBUILD=false

if ! docker image inspect qwen-code-docker >/dev/null 2>&1; then
    echo "  1. Build the image: docker compose build"
    NEEDS_REBUILD=true
elif ! docker exec qwen-code id qwen 2>/dev/null >/dev/null; then
    echo "  1. User 'qwen' missing - rebuild image: docker compose build --no-cache"
    NEEDS_REBUILD=true
elif ! docker exec qwen-code which qwen 2>/dev/null >/dev/null; then
    echo "  1. Command 'qwen' missing - rebuild image: docker compose build --no-cache"
    NEEDS_REBUILD=true
fi

if [ "$NEEDS_REBUILD" = false ]; then
    if [ "$USE_BRIDGE" = "true" ] && ! docker exec qwen-code pgrep -f "node.*bridge" >/dev/null 2>&1; then
        echo "  1. Bridge enabled but not running - restart container: docker restart qwen-code"
    else
        echo -e "  ${GREEN}✓${NC} Everything looks good!"
        echo ""
        echo "  To connect to the container:"
        echo "    ./start.sh"
    fi
fi

echo ""
echo -e "${BLUE}================================================${NC}"