#!/bin/bash

# Integration Test: qwen-code CLI Direct Connection
# Tests qwen-code CLI without the Gemini-OpenAI bridge

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source utilities
source "$SCRIPT_DIR/utils.sh"

# Test configuration
TEST_NAME="CLI Direct Connection"
MOCK_SERVER_PORT=8443
MOCK_LOG_FILE="/tmp/mock-ollama-direct-test.log"
TEST_ENV_FILE="/tmp/test-direct.env"
MOCK_SERVER_PID=""

cleanup() {
    log_info "Cleaning up direct connection test..."
    
    # Stop mock server
    if [ -n "$MOCK_SERVER_PID" ]; then
        kill "$MOCK_SERVER_PID" 2>/dev/null || true
        wait "$MOCK_SERVER_PID" 2>/dev/null || true
    fi
    
    # Stop and remove test container
    cleanup_container "$CONTAINER_NAME"
    
    # Remove test files
    rm -f "$TEST_ENV_FILE" "$MOCK_LOG_FILE"
    
    log_info "Direct connection test cleanup complete"
}

trap cleanup EXIT

main() {
    log_info "=========================================="
    log_info "Starting $TEST_NAME Test"
    log_info "=========================================="
    
    cd "$PROJECT_ROOT"
    
    # Test 1: Setup mock server
    test_start "Starting mock Ollama server"
    node "$SCRIPT_DIR/mock-ollama-server.js" &
    MOCK_SERVER_PID=$!
    
    # Wait for mock server to start
    local count=0
    while [ $count -lt 10 ]; do
        if curl -s http://localhost:$MOCK_SERVER_PORT/health >/dev/null 2>&1; then
            test_pass "Mock Ollama server started on port $MOCK_SERVER_PORT"
            break
        fi
        sleep 1
        count=$((count + 1))
    done
    
    if [ $count -eq 10 ]; then
        test_fail "Mock server failed to start"
        return 1
    fi
    
    # Test 2: Create test environment without bridge
    test_start "Creating test environment (bridge disabled)"
    create_test_env "$TEST_ENV_FILE" false 8080 "http://localhost:$MOCK_SERVER_PORT/v1"
    test_pass "Test environment created"
    
    # Test 3: Start container with direct connection
    test_start "Starting container with direct connection"
    
    # Override container name for testing
    export COMPOSE_PROJECT_NAME="qwen-test-direct"
    CONTAINER_NAME="qwen-test-direct-qwen-code-1"
    
    if compose_up_with_env "$TEST_ENV_FILE"; then
        test_pass "Container started successfully"
    else
        test_fail "Failed to start container"
        return 1
    fi
    
    # Test 4: Verify no bridge process is running
    test_start "Verifying bridge is NOT running"
    sleep 3  # Give container time to fully start
    
    if check_bridge_process "$CONTAINER_NAME"; then
        test_fail "Bridge process is running (should be disabled)"
    else
        test_pass "Bridge process is not running (correct)"
    fi
    
    # Test 5: Verify environment variables
    test_start "Checking environment variables in container"
    local use_bridge
    use_bridge=$(docker exec "$CONTAINER_NAME" printenv USE_GEMINI_BRIDGE 2>/dev/null || echo "")
    
    if [ "$use_bridge" = "false" ] || [ "$use_bridge" = "" ]; then
        test_pass "Bridge correctly disabled in container"
    else
        test_warning "Bridge setting in container: $use_bridge"
    fi
    
    # Test 6: Test qwen-code CLI direct connection
    test_start "Testing qwen-code CLI direct connection"
    
    # Clear mock server logs
    rm -f "$MOCK_LOG_FILE"
    
    # Run a simple qwen command
    local qwen_output
    qwen_output=$(run_qwen_command "$CONTAINER_NAME" "What is 2+2?" 10 2>&1 || echo "COMMAND_FAILED")
    
    log_debug "qwen-code output: $qwen_output"
    
    # Check if qwen connected (should see request in mock server)
    sleep 2
    
    if [ -f "$MOCK_LOG_FILE" ] && [ -s "$MOCK_LOG_FILE" ]; then
        test_pass "qwen-code made request to mock server"
        
        # Test 7: Validate request format (should be Gemini format)
        test_start "Validating request format (expecting Gemini format)"
        
        if validate_last_request "$MOCK_LOG_FILE" "gemini"; then
            test_pass "Request contains Gemini fields (direct connection working)"
        else
            test_warning "Request format unexpected - check mock server logs"
            log_debug "Last request: $(tail -n 1 "$MOCK_LOG_FILE")"
        fi
    else
        test_fail "No requests received by mock server"
        log_debug "Container logs:"
        get_container_logs "$CONTAINER_NAME" 10
    fi
    
    # Test 8: Check for excessive token requests
    test_start "Checking for excessive token requests"
    if grep -q '"max_tokens":[[:space:]]*[0-9]\{6,\}' "$MOCK_LOG_FILE" 2>/dev/null; then
        test_warning "Found excessive token request (>100k tokens) - this is expected for direct connection"
    else
        test_pass "No excessive token requests found"
    fi
    
    # Test 9: Verify direct URL connection
    test_start "Verifying container connects to mock server directly"
    local openai_url
    openai_url=$(docker exec "$CONTAINER_NAME" printenv OPENAI_BASE_URL 2>/dev/null || echo "")
    
    if echo "$openai_url" | grep -q "localhost:$MOCK_SERVER_PORT"; then
        test_pass "Container configured to connect directly to mock server"
    else
        test_warning "Container OPENAI_BASE_URL: $openai_url"
    fi
    
    # Test 10: Container logs check
    test_start "Checking container logs for errors"
    local logs
    logs=$(get_container_logs "$CONTAINER_NAME" 20)
    
    if echo "$logs" | grep -qi "error\|fail\|exception"; then
        test_warning "Found potential errors in container logs"
        log_debug "Container logs: $logs"
    else
        test_pass "No obvious errors in container logs"
    fi
    
    log_info "Direct connection test completed"
    return 0
}

# Run tests
main "$@"

# Show summary
if test_summary; then
    exit 0
else
    exit 1
fi