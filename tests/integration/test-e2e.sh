#!/bin/bash

# End-to-End Integration Test Orchestrator
# Runs complete test suite for qwen-code CLI with and without bridge

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source utilities
source "$SCRIPT_DIR/utils.sh"

# Test configuration
TEST_SUITE_NAME="E2E Integration Tests"
RESULTS_DIR="/tmp/qwen-integration-results-$$"
START_TIME=$(date +%s)

# Test results tracking
DIRECT_TEST_RESULT=0
BRIDGE_TEST_RESULT=0
BRIDGE_UNIT_TEST_RESULT=0

cleanup() {
    log_info "Cleaning up E2E test suite..."
    
    # Cleanup any remaining containers
    cleanup_container "qwen-test-direct-qwen-code-1"
    cleanup_container "qwen-test-bridge-qwen-code-1"
    
    # Remove results directory
    rm -rf "$RESULTS_DIR"
    
    log_info "E2E test cleanup complete"
}

trap cleanup EXIT

run_bridge_unit_tests() {
    log_info "=========================================="
    log_info "Running Bridge Unit Tests"
    log_info "=========================================="
    
    cd "$PROJECT_ROOT/gemini-openai-bridge"
    
    test_start "Bridge unit test suite"
    
    if npm test 2>&1 | tee "$RESULTS_DIR/bridge-unit-tests.log"; then
        test_pass "Bridge unit tests passed"
        BRIDGE_UNIT_TEST_RESULT=0
    else
        test_fail "Bridge unit tests failed"
        BRIDGE_UNIT_TEST_RESULT=1
    fi
    
    # Also run coverage for reporting
    if npm run test:coverage >/dev/null 2>&1; then
        log_debug "Bridge test coverage generated"
    fi
    
    cd "$PROJECT_ROOT"
}

run_direct_connection_test() {
    log_info "=========================================="
    log_info "Running Direct Connection Test"
    log_info "=========================================="
    
    test_start "Direct connection integration test"
    
    if "$SCRIPT_DIR/test-cli-direct.sh" 2>&1 | tee "$RESULTS_DIR/direct-test.log"; then
        test_pass "Direct connection test passed"
        DIRECT_TEST_RESULT=0
    else
        test_fail "Direct connection test failed"
        DIRECT_TEST_RESULT=1
    fi
}

run_bridge_connection_test() {
    log_info "=========================================="
    log_info "Running Bridge Connection Test"
    log_info "=========================================="
    
    test_start "Bridge connection integration test"
    
    if "$SCRIPT_DIR/test-cli-bridge.sh" 2>&1 | tee "$RESULTS_DIR/bridge-test.log"; then
        test_pass "Bridge connection test passed"
        BRIDGE_TEST_RESULT=0
    else
        test_fail "Bridge connection test failed"
        BRIDGE_TEST_RESULT=1
    fi
}

run_docker_image_validation() {
    log_info "=========================================="
    log_info "Docker Image Validation"
    log_info "=========================================="
    
    # Test 1: Check if image exists
    test_start "Checking Docker image exists"
    
    if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        test_pass "Docker image exists: $IMAGE_NAME"
    else
        test_warning "Docker image not found, will be built during tests"
    fi
    
    # Test 2: Check bridge files are in image
    test_start "Validating bridge files in Docker image"
    
    # Build a temporary container to check files
    local temp_container="qwen-temp-validation-$$"
    
    if docker run --name "$temp_container" --rm -d "$IMAGE_NAME" sleep 30 >/dev/null 2>&1; then
        if docker exec "$temp_container" test -f /bridge/bridge.js >/dev/null 2>&1; then
            test_pass "Bridge files found in Docker image"
        else
            test_fail "Bridge files missing from Docker image"
        fi
        
        if docker exec "$temp_container" test -f /usr/local/bin/docker-entrypoint.sh >/dev/null 2>&1; then
            test_pass "Entrypoint script found in Docker image"
        else
            test_fail "Entrypoint script missing from Docker image"
        fi
        
        docker stop "$temp_container" >/dev/null 2>&1 || true
    else
        test_warning "Could not create temporary container for validation"
    fi
}

generate_test_report() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    log_info "=========================================="
    log_info "FINAL TEST REPORT"
    log_info "=========================================="
    
    echo
    log_info "Test Duration: ${duration}s"
    log_info "Results Directory: $RESULTS_DIR"
    echo
    
    # Individual test results
    log_info "Individual Test Results:"
    
    if [ $BRIDGE_UNIT_TEST_RESULT -eq 0 ]; then
        log_success "✅ Bridge Unit Tests: PASSED"
    else
        log_error "❌ Bridge Unit Tests: FAILED"
    fi
    
    if [ $DIRECT_TEST_RESULT -eq 0 ]; then
        log_success "✅ Direct Connection Test: PASSED"
    else
        log_error "❌ Direct Connection Test: FAILED"
    fi
    
    if [ $BRIDGE_TEST_RESULT -eq 0 ]; then
        log_success "✅ Bridge Connection Test: PASSED"
    else
        log_error "❌ Bridge Connection Test: FAILED"
    fi
    
    echo
    
    # Overall result
    local total_failures=$((BRIDGE_UNIT_TEST_RESULT + DIRECT_TEST_RESULT + BRIDGE_TEST_RESULT + FAILED_COUNT))
    
    if [ $total_failures -eq 0 ]; then
        log_success "🎉 ALL TESTS PASSED!"
        log_success "Both direct and bridge modes are working correctly"
        echo
        log_info "Ready for production use:"
        log_info "• Direct mode: Set USE_GEMINI_BRIDGE=false"
        log_info "• Bridge mode: Set USE_GEMINI_BRIDGE=true"
        return 0
    else
        log_error "💥 $total_failures TEST(S) FAILED"
        echo
        log_error "Check the individual test logs:"
        if [ -f "$RESULTS_DIR/bridge-unit-tests.log" ]; then
            log_info "• Bridge unit tests: $RESULTS_DIR/bridge-unit-tests.log"
        fi
        if [ -f "$RESULTS_DIR/direct-test.log" ]; then
            log_info "• Direct connection: $RESULTS_DIR/direct-test.log"
        fi
        if [ -f "$RESULTS_DIR/bridge-test.log" ]; then
            log_info "• Bridge connection: $RESULTS_DIR/bridge-test.log"
        fi
        return 1
    fi
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --skip-unit       Skip bridge unit tests"
    echo "  --skip-direct     Skip direct connection test"
    echo "  --skip-bridge     Skip bridge connection test"
    echo "  --debug           Enable debug output"
    echo "  --fail-fast       Stop on first failure"
    echo "  --help            Show this help"
    echo
    echo "Examples:"
    echo "  $0                    # Run all tests"
    echo "  $0 --skip-unit        # Skip unit tests, run integration only"
    echo "  $0 --debug            # Run with debug output"
    echo "  $0 --fail-fast        # Stop on first failure"
}

main() {
    # Parse command line arguments
    local skip_unit=false
    local skip_direct=false
    local skip_bridge=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-unit)
                skip_unit=true
                shift
                ;;
            --skip-direct)
                skip_direct=true
                shift
                ;;
            --skip-bridge)
                skip_bridge=true
                shift
                ;;
            --debug)
                export TEST_DEBUG=true
                shift
                ;;
            --fail-fast)
                export TEST_FAIL_FAST=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log_info "=========================================="
    log_info "Starting $TEST_SUITE_NAME"
    log_info "=========================================="
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    log_info "Results will be saved to: $RESULTS_DIR"
    
    cd "$PROJECT_ROOT"
    
    # Initialize Docker compose
    init_docker_compose
    
    # Run Docker image validation
    run_docker_image_validation
    
    # Run bridge unit tests first
    if [ "$skip_unit" = false ]; then
        run_bridge_unit_tests
        
        if [ $BRIDGE_UNIT_TEST_RESULT -ne 0 ] && [ "${TEST_FAIL_FAST:-false}" = "true" ]; then
            log_error "Bridge unit tests failed, stopping due to --fail-fast"
            generate_test_report
            exit 1
        fi
    else
        log_info "Skipping bridge unit tests"
    fi
    
    # Run direct connection test
    if [ "$skip_direct" = false ]; then
        run_direct_connection_test
        
        if [ $DIRECT_TEST_RESULT -ne 0 ] && [ "${TEST_FAIL_FAST:-false}" = "true" ]; then
            log_error "Direct connection test failed, stopping due to --fail-fast"
            generate_test_report
            exit 1
        fi
    else
        log_info "Skipping direct connection test"
    fi
    
    # Run bridge connection test
    if [ "$skip_bridge" = false ]; then
        run_bridge_connection_test
        
        if [ $BRIDGE_TEST_RESULT -ne 0 ] && [ "${TEST_FAIL_FAST:-false}" = "true" ]; then
            log_error "Bridge connection test failed, stopping due to --fail-fast"
            generate_test_report
            exit 1
        fi
    else
        log_info "Skipping bridge connection test"
    fi
    
    # Generate final report
    generate_test_report
}

# Handle signals gracefully
trap 'log_warning "Test interrupted by signal"; cleanup; exit 130' INT TERM

# Run main function
main "$@"