#!/bin/bash

# Qwen Code Docker Test Runner
# Runs all available tests: connection tests, unit tests, and integration tests

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

print_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

print_separator() {
    echo -e "${CYAN}================================================${NC}"
}

# Load environment variables with defaults
export OLLAMA_HOST=${OLLAMA_HOST:-"localhost"}
export OLLAMA_PORT=${OLLAMA_PORT:-"8443"}

# Build endpoint URL
if [ -n "$CUSTOM_ENDPOINT" ]; then
    export OPENAI_BASE_URL="$CUSTOM_ENDPOINT"
else
    export OPENAI_BASE_URL="https://${OLLAMA_HOST}:${OLLAMA_PORT}/v1"
fi

print_separator
print_info "Qwen Code Docker Test Suite"
print_separator

# Display current configuration
print_info "Current Configuration:"
echo "  OLLAMA_HOST: $OLLAMA_HOST"
echo "  OLLAMA_PORT: $OLLAMA_PORT"
echo "  OPENAI_BASE_URL: $OPENAI_BASE_URL"
if [ -n "$CUSTOM_ENDPOINT" ]; then
    echo "  CUSTOM_ENDPOINT: $CUSTOM_ENDPOINT"
fi
echo ""

# Test 1: Check if required tools are available
print_test "Checking required tools..."

# Check curl
if command -v curl >/dev/null 2>&1; then
    print_success "curl is available"
else
    print_error "curl is not installed or not in PATH"
    exit 1
fi

# Check jq (optional but helpful)
if command -v jq >/dev/null 2>&1; then
    print_success "jq is available for JSON parsing"
    HAS_JQ=true
else
    print_warning "jq not found - JSON responses will be shown raw"
    HAS_JQ=false
fi

echo ""

# Test 2: Basic connectivity test
print_test "Testing basic connectivity to $OLLAMA_HOST:$OLLAMA_PORT..."

if curl -k -s --connect-timeout 10 --max-time 30 "https://${OLLAMA_HOST}:${OLLAMA_PORT}" >/dev/null 2>&1; then
    print_success "Successfully connected to $OLLAMA_HOST:$OLLAMA_PORT"
else
    print_error "Failed to connect to $OLLAMA_HOST:$OLLAMA_PORT"
    print_warning "This could be due to network issues, firewall, or the service being down"
fi

echo ""

# Test 3: API endpoint test
print_test "Testing API endpoint: $OPENAI_BASE_URL..."

API_RESPONSE=$(curl -k -s --connect-timeout 10 --max-time 30 \
    -H "Content-Type: application/json" \
    "$OPENAI_BASE_URL" 2>/dev/null || echo "CURL_ERROR")

if [ "$API_RESPONSE" = "CURL_ERROR" ]; then
    print_error "Failed to reach API endpoint"
else
    print_success "API endpoint is reachable"
    if [ "$HAS_JQ" = true ]; then
        echo "Response (formatted):"
        echo "$API_RESPONSE" | jq . 2>/dev/null || echo "$API_RESPONSE"
    else
        echo "Response: $API_RESPONSE"
    fi
fi

echo ""

# Test 4: Models endpoint test
print_test "Testing models endpoint..."

MODELS_URL="${OPENAI_BASE_URL}/models"
MODELS_RESPONSE=$(curl -k -s --connect-timeout 10 --max-time 30 \
    -H "Content-Type: application/json" \
    "$MODELS_URL" 2>/dev/null || echo "CURL_ERROR")

if [ "$MODELS_RESPONSE" = "CURL_ERROR" ]; then
    print_error "Failed to reach models endpoint"
else
    print_success "Models endpoint is reachable"
    if [ "$HAS_JQ" = true ] && echo "$MODELS_RESPONSE" | jq . >/dev/null 2>&1; then
        echo "Available models:"
        echo "$MODELS_RESPONSE" | jq -r '.data[]? | "  - " + .id' 2>/dev/null || echo "  Could not parse models list"
    else
        echo "Raw response: $MODELS_RESPONSE"
    fi
fi

echo ""

# Test 5: Docker containers status (if running in Docker environment)
print_test "Checking Docker containers status..."

if command -v docker >/dev/null 2>&1; then
    if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | grep -q "qwen\|coder" 2>/dev/null; then
        print_success "Found running Qwen Coder containers:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(NAME|qwen|coder)" || true
    else
        print_warning "No Qwen Coder containers found running"
        print_info "You may need to run the startup script first"
    fi
else
    print_warning "Docker not available - skipping container check"
fi

echo ""

# Test 6: Environment validation
print_test "Validating environment configuration..."

# Check for common configuration issues
if [[ "$OPENAI_BASE_URL" == *"localhost"* ]] || [[ "$OPENAI_BASE_URL" == *"127.0.0.1"* ]]; then
    print_warning "Using localhost endpoint - ensure the service is running locally"
fi

if [[ "$OPENAI_BASE_URL" == "http://"* ]]; then
    print_warning "Using HTTP (not HTTPS) - this may cause security warnings"
fi

if [ ${#OPENAI_BASE_URL} -gt 100 ]; then
    print_warning "Very long endpoint URL - please verify it's correct"
fi

print_success "Environment validation complete"

echo ""
print_separator
print_info "Connection tests completed!"
print_separator

# Parse command line arguments for test selection
RUN_CONNECTION=true
RUN_INTEGRATION=true
RUN_UNIT=true
SHOW_HELP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --connection-only)
            RUN_INTEGRATION=false
            RUN_UNIT=false
            shift
            ;;
        --integration-only)
            RUN_CONNECTION=false
            RUN_UNIT=false
            shift
            ;;
        --unit-only)
            RUN_CONNECTION=false
            RUN_INTEGRATION=false
            shift
            ;;
        --skip-connection)
            RUN_CONNECTION=false
            shift
            ;;
        --skip-integration)
            RUN_INTEGRATION=false
            shift
            ;;
        --skip-unit)
            RUN_UNIT=false
            shift
            ;;
        --help)
            SHOW_HELP=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            SHOW_HELP=true
            shift
            ;;
    esac
done

if [ "$SHOW_HELP" = true ]; then
    echo ""
    print_info "Usage: $0 [OPTIONS]"
    echo ""
    echo "Test Selection:"
    echo "  --connection-only     Run only connection tests"
    echo "  --integration-only    Run only integration tests"
    echo "  --unit-only          Run only unit tests"
    echo "  --skip-connection    Skip connection tests"
    echo "  --skip-integration   Skip integration tests"
    echo "  --skip-unit         Skip unit tests"
    echo "  --help              Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                           # Run all tests"
    echo "  $0 --integration-only        # Run only Docker integration tests"
    echo "  $0 --skip-connection         # Skip basic connection tests"
    exit 0
fi

# Determine script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Track overall results
OVERALL_SUCCESS=true

# Run bridge unit tests
if [ "$RUN_UNIT" = true ]; then
    echo ""
    print_separator
    print_info "Running Bridge Unit Tests"
    print_separator
    
    if [ -f "$PROJECT_ROOT/gemini-openai-bridge/package.json" ]; then
        cd "$PROJECT_ROOT/gemini-openai-bridge"
        if npm test; then
            print_success "Bridge unit tests passed"
        else
            print_error "Bridge unit tests failed"
            OVERALL_SUCCESS=false
        fi
        cd "$PROJECT_ROOT"
    else
        print_warning "Bridge unit tests not found"
    fi
fi

# Run integration tests
if [ "$RUN_INTEGRATION" = true ]; then
    echo ""
    print_separator
    print_info "Running Integration Tests"
    print_separator
    
    if [ -f "$SCRIPT_DIR/integration/test-e2e.sh" ]; then
        if bash "$SCRIPT_DIR/integration/test-e2e.sh"; then
            print_success "Integration tests passed"
        else
            print_error "Integration tests failed"
            OVERALL_SUCCESS=false
        fi
    else
        print_warning "Integration tests not found"
    fi
fi

# Final summary
echo ""
print_separator
if [ "$OVERALL_SUCCESS" = true ]; then
    print_success "🎉 ALL TESTS PASSED!"
    print_info "Your qwen-code Docker setup is working correctly"
else
    print_error "💥 SOME TESTS FAILED"
    print_error "Check the output above for details"
fi
print_separator

# Summary
echo ""
print_info "Summary:"
echo "  Endpoint: $OPENAI_BASE_URL"
echo "  Host: $OLLAMA_HOST"
echo "  Port: $OLLAMA_PORT"

if [ -f "../docker-compose.yml" ]; then
    echo ""
    print_info "To start the environment, run: ../start.sh"
elif [ -f "./docker-compose.yml" ]; then
    echo ""
    print_info "To start the environment, run: ./start.sh"
else
    echo ""
    print_warning "docker-compose.yml not found - ensure you're in the correct directory"
fi

# Exit with appropriate code
if [ "$OVERALL_SUCCESS" = true ]; then
    exit 0
else
    exit 1
fi