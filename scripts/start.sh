#!/bin/bash

# Qwen Code Docker Intelligent Startup Script
# Handles container states, rebuilds, and data persistence

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check for --rebuild flag
FORCE_REBUILD=false
if [ "$1" = "--rebuild" ] || [ "$1" = "-r" ]; then
    FORCE_REBUILD=true
    print_info "Force rebuild requested"
fi

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
CONTAINER_NAME="qwen-code"
IMAGE_NAME="qwen-code-docker"
DOCKERFILE_PATH="./Dockerfile"

print_info "Starting Qwen Code Docker Environment..."

# Check if .env exists
if [ ! -f .env ]; then
    print_warning ".env file not found."
    print_info "Please copy .env.example to .env and configure your settings:"
    print_info "  cp .env.example .env"
    print_info "  # Edit .env with your API configuration"
    print_error "Cannot start without .env file"
    exit 1
fi

# Clear any potentially conflicting environment variables to ensure .env takes precedence
print_info "Clearing conflicting environment variables..."
unset OPENAI_API_KEY OPENAI_BASE_URL OPENAI_MODEL GEMINI_DEFAULT_AUTH_TYPE
unset USE_GEMINI_BRIDGE BRIDGE_TARGET_URL BRIDGE_PORT BRIDGE_DEBUG

# Load .env file
print_info "Loading environment from .env file..."
export $(cat .env | grep -v '^#' | xargs)

# Set default environment variables (only if not already set)
export OPENAI_BASE_URL=${OPENAI_BASE_URL:-"http://localhost:11434/v1"}
export OPENAI_MODEL=${OPENAI_MODEL:-"qwen3-coder:latest"}

# Display configuration
print_info "Configuration:"
echo "  OPENAI_BASE_URL: $OPENAI_BASE_URL"
echo "  OPENAI_MODEL: $OPENAI_MODEL"
echo "  OPENAI_API_KEY: ${OPENAI_API_KEY:+***set***}"

# Get script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check if docker-compose.yml exists
if [ ! -f "$PROJECT_ROOT/docker/docker-compose.yml" ]; then
    print_error "docker-compose.yml not found in docker/ directory"
    print_error "Please ensure project structure is intact"
    exit 1
fi

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_error "Docker is not running or not accessible"
    print_error "Please start Docker and try again"
    exit 1
fi

# Determine compose command
if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose -f $PROJECT_ROOT/docker/docker-compose.yml"
elif docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose -f $PROJECT_ROOT/docker/docker-compose.yml"
else
    print_error "docker-compose or 'docker compose' command not found"
    print_error "Please install Docker Compose and try again"
    exit 1
fi

# Function to check if image needs rebuild
needs_rebuild() {
    # Check if image exists
    if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        print_info "Image does not exist, needs build"
        return 0  # Needs build
    fi
    
    # Get image creation time
    IMAGE_CREATED=$(docker image inspect "$IMAGE_NAME" -f '{{.Created}}' 2>/dev/null | xargs -I {} date -d {} +%s 2>/dev/null || echo 0)
    
    # Check multiple files for modifications
    FILES_TO_CHECK=(
        "$PROJECT_ROOT/docker/Dockerfile"
        "$PROJECT_ROOT/scripts/entrypoint/docker-entrypoint.sh"
        "$PROJECT_ROOT/scripts/entrypoint/docker-healthcheck.sh"
        "$PROJECT_ROOT/scripts/bridge/bridge-health-check.sh"
        "$PROJECT_ROOT/src/bridge/bridge.js"
        "$PROJECT_ROOT/.env"
    )
    
    for file in "${FILES_TO_CHECK[@]}"; do
        if [ -f "$file" ]; then
            FILE_MODIFIED=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo 0)
            if [ "$FILE_MODIFIED" -gt "$IMAGE_CREATED" ]; then
                print_info "$file has been modified, rebuild needed"
                return 0  # Needs rebuild
            fi
        fi
    done
    
    return 1  # No rebuild needed
}

# Function to check container state
get_container_state() {
    if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
        docker container inspect "$CONTAINER_NAME" -f '{{.State.Status}}'
    else
        echo "missing"
    fi
}

# Function to rebuild image and recreate container
rebuild_and_recreate() {
    print_info "Rebuilding image and recreating container..."
    
    # Stop and remove container but keep volumes
    if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
        print_info "Stopping and removing existing container..."
        docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
        docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
    
    # Rebuild image
    print_info "Building new image..."
    $COMPOSE_CMD build --no-cache
    
    print_success "Image rebuilt successfully"
}

# Function to start container and exec into qwen
start_and_exec() {
    print_info "Starting container..."
    $COMPOSE_CMD up -d
    
    # Wait for container to be ready
    print_info "Waiting for container to be ready..."
    for i in {1..10}; do
        if docker exec "$CONTAINER_NAME" test -f /workspace/logs/entrypoint.log 2>/dev/null; then
            if docker exec "$CONTAINER_NAME" grep -q "Entrypoint setup complete" /workspace/logs/entrypoint.log 2>/dev/null; then
                break
            fi
        fi
        sleep 1
    done
    
    exec_into_running
}

# Function to exec into running container
exec_into_running() {
    print_info "Connecting to Qwen CLI..."
    
    # Determine the correct OPENAI_BASE_URL based on bridge status
    USE_BRIDGE=$(docker exec "$CONTAINER_NAME" printenv USE_GEMINI_BRIDGE 2>/dev/null)
    if [ "$USE_BRIDGE" = "true" ]; then
        BRIDGE_PORT=$(docker exec "$CONTAINER_NAME" printenv BRIDGE_PORT 2>/dev/null || echo "8080")
        EXEC_BASE_URL="http://localhost:${BRIDGE_PORT}/v1"
        print_info "Using bridge at: $EXEC_BASE_URL"
    else
        EXEC_BASE_URL="${OPENAI_BASE_URL:-http://localhost:11434/v1}"
        print_info "Using direct connection: $EXEC_BASE_URL"
    fi
    
    # First check if qwen user exists
    if ! docker exec "$CONTAINER_NAME" id qwen >/dev/null 2>&1; then
        print_warning "qwen user not found, using root"
        # Check if qwen command exists
        if docker exec "$CONTAINER_NAME" which qwen >/dev/null 2>&1; then
            print_success "Launching Qwen CLI as root..."
            docker exec -it \
                -e OPENAI_BASE_URL="$EXEC_BASE_URL" \
                -e OPENAI_API_KEY="$OPENAI_API_KEY" \
                -e OPENAI_MODEL="$OPENAI_MODEL" \
                -e TERM=xterm-256color \
                "$CONTAINER_NAME" bash -c "stty sane; stty echo; exec qwen"
        else
            print_info "Dropping you into bash shell as root..."
            docker exec -it "$CONTAINER_NAME" bash
        fi
    else
        # qwen user exists, use it
        if docker exec -u qwen "$CONTAINER_NAME" which qwen >/dev/null 2>&1; then
            print_success "Launching Qwen CLI as qwen user (with sudo access)..."
            docker exec -it -u qwen \
                -e OPENAI_BASE_URL="$EXEC_BASE_URL" \
                -e OPENAI_API_KEY="$OPENAI_API_KEY" \
                -e OPENAI_MODEL="$OPENAI_MODEL" \
                -e TERM=xterm-256color \
                "$CONTAINER_NAME" bash -c "stty sane; stty echo; exec qwen"
        else
            print_error "qwen command not found"
            print_info "Dropping you into bash shell as qwen user (with sudo access)..."
            docker exec -it -u qwen \
                -e OPENAI_BASE_URL="$EXEC_BASE_URL" \
                -e OPENAI_API_KEY="$OPENAI_API_KEY" \
                -e OPENAI_MODEL="$OPENAI_MODEL" \
                "$CONTAINER_NAME" bash
        fi
    fi
}

# Create empty gitconfig if it doesn't exist to prevent mount errors
if [ ! -f "$HOME/.gitconfig" ]; then
    print_info "Creating empty .gitconfig file for container mount"
    touch "$HOME/.gitconfig"
fi

# Main logic
print_info "Checking container and image status..."

CONTAINER_STATE=$(get_container_state)
print_info "Container state: $CONTAINER_STATE"

# Check if rebuild is needed or forced
if [ "$FORCE_REBUILD" = true ] || needs_rebuild; then
    if [ "$FORCE_REBUILD" = true ]; then
        print_warning "Forcing rebuild as requested"
    fi
    rebuild_and_recreate
    start_and_exec
else
    case "$CONTAINER_STATE" in
        "running")
            print_info "Container is already running"
            exec_into_running
            ;;
        "exited"|"stopped")
            print_info "Container exists but is stopped, starting it..."
            docker start "$CONTAINER_NAME"
            sleep 2  # Give container time to start
            exec_into_running
            ;;
        "missing")
            print_info "Container does not exist, creating it..."
            start_and_exec
            ;;
        "restarting")
            print_warning "Container is in restart loop, checking logs..."
            docker logs "$CONTAINER_NAME" --tail 20 2>&1 | sed 's/^/  /'
            print_info "Stopping and removing the failed container..."
            docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
            docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
            print_info "Rebuilding and starting fresh..."
            rebuild_and_recreate
            start_and_exec
            ;;
        *)
            print_warning "Unknown container state: $CONTAINER_STATE"
            print_info "Attempting to start container anyway..."
            start_and_exec
            ;;
    esac
fi