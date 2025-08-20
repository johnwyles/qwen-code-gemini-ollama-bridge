#!/usr/bin/env zsh

# Qwen Code Docker Startup Script (Zsh)
# Handles container states, rebuilds, and data persistence

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

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check for --rebuild flag
FORCE_REBUILD=false
if [[ "$1" == "--rebuild" ]] || [[ "$1" == "-r" ]]; then
    FORCE_REBUILD=true
    print_info "Force rebuild requested"
fi

print_info "Starting Qwen Code Docker Environment..."

# Check if .env exists, run setup if not
if [[ ! -f .env ]]; then
    print_warning ".env file not found. Please create one manually or run the setup wizard"
    print_error "Create a .env file with your configuration"
    exit 1
fi

# Clear any potentially conflicting environment variables
print_info "Clearing conflicting environment variables..."
unset OPENAI_API_KEY OPENAI_BASE_URL OPENAI_MODEL GEMINI_DEFAULT_AUTH_TYPE
unset USE_GEMINI_BRIDGE BRIDGE_TARGET_URL BRIDGE_PORT BRIDGE_DEBUG

# Load .env file
print_info "Loading environment from .env file..."
set -a
source .env
set +a

# Set default environment variables
export OPENAI_BASE_URL=${OPENAI_BASE_URL:-"http://localhost:11434/v1"}
export OPENAI_MODEL=${OPENAI_MODEL:-"qwen3-coder:latest"}

# Display configuration
print_info "Configuration:"
echo "  OPENAI_BASE_URL: $OPENAI_BASE_URL"
echo "  OPENAI_MODEL: $OPENAI_MODEL"
echo "  OPENAI_API_KEY: ${OPENAI_API_KEY:+***set***}"

# Execute the main start script
print_info "Executing main startup script..."
exec ./scripts/start.sh "$@"