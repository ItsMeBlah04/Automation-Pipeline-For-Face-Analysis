#!/bin/bash

# Smoke Test Suite for Face Analysis Pipeline
# Comprehensive integration testing for staging and production deployments
# Usage: ./smoke_test.sh [staging|prod] <EC2_HOST>

set -o pipefail

#============================================
# Configuration & Setup
#============================================

ENVIRONMENT="${1:-staging}"
EC2_HOST="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR=$(mktemp -d)
TEST_LOG="$TEMP_DIR/test_log.txt"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Timeouts and retries
MAX_RETRIES=3
RETRY_DELAY=2
CURL_TIMEOUT=10
CURL_TIMEOUT_ANALYZE=30
HEALTH_CHECK_RETRIES=5

#============================================
# Cleanup & Trap Functions
#============================================

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

handle_error() {
    local line_number=$1
    local error_msg="$2"
    echo -e "${RED}✗ Error on line $line_number: $error_msg${NC}"
    exit 1
}

#============================================
# Validation Functions
#============================================

validate_arguments() {
    if [ -z "$EC2_HOST" ]; then
        echo -e "${RED}Error: EC2_HOST not provided${NC}"
        echo "Usage: $0 [staging|prod] <EC2_HOST>"
        echo "Example: $0 staging ec2-123-456-789.compute.amazonaws.com"
        exit 1
    fi

    if [ "$ENVIRONMENT" != "staging" ] && [ "$ENVIRONMENT" != "prod" ]; then
        echo -e "${RED}Error: ENVIRONMENT must be 'staging' or 'prod'${NC}"
        exit 1
    fi
}

check_prerequisites() {
    local missing_tools=()
    
    for tool in curl jq; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${YELLOW}Warning: Missing tools: ${missing_tools[*]}${NC}"
        echo "Some tests may be skipped."
    fi
}

#============================================
# Test Image Creation
#============================================

create_test_image() {
    local output_file="$1"
    
    # Try ImageMagick first
    if command -v convert &>/dev/null; then
        if convert -size 100x100 xc:blue "$output_file" 2>/dev/null; then
            return 0
        fi
    fi
    
    # Try Python with Pillow
    if command -v python3 &>/dev/null; then
        python3 - "$output_file" 2>/dev/null <<'PYTHON'
import sys
try:
    from PIL import Image
img = Image.new('RGB', (100, 100), color='blue')
img.save(sys.argv[1])
    sys.exit(0)
except Exception as e:
    sys.exit(1)
PYTHON
        if [ $? -eq 0 ]; then
            return 0
        fi
    fi
    
    # Fallback: minimal valid PNG (1x1 pixel blue)
    printf '\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0d\x49\x48\x44\x52\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90\x77\x53\xde\x00\x00\x00\x0c\x49\x44\x41\x54\x08\xd7\x63\xf8\xcf\xc0\x00\x00\x03\x01\x01\x00\x18\xdd\x8d\xb4\x00\x00\x00\x00\x49\x45\x4e\x44\xae\x42\x60\x82' > "$output_file"
    return 0
}

#============================================
# HTTP Request Utilities
#============================================

make_request() {
    local method="$1"
    local url="$2"
    local data_file="${3:-}"
    local output_file="${4:-}"
    local timeout="${5:-$CURL_TIMEOUT}"
    
    local curl_opts=(
        --silent
        --show-error
        --max-time "$timeout"
        --write-out "%{http_code}"
    )
    
    if [ -n "$output_file" ]; then
        curl_opts+=(--output "$output_file")
    fi
    
    if [ "$method" = "POST" ]; then
        curl_opts+=(-X POST)
    fi
    
    if [ -n "$data_file" ] && [ -f "$data_file" ]; then
        curl_opts+=(-F "image=@$data_file")
    fi
    
    curl "${curl_opts[@]}" "$url" 2>/dev/null
}

#============================================
# Test Execution Framework
#============================================

print_section() {
    local section_num="$1"
    local section_name="$2"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}SECTION $section_num: $section_name${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    local expect_success="${3:-true}"
    
    ((TOTAL_TESTS++))
    local test_num=$TOTAL_TESTS
    
    echo -n "[$test_num] Test: $test_name ... "
    
    # Execute test with error suppression
    local output
    local exit_code
    output=$(eval "$test_command" 2>&1)
    exit_code=$?
    
    local test_passed=false
    if [ "$expect_success" = "true" ]; then
        if [ $exit_code -eq 0 ]; then
            test_passed=true
        fi
    else
        if [ $exit_code -ne 0 ]; then
            test_passed=true
        fi
    fi
    
    if [ "$test_passed" = "true" ]; then
        echo -e "${GREEN}✓ PASSED${NC}"
        ((PASSED_TESTS++))
    else
        echo -e "${RED}✗ FAILED${NC}"
        ((FAILED_TESTS++))
        if [ -n "$output" ]; then
            echo "    Error: $output" | head -3
        fi
    fi
}

#============================================
# Health Check Utilities
#============================================

wait_for_endpoint() {
    local url="$1"
    local expected_status="$2"
    local max_attempts="${3:-$HEALTH_CHECK_RETRIES}"
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local http_code=$(curl --silent --max-time 5 --write-out "%{http_code}" --output /dev/null "$url" 2>/dev/null)
        if [ "$http_code" = "$expected_status" ]; then
            return 0
        fi
        ((attempt++))
        [ $attempt -lt $max_attempts ] && sleep "$RETRY_DELAY"
    done
    
    return 1
}

#============================================
# Main Test Suites
#============================================

run_health_checks() {
    print_section "1" "Basic Health Checks"
    
    # Test 1: Frontend Health
    run_test "Frontend Health Endpoint" \
        "[ \"\$(curl --silent --max-time $CURL_TIMEOUT --write-out '%{http_code}' --output /dev/null http://$EC2_HOST/health)\" = \"200\" ]"
    
    # Test 2: Frontend Main Page
    run_test "Frontend Main Page Loads" \
        "curl --silent --max-time $CURL_TIMEOUT http://$EC2_HOST/ | grep -qi 'html\|doctype' && echo 'ok' | grep -q 'ok'"
    
    # Test 3: Backend Health (Direct)
    run_test "Backend Health Endpoint (Direct)" \
        "[ \"\$(curl --silent --max-time $CURL_TIMEOUT --write-out '%{http_code}' --output /dev/null http://$EC2_HOST:8000/health)\" = \"200\" ]"
    
    # Test 4: Backend JSON Response
    run_test "Backend Returns Valid JSON" \
        "curl --silent --max-time $CURL_TIMEOUT http://$EC2_HOST:8000/health | jq -e '.status == \"ok\"' >/dev/null 2>&1"
}

run_frontend_tests() {
    print_section "2" "Frontend Content & Functionality"
    
    # Test 5: Frontend Content
    run_test "Frontend Contains Face Analysis Content" \
        "curl --silent --max-time $CURL_TIMEOUT http://$EC2_HOST/ | grep -qi 'face'"
    
    # Test 6: Frontend HTML Content-Type
    run_test "Frontend Serves HTML Content" \
        "curl --silent --max-time $CURL_TIMEOUT -H 'Accept: text/html' http://$EC2_HOST/ | grep -qi '<!doctype\|<html'"
}

run_api_documentation_tests() {
    print_section "3" "Backend API Documentation"
    
    # Test 7: API Docs Direct
    run_test "Backend API Docs (Direct Access)" \
        "[ \"\$(curl --silent --max-time $CURL_TIMEOUT --write-out '%{http_code}' --output /dev/null http://$EC2_HOST:8000/docs)\" = \"200\" ]"
    
    # Test 8: API Docs via Proxy
    run_test "Backend API Docs (Via Nginx Proxy)" \
        "[ \"\$(curl --silent --max-time $CURL_TIMEOUT --write-out '%{http_code}' --output /dev/null http://$EC2_HOST/docs)\" = \"200\" ]"
    
    # Test 9: OpenAPI Schema
    run_test "OpenAPI Schema Available" \
        "curl --silent --max-time $CURL_TIMEOUT http://$EC2_HOST/openapi.json 2>/dev/null | jq -e '.openapi' >/dev/null 2>&1"
}

run_api_tests() {
    print_section "4" "Backend-Frontend Integration (Analyze Endpoint)"
    
    # Create test image
    local TEST_IMAGE="$TEMP_DIR/test_face.png"
create_test_image "$TEST_IMAGE"
    
    if [ ! -f "$TEST_IMAGE" ]; then
        echo -e "${RED}✗ Failed to create test image${NC}"
        return 1
    fi

# Test 10: Analyze Endpoint Available (Proxied)
    run_test "Analyze Endpoint Available (Via Proxy)" \
        "[ \"\$(make_request POST http://$EC2_HOST/analyze $TEST_IMAGE '' $CURL_TIMEOUT_ANALYZE)\" = \"200\" ]"
    
    # Test 11: Analyze Returns Valid JSON (Proxied)
    run_test "Analyze Returns Valid JSON (Via Proxy)" \
        "curl --silent --max-time $CURL_TIMEOUT_ANALYZE -X POST -F 'image=@$TEST_IMAGE' http://$EC2_HOST/analyze 2>/dev/null | jq -e '.face_count' >/dev/null 2>&1"
    
    # Test 12: Analyze Response Structure (Proxied)
    run_test "Analyze Response Has Expected Structure" \
        "curl --silent --max-time $CURL_TIMEOUT_ANALYZE -X POST -F 'image=@$TEST_IMAGE' http://$EC2_HOST/analyze 2>/dev/null | jq -e 'has(\"filename\") and has(\"face_count\") and has(\"faces\")' >/dev/null 2>&1"
    
    # Test 13: Analyze Endpoint Direct
    run_test "Analyze Endpoint Available (Direct Access)" \
        "[ \"\$(make_request POST http://$EC2_HOST:8000/analyze $TEST_IMAGE '' $CURL_TIMEOUT_ANALYZE)\" = \"200\" ]"
}

run_error_handling_tests() {
    print_section "5" "Error Handling"
    
    # Test 14: Empty File Returns 400
    local EMPTY_FILE="$TEMP_DIR/empty.txt"
touch "$EMPTY_FILE"
run_test "Empty File Upload Returns 400" \
    "[ \"\$(curl --silent --max-time $CURL_TIMEOUT_ANALYZE -X POST -F 'image=@$EMPTY_FILE' http://$EC2_HOST/analyze 2>/dev/null | tail -c 3)\" = \"400\" ]"

    # Test 15: Missing Parameter Returns 422
run_test "Missing Image Parameter Returns 422" \
    "[ \"\$(curl --silent --max-time $CURL_TIMEOUT_ANALYZE -X POST http://$EC2_HOST/analyze 2>/dev/null | tail -c 3)\" = \"422\" ]"
}

run_infrastructure_tests() {
    print_section "6" "Infrastructure & Deployment"

# Test 16: Backend Container Running
run_test "Backend Container Running" \
        "ssh -i \"\$SSH_KEY\" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ec2-user@$EC2_HOST 'docker ps | grep -q face-analysis-backend' 2>/dev/null"

# Test 17: Frontend Container Running
run_test "Frontend Container Running" \
        "ssh -i \"\$SSH_KEY\" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ec2-user@$EC2_HOST 'docker ps | grep -q face-analysis-frontend' 2>/dev/null"

    # Test 18: Backend Container Healthy
run_test "Backend Container Health Status" \
        "ssh -i \"\$SSH_KEY\" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ec2-user@$EC2_HOST 'docker ps --filter name=face-analysis-backend --format \"table {{.Status}}\" | grep -q \"(healthy)\"' 2>/dev/null"

    # Test 19: Frontend Container Healthy
run_test "Frontend Container Health Status" \
        "ssh -i \"\$SSH_KEY\" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ec2-user@$EC2_HOST 'docker ps --filter name=face-analysis-frontend --format \"table {{.Status}}\" | grep -q \"(healthy)\"' 2>/dev/null"
}

#============================================
# Results Summary
#============================================

print_summary() {
    local success_rate=0
    if [ $TOTAL_TESTS -gt 0 ]; then
        success_rate=$(awk "BEGIN {printf \"%.1f\", ($PASSED_TESTS/$TOTAL_TESTS)*100}")
    fi
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}TEST RESULTS SUMMARY${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Environment:    $ENVIRONMENT"
    echo "Target Host:    $EC2_HOST"
echo "Total Tests:    $TOTAL_TESTS"
    echo -e "Passed:         ${GREEN}$PASSED_TESTS ✓${NC}"
    echo -e "Failed:         ${RED}$FAILED_TESTS ✗${NC}"
    echo "Success Rate:   $success_rate%"
echo ""
}

print_success_summary() {
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}✓ ALL SMOKE TESTS PASSED!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo "Deployment is healthy and ready for use."
    echo ""
    echo "Service URLs:"
    echo "  • Frontend:        http://$EC2_HOST"
    echo "  • Backend API:     http://$EC2_HOST:8000"
    echo "  • API Docs:        http://$EC2_HOST/docs"
    echo "  • Health Check:    http://$EC2_HOST/health"
    echo "  • Analyze API:     http://$EC2_HOST/analyze"
    echo ""
}

print_failure_summary() {
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}✗ SMOKE TESTS FAILED${NC}"
    echo -e "${RED}============================================${NC}"
    echo ""
    echo "$FAILED_TESTS test(s) failed. Deployment may have issues."
    echo ""
    echo "Troubleshooting Steps:"
    echo ""
    echo "1. Check container logs:"
    echo "   ssh ec2-user@$EC2_HOST 'docker-compose logs --tail=100 backend frontend'"
    echo ""
    echo "2. Check container status:"
    echo "   ssh ec2-user@$EC2_HOST 'docker ps -a'"
    echo ""
    echo "3. Check specific container health:"
    echo "   ssh ec2-user@$EC2_HOST 'docker inspect face-analysis-backend | jq '.[0].State.Health'"
    echo "   ssh ec2-user@$EC2_HOST 'docker inspect face-analysis-frontend | jq '.[0].State.Health'"
    echo ""
    echo "4. Test endpoints directly on EC2:"
    echo "   ssh ec2-user@$EC2_HOST 'curl -v http://localhost:8000/health'"
    echo "   ssh ec2-user@$EC2_HOST 'curl -v http://localhost/health'"
    echo ""
    echo "5. Check nginx configuration:"
    echo "   ssh ec2-user@$EC2_HOST 'docker exec face-analysis-frontend nginx -t'"
    echo ""
    echo "6. Check AWS security groups allow traffic on ports 80 and 8000"
    echo ""
    echo "7. Monitor CloudWatch metrics:"
    echo "   Check CPU, memory, and network metrics in AWS console"
    echo ""
}

#============================================
# Main Execution
#============================================

main() {
    # Header
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}Face Analysis Pipeline - Smoke Tests${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo "Environment: $ENVIRONMENT"
    echo "Target Host: $EC2_HOST"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    
    # Validation
    validate_arguments
    check_prerequisites
    
    # Wait for services to be ready
    echo "Waiting for services to be ready..."
    if ! wait_for_endpoint "http://$EC2_HOST/health" "200" 5; then
        echo -e "${YELLOW}Warning: Frontend not responding yet, tests may fail${NC}"
    fi
    if ! wait_for_endpoint "http://$EC2_HOST:8000/health" "200" 5; then
        echo -e "${YELLOW}Warning: Backend not responding yet, tests may fail${NC}"
    fi
    echo ""
    
    # Run test suites
    run_health_checks
    run_frontend_tests
    run_api_documentation_tests
    run_api_tests
    run_error_handling_tests
    run_infrastructure_tests
    
    # Print results
    print_summary
    
    if [ $FAILED_TESTS -eq 0 ]; then
        print_success_summary
        exit 0
    else
        print_failure_summary
    exit 1
fi
}

# Execute main function
main "$@"
