#!/usr/bin/env fish

# Qwen Code Docker Startup Script (Fish Shell)
# Handles container states, rebuilds, and data persistence

set -l RED '\033[0;31m'
set -l GREEN '\033[0;32m'
set -l YELLOW '\033[1;33m'
set -l BLUE '\033[0;34m'
set -l NC '\033[0m' # No Color

function print_info
    echo -e "$BLUE[INFO]$NC $argv"
end

function print_success
    echo -e "$GREEN[SUCCESS]$NC $argv"
end

function print_warning
    echo -e "$YELLOW[WARNING]$NC $argv"
end

function print_error
    echo -e "$RED[ERROR]$NC $argv"
end

# Check for --rebuild flag
set -l FORCE_REBUILD false
if test "$argv[1]" = "--rebuild"; or test "$argv[1]" = "-r"
    set FORCE_REBUILD true
    print_info "Force rebuild requested"
end

print_info "Starting Qwen Code Docker Environment..."

# Check if .env exists, run setup if not
if not test -f .env
    print_warning ".env file not found. Please create one manually or run the setup wizard"
    print_error "Create a .env file with your configuration"
    exit 1
end

# Clear any potentially conflicting environment variables
print_info "Clearing conflicting environment variables..."
set -e OPENAI_API_KEY OPENAI_BASE_URL OPENAI_MODEL GEMINI_DEFAULT_AUTH_TYPE
set -e USE_GEMINI_BRIDGE BRIDGE_TARGET_URL BRIDGE_PORT BRIDGE_DEBUG

# Load .env file (Fish doesn't have built-in .env support)
print_info "Loading environment from .env file..."
for line in (cat .env | grep -v '^#' | grep -v '^$')
    set -l key_value (string split '=' $line)
    if test (count $key_value) -ge 2
        set -gx $key_value[1] $key_value[2]
    end
end

# Set default environment variables
set -q OPENAI_BASE_URL; or set -gx OPENAI_BASE_URL "http://localhost:11434/v1"
set -q OPENAI_MODEL; or set -gx OPENAI_MODEL "qwen3-coder:latest"

# Display configuration
print_info "Configuration:"
echo "  OPENAI_BASE_URL: $OPENAI_BASE_URL"
echo "  OPENAI_MODEL: $OPENAI_MODEL"
if set -q OPENAI_API_KEY
    echo "  OPENAI_API_KEY: ***set***"
else
    echo "  OPENAI_API_KEY: ***not set***"
end

# Execute the main start script
print_info "Executing main startup script..."
exec ./scripts/start.sh $argv