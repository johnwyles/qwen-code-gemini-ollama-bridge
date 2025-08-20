#!/bin/bash

# Integration Test Utilities
# Shared functions for qwen-code CLI integration testing

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Test tracking
TEST_COUNT=0
PASSED_COUNT=0
FAILED_COUNT=0
WARNING_COUNT=0

# Container and image names
CONTAINER_NAME="qwen-code-test"
IMAGE_NAME="qwen-code-docker-qwen-code"
COMPOSE_CMD=""

# Determine compose command
init_docker_compose() {
    if command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    elif docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    else
        log_error "docker-compose or 'docker compose' command not found"
        exit 1
    fi
}

# Logging functions
log() {
    local color=$1
    shift
    echo -e "${color}[$(date +'%H:%M:%S')] $*${NC}"
}

log_info() { log $BLUE "$*"; }
log_success() { log $GREEN "$*"; }
log_warning() { log $YELLOW "$*"; }
log_error() { log $RED "$*"; }
log_test() { log $CYAN "$*"; }
log_debug() { 
    if [ "${TEST_DEBUG:-false}" = "true" ]; then
        log $PURPLE "DEBUG: $*"
    fi
}

# Test result functions
test_start() {
    TEST_COUNT=$((TEST_COUNT + 1))
    log_test "Test $TEST_COUNT: $1"
}

test_pass() {
    PASSED_COUNT=$((PASSED_COUNT + 1))
    log_success "✅ $1"
}

test_fail() {
    FAILED_COUNT=$((FAILED_COUNT + 1))
    log_error "❌ $1"
    if [ "${TEST_FAIL_FAST:-false}" = "true" ]; then
        exit 1
    fi
}

test_warning() {
    WARNING_COUNT=$((WARNING_COUNT + 1))
    log_warning "⚠️  $1"
}

# Test summary
test_summary() {
    echo
    log_info "=========================================="
    log_info "TEST SUMMARY"
    log_info "=========================================="
    log_info "Total Tests: $TEST_COUNT"
    log_success "Passed: $PASSED_COUNT"
    log_error "Failed: $FAILED_COUNT"
    log_warning "Warnings: $WARNING_COUNT"
    
    if [ $FAILED_COUNT -eq 0 ]; then
        log_success "🎉 All tests passed!"
        return 0
    else
        log_error "💥 $FAILED_COUNT test(s) failed"
        return 1
    fi
}

# Container management functions
cleanup_container() {
    local container_name=${1:-$CONTAINER_NAME}
    log_debug "Cleaning up container: $container_name"
    
    if docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
        docker stop "$container_name" >/dev/null 2>&1 || true
        docker rm "$container_name" >/dev/null 2>&1 || true
        log_debug "Container $container_name cleaned up"
    fi
}

start_container() {
    local env_file=${1:-.env}
    local container_name=${2:-$CONTAINER_NAME}
    
    log_debug "Starting container $container_name with env: $env_file"
    
    # Stop existing container
    cleanup_container "$container_name"
    
    # Start container with environment
    if [ -f "$env_file" ]; then
        $COMPOSE_CMD --env-file "$env_file" up -d
    else
        $COMPOSE_CMD up -d
    fi
    
    # Wait for container to be ready
    wait_for_container "$container_name"
}

wait_for_container() {
    local container_name=${1:-$CONTAINER_NAME}
    local max_wait=${2:-30}
    local count=0
    
    log_debug "Waiting for container $container_name to be ready..."
    
    while [ $count -lt $max_wait ]; do
        if docker exec "$container_name" echo "ready" >/dev/null 2>&1; then
            log_debug "Container $container_name is ready"
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    
    log_error "Container $container_name not ready after ${max_wait}s"
    return 1
}

# Bridge management functions
wait_for_bridge() {
    local port=${1:-8080}
    local max_wait=${2:-15}
    local count=0
    
    log_debug "Waiting for bridge on port $port..."
    
    while [ $count -lt $max_wait ]; do
        if curl -s http://localhost:$port/health >/dev/null 2>&1; then
            log_debug "Bridge is ready on port $port"
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    
    log_error "Bridge not ready on port $port after ${max_wait}s"
    return 1
}

check_bridge_health() {
    local port=${1:-8080}
    local response
    
    if ! response=$(curl -s http://localhost:$port/health 2>/dev/null); then
        return 1
    fi
    
    # Check if response contains expected fields
    if echo "$response" | grep -q '"status":"healthy"' && echo "$response" | grep -q '"bridge":"gemini-openai-bridge"'; then
        return 0
    else
        return 1
    fi
}

# Request validation functions
validate_last_request() {
    local log_file=${1:-/tmp/mock-ollama-requests.log}
    local expected_format=${2:-openai}
    
    if [ ! -f "$log_file" ]; then
        log_error "Request log file not found: $log_file"
        return 1
    fi
    
    # Get last line from log file
    local last_request
    last_request=$(tail -n 1 "$log_file" 2>/dev/null || echo "")
    
    if [ -z "$last_request" ]; then
        log_error "No requests found in log file"
        return 1
    fi
    
    # Parse JSON to check for Gemini fields
    local has_gemini_fields=false
    if echo "$last_request" | grep -q '"generationConfig"\|"safetySettings"\|"systemInstruction"\|"toolConfig"'; then
        has_gemini_fields=true
    fi
    
    # Validate expected format
    if [ "$expected_format" = "openai" ] && [ "$has_gemini_fields" = true ]; then
        log_error "Expected OpenAI format but found Gemini fields"
        echo "$last_request" | jq '.body' 2>/dev/null || echo "$last_request"
        return 1
    fi
    
    if [ "$expected_format" = "gemini" ] && [ "$has_gemini_fields" = false ]; then
        log_error "Expected Gemini format but found pure OpenAI format"
        return 1
    fi
    
    # Check token limits
    local max_tokens
    max_tokens=$(echo "$last_request" | jq -r '.body.max_tokens // empty' 2>/dev/null || echo "")
    if [ -n "$max_tokens" ] && [ "$max_tokens" -gt 50000 ]; then
        log_warning "Found excessive token request: $max_tokens"
    fi
    
    return 0
}

# Environment setup functions
create_test_env() {
    local env_file=$1
    local use_bridge=${2:-false}
    local bridge_port=${3:-8080}
    local target_url=${4:-http://localhost:8443/v1}
    
    cat > "$env_file" << EOF
# Test environment configuration
OPENAI_BASE_URL=$target_url
OPENAI_API_KEY=test-api-key
OPENAI_MODEL=qwen3-coder:latest
GEMINI_DEFAULT_AUTH_TYPE=openai

# Bridge configuration
USE_GEMINI_BRIDGE=$use_bridge
BRIDGE_TARGET_URL=$target_url
BRIDGE_PORT=$bridge_port
BRIDGE_DEBUG=true
EOF
    
    log_debug "Created test environment: $env_file"
}

# qwen-code execution functions
run_qwen_command() {
    local container_name=${1:-$CONTAINER_NAME}
    local command=${2:-"echo 'Hello from qwen-code'"}
    local timeout=${3:-30}
    
    log_debug "Running qwen command in $container_name: $command"
    
    # Create a temporary script file
    local script_file="/tmp/qwen-test-cmd-$$.sh"
    cat > "$script_file" << EOF
#!/bin/bash
set -euo pipefail
cd /workspace
echo "$command" | timeout $timeout qwen-code --non-interactive 2>&1 || echo "QWEN_ERROR: \$?"
EOF
    
    # Copy script to container and execute
    docker cp "$script_file" "$container_name:/tmp/test-cmd.sh"
    docker exec "$container_name" chmod +x /tmp/test-cmd.sh
    local result
    result=$(docker exec "$container_name" /tmp/test-cmd.sh 2>&1 || echo "EXEC_ERROR: $?")
    
    # Cleanup
    rm -f "$script_file"
    docker exec "$container_name" rm -f /tmp/test-cmd.sh >/dev/null 2>&1 || true
    
    echo "$result"
}

check_qwen_process() {
    local container_name=${1:-$CONTAINER_NAME}
    
    if docker exec "$container_name" pgrep -f "qwen" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

check_bridge_process() {
    local container_name=${1:-$CONTAINER_NAME}
    
    if docker exec "$container_name" pgrep -f "bridge.js" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# File and log helpers
get_container_logs() {
    local container_name=${1:-$CONTAINER_NAME}
    local lines=${2:-50}
    
    docker logs "$container_name" --tail "$lines" 2>&1 || echo "Failed to get logs"
}

create_temp_workspace() {
    local workspace_dir="/tmp/qwen-test-workspace-$$"
    mkdir -p "$workspace_dir"
    echo "$workspace_dir"
}

cleanup_temp_workspace() {
    local workspace_dir=$1
    if [ -n "$workspace_dir" ] && [ -d "$workspace_dir" ]; then
        rm -rf "$workspace_dir"
    fi
}

# Docker compose helpers with env files
compose_up_with_env() {
    local env_file=$1
    local service=${2:-qwen-code}
    
    log_debug "Starting compose with env file: $env_file"
    $COMPOSE_CMD --env-file "$env_file" up -d "$service"
}

compose_down() {
    local env_file=${1:-.env}
    
    log_debug "Stopping compose"
    if [ -f "$env_file" ]; then
        $COMPOSE_CMD --env-file "$env_file" down >/dev/null 2>&1 || true
    else
        $COMPOSE_CMD down >/dev/null 2>&1 || true
    fi
}

# Initialize on source
init_docker_compose