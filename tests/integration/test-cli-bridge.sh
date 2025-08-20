#!/bin/bash

# Integration Test: qwen-code CLI with Gemini-OpenAI Bridge
# Tests qwen-code CLI with bridge enabled for request translation

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source utilities
source "$SCRIPT_DIR/utils.sh"

# Test configuration
TEST_NAME="CLI Bridge Connection"
MOCK_SERVER_PORT=8443
BRIDGE_PORT=8080
MOCK_LOG_FILE="/tmp/mock-ollama-bridge-test.log"
TEST_ENV_FILE="/tmp/test-bridge.env"
MOCK_SERVER_PID=""

cleanup() {
    log_info "Cleaning up bridge connection test..."
    
    # Stop mock server
    if [ -n "$MOCK_SERVER_PID" ]; then
        kill "$MOCK_SERVER_PID" 2>/dev/null || true
        wait "$MOCK_SERVER_PID" 2>/dev/null || true
    fi
    
    # Stop and remove test container
    cleanup_container "$CONTAINER_NAME"
    
    # Remove test files
    rm -f "$TEST_ENV_FILE" "$MOCK_LOG_FILE"
    
    log_info "Bridge connection test cleanup complete"
}

trap cleanup EXIT

main() {
    log_info "=========================================="
    log_info "Starting $TEST_NAME Test"
    log_info "=========================================="
    
    cd "$PROJECT_ROOT"
    
    # Test 1: Setup mock server
    test_start "Starting mock Ollama server"
    MOCK_PORT=$MOCK_SERVER_PORT MOCK_LOG_FILE=$MOCK_LOG_FILE node "$SCRIPT_DIR/mock-ollama-server.js" &
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
    
    # Test 2: Create test environment with bridge enabled
    test_start "Creating test environment (bridge enabled)"
    create_test_env "$TEST_ENV_FILE" true $BRIDGE_PORT "http://localhost:$MOCK_SERVER_PORT/v1"
    
    # Update env to redirect qwen-code through bridge
    cat >> "$TEST_ENV_FILE" << EOF

# Override qwen-code to use bridge instead of direct connection
OPENAI_BASE_URL=http://localhost:$BRIDGE_PORT/v1
EOF
    
    test_pass "Test environment created with bridge enabled"
    
    # Test 3: Start container with bridge
    test_start "Starting container with bridge enabled"
    
    # Override container name for testing
    export COMPOSE_PROJECT_NAME="qwen-test-bridge"
    CONTAINER_NAME="qwen-test-bridge-qwen-code-1"
    
    if compose_up_with_env "$TEST_ENV_FILE"; then
        test_pass "Container started successfully"
    else
        test_fail "Failed to start container"
        return 1
    fi
    
    # Test 4: Wait for container and bridge to be ready
    test_start "Waiting for container and bridge startup"
    
    if wait_for_container "$CONTAINER_NAME" 30; then
        test_pass "Container is ready"
    else
        test_fail "Container not ready"
        log_debug "Container logs:"
        get_container_logs "$CONTAINER_NAME" 20
        return 1
    fi
    
    # Give bridge extra time to start
    sleep 5
    
    # Test 5: Verify bridge process is running
    test_start "Verifying bridge process is running"
    
    if check_bridge_process "$CONTAINER_NAME"; then
        test_pass "Bridge process is running"
    else
        test_fail "Bridge process is not running"
        log_debug "Container processes:"
        docker exec "$CONTAINER_NAME" ps aux 2>/dev/null || true
        return 1
    fi
    
    # Test 6: Check bridge health endpoint
    test_start "Testing bridge health endpoint"
    
    local bridge_health
    bridge_health=$(docker exec "$CONTAINER_NAME" curl -s http://localhost:$BRIDGE_PORT/health 2>/dev/null || echo "CURL_FAILED")
    
    if echo "$bridge_health" | grep -q '"status":"healthy"'; then
        test_pass "Bridge health endpoint responding"
        log_debug "Bridge health: $bridge_health"
    else
        test_fail "Bridge health endpoint not responding"
        log_debug "Bridge health response: $bridge_health"
        return 1
    fi
    
    # Test 7: Verify environment variables
    test_start "Checking bridge environment variables in container"
    
    local use_bridge
    use_bridge=$(docker exec "$CONTAINER_NAME" printenv USE_GEMINI_BRIDGE 2>/dev/null || echo "")
    
    if [ "$use_bridge" = "true" ]; then
        test_pass "Bridge correctly enabled in container"
    else
        test_fail "Bridge setting in container: $use_bridge (expected: true)"
    fi
    
    # Test 8: Verify qwen-code connects through bridge
    test_start "Checking qwen-code OPENAI_BASE_URL points to bridge"
    
    local qwen_url
    qwen_url=$(docker exec "$CONTAINER_NAME" printenv OPENAI_BASE_URL 2>/dev/null || echo "")
    
    if echo "$qwen_url" | grep -q "localhost:$BRIDGE_PORT"; then
        test_pass "qwen-code configured to use bridge"
    else
        test_warning "qwen-code URL: $qwen_url (expected to contain localhost:$BRIDGE_PORT)"
    fi
    
    # Test 9: Test qwen-code CLI through bridge
    test_start "Testing qwen-code CLI through bridge"
    
    # Clear mock server logs
    rm -f "$MOCK_LOG_FILE"
    
    # Run a simple qwen command
    local qwen_output
    qwen_output=$(run_qwen_command "$CONTAINER_NAME" "What is 2+2?" 10 2>&1 || echo "COMMAND_FAILED")
    
    log_debug "qwen-code output: $qwen_output"
    
    # Wait for request to be processed
    sleep 3
    
    if [ -f "$MOCK_LOG_FILE" ] && [ -s "$MOCK_LOG_FILE" ]; then
        test_pass "qwen-code made request through bridge to mock server"
        
        # Test 10: Validate request format (should be OpenAI format due to bridge)
        test_start "Validating request format (expecting OpenAI format)"
        
        if validate_last_request "$MOCK_LOG_FILE" "openai"; then
            test_pass "Request in clean OpenAI format (bridge working correctly)"
        else
            test_fail "Request format validation failed"
            log_debug "Last request: $(tail -n 1 "$MOCK_LOG_FILE" | jq '.body' 2>/dev/null || tail -n 1 "$MOCK_LOG_FILE")"
        fi
        
        # Test 11: Check token limits were capped
        test_start "Checking token limits were capped by bridge"
        
        local max_tokens
        max_tokens=$(tail -n 1 "$MOCK_LOG_FILE" | jq -r '.body.max_tokens // empty' 2>/dev/null || echo "")
        
        if [ -n "$max_tokens" ] && [ "$max_tokens" -le 10000 ]; then
            test_pass "Token limits properly capped by bridge: $max_tokens"
        elif [ -z "$max_tokens" ]; then
            test_pass "No max_tokens field (acceptable)"
        else
            test_fail "Token limits not capped: $max_tokens"
        fi
        
        # Test 12: Check Gemini fields were removed
        test_start "Verifying Gemini fields were stripped"
        
        local last_request
        last_request=$(tail -n 1 "$MOCK_LOG_FILE" 2>/dev/null || echo "")
        
        if echo "$last_request" | grep -q '"generationConfig"\|"safetySettings"\|"systemInstruction"'; then
            test_fail "Found Gemini fields in request (bridge not working)"
            log_debug "Request body: $(echo "$last_request" | jq '.body' 2>/dev/null || echo "$last_request")"
        else
            test_pass "Gemini fields successfully stripped by bridge"
        fi
        
    else
        test_fail "No requests received by mock server"
        log_debug "Container logs:"
        get_container_logs "$CONTAINER_NAME" 15
        log_debug "Bridge logs:"
        docker exec "$CONTAINER_NAME" cat /bridge/bridge.log 2>/dev/null || echo "No bridge log found"
    fi
    
    # Test 13: Bridge error handling
    test_start "Testing bridge error handling"
    
    # Stop mock server temporarily to test error handling
    kill "$MOCK_SERVER_PID" 2>/dev/null || true
    wait "$MOCK_SERVER_PID" 2>/dev/null || true
    MOCK_SERVER_PID=""
    
    # Try qwen command with server down
    local error_output
    error_output=$(run_qwen_command "$CONTAINER_NAME" "Test error handling" 5 2>&1 || echo "EXPECTED_ERROR")
    
    if echo "$error_output" | grep -qi "error\|failed\|timeout"; then
        test_pass "Bridge correctly handles server errors"
    else
        test_warning "Error handling unclear - output: $error_output"
    fi
    
    # Test 14: Container logs validation
    test_start "Checking container logs for bridge startup messages"
    
    local logs
    logs=$(get_container_logs "$CONTAINER_NAME" 30)
    
    if echo "$logs" | grep -q "Bridge.*started\|bridge.*running"; then
        test_pass "Bridge startup messages found in logs"
    else
        test_warning "No clear bridge startup messages in logs"
        log_debug "Recent logs: $logs"
    fi
    
    log_info "Bridge connection test completed"
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