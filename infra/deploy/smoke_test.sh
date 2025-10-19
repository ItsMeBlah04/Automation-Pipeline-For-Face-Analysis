#!/bin/bash

# Smoke Test Script for Face Analysis Pipeline
# This script performs comprehensive integration tests on deployed services
# Usage: ./smoke_test.sh [staging|prod] <EC2_HOST>

set -e  # Exit on any error

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 [staging|prod] <EC2_HOST>"
    echo "Example: $0 staging ec2-123-456-789.compute-1.amazonaws.com"
    exit 1
fi

ENVIRONMENT=$1
EC2_HOST=$2
TEMP_DIR=$(mktemp -d)

# Cleanup temp directory on exit
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "============================================"
echo "Face Analysis Pipeline - Smoke Tests"
echo "============================================"
echo "Environment: $ENVIRONMENT"
echo "Target Host: $EC2_HOST"
echo "============================================"
echo ""

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_status="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo "[$TOTAL_TESTS] Test: $test_name"

    # Execute the test
    if eval "$test_command"; then
        if [ "$expected_status" = "success" ]; then
            echo "    ✓ PASSED"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo "    ✗ FAILED (expected failure but got success)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        if [ "$expected_status" = "failure" ]; then
            echo "    ✓ PASSED (expected failure)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo "    ✗ FAILED"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    fi
    echo ""
}

# Create a test image (100x100 solid color PNG) for API testing
create_test_image() {
    local output_file="$1"
    # Prefer ImageMagick if available
    if command -v convert >/dev/null 2>&1; then
        if convert -size 100x100 xc:blue "$output_file" >/dev/null 2>&1; then
            return 0
        fi
    fi
    # Use Python only if Pillow is present; guard under if to avoid set -e exit
    if command -v python3 >/dev/null 2>&1; then
        if python3 - "$output_file" >/dev/null 2>&1 <<'PY'
import sys
try:
    from PIL import Image
except Exception:
    sys.exit(2)
img = Image.new('RGB', (100, 100), color='blue')
img.save(sys.argv[1])
PY
        then
            return 0
        fi
    fi
    # Fallback: create a minimal valid PNG file (1x1 pixel)
    printf '\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0d\x49\x48\x44\x52\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90\x77\x53\xde\x00\x00\x00\x0c\x49\x44\x41\x54\x08\xd7\x63\xf8\xcf\xc0\x00\x00\x03\x01\x01\x00\x18\xdd\x8d\xb4\x00\x00\x00\x00\x49\x45\x4e\x44\xae\x42\x60\x82' > "$output_file"
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SECTION 1: Basic Health Checks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 1: Frontend Health Check
run_test "Frontend Health Check" \
    "curl -f -s http://$EC2_HOST/health -w 'Status: %{http_code}' | grep -q 'Status: 200'" \
    "success"

# Test 2: Frontend Main Page Loads
run_test "Frontend Main Page" \
    "curl -f -s http://$EC2_HOST/ -w 'Status: %{http_code}' | grep -q 'Status: 200'" \
    "success"

# Test 3: Backend Health Check (Direct Access)
run_test "Backend Health Check (Direct)" \
    "curl -f -s http://$EC2_HOST:8000/health -w 'Status: %{http_code}' | grep -q 'Status: 200'" \
    "success"

# Test 4: Backend Returns Valid JSON
run_test "Backend JSON Response Format" \
    "curl -f -s http://$EC2_HOST:8000/health -H 'Accept: application/json' | jq -e '.status == \"ok\"' > /dev/null 2>&1" \
    "success"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SECTION 2: Frontend Content & Assets"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 5: Frontend Contains Expected Content
run_test "Frontend Contains Face Analysis Content" \
    "curl -f -s http://$EC2_HOST/ | grep -qi 'Face Analysis'" \
    "success"

# Test 6: Frontend Returns HTML
run_test "Frontend Serves HTML Content" \
    "curl -f -s http://$EC2_HOST/ -H 'Accept: text/html' | grep -qi '<!doctype html>'" \
    "success"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SECTION 3: Backend API Documentation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 7: API Documentation Available (Direct)
run_test "Backend API Documentation (Direct)" \
    "curl -f -s http://$EC2_HOST:8000/docs -w 'Status: %{http_code}' | grep -q 'Status: 200'" \
    "success"

# Test 8: API Documentation Available (Via Nginx Proxy)
run_test "Backend API Documentation (Proxied)" \
    "curl -f -s http://$EC2_HOST/docs -w 'Status: %{http_code}' | grep -q 'Status: 200'" \
    "success"

# Test 9: OpenAPI Schema Available
run_test "OpenAPI Schema Endpoint" \
    "curl -f -s http://$EC2_HOST/openapi.json | jq -e '.openapi' > /dev/null 2>&1" \
    "success"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SECTION 4: Backend-Frontend Integration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create a test image for API testing
TEST_IMAGE="$TEMP_DIR/test_face.png"
create_test_image "$TEST_IMAGE"

# Test 10: Analyze Endpoint Available (Proxied)
run_test "Analyze Endpoint Available (Proxied)" \
    "curl -f -s -X POST http://$EC2_HOST/analyze -F 'image=@$TEST_IMAGE' -w 'Status: %{http_code}' | grep -q 'Status: 200'" \
    "success"

# Test 11: Analyze Endpoint Returns Valid JSON
run_test "Analyze Endpoint Returns Valid JSON" \
    "curl -f -s -X POST http://$EC2_HOST/analyze -F 'image=@$TEST_IMAGE' | jq -e '.face_count' > /dev/null 2>&1" \
    "success"

# Test 12: Analyze Response Has Expected Structure
run_test "Analyze Response Structure" \
    "curl -f -s -X POST http://$EC2_HOST/analyze -F 'image=@$TEST_IMAGE' | jq -e 'has(\"filename\") and has(\"face_count\") and has(\"faces\")' > /dev/null 2>&1" \
    "success"

# Test 13: Analyze Endpoint Available (Direct to Backend)
run_test "Analyze Endpoint Available (Direct)" \
    "curl -f -s -X POST http://$EC2_HOST:8000/analyze -F 'image=@$TEST_IMAGE' -w 'Status: %{http_code}' | grep -q 'Status: 200'" \
    "success"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SECTION 5: Error Handling"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 14: Empty File Upload Returns Error
EMPTY_FILE="$TEMP_DIR/empty.txt"
touch "$EMPTY_FILE"
run_test "Empty File Upload Returns 400" \
    "curl -s -X POST http://$EC2_HOST/analyze -F 'image=@$EMPTY_FILE' -w '%{http_code}' | grep -q '400'" \
    "success"

# Test 15: Missing Image Parameter Returns Error
run_test "Missing Image Parameter Returns 422" \
    "curl -s -X POST http://$EC2_HOST/analyze -w '%{http_code}' | grep -q '422'" \
    "success"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SECTION 6: Infrastructure & Docker"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 16: Backend Container Running
run_test "Backend Container Running" \
    "ssh -i \"\$SSH_KEY\" -o StrictHostKeyChecking=no ec2-user@$EC2_HOST 'docker ps | grep -q face-analysis-backend'" \
    "success"

# Test 17: Frontend Container Running
run_test "Frontend Container Running" \
    "ssh -i \"\$SSH_KEY\" -o StrictHostKeyChecking=no ec2-user@$EC2_HOST 'docker ps | grep -q face-analysis-frontend'" \
    "success"

# Test 18: Backend Container is Healthy
run_test "Backend Container Health Status" \
    "ssh -i \"\$SSH_KEY\" -o StrictHostKeyChecking=no ec2-user@$EC2_HOST 'docker ps --filter name=face-analysis-backend --format \"{{.Status}}\" | grep -q \"(healthy)\"'" \
    "success"

# Test 19: Frontend Container is Healthy
run_test "Frontend Container Health Status" \
    "ssh -i \"\$SSH_KEY\" -o StrictHostKeyChecking=no ec2-user@$EC2_HOST 'docker ps --filter name=face-analysis-frontend --format \"{{.Status}}\" | grep -q \"(healthy)\"'" \
    "success"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST RESULTS SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Environment:    $ENVIRONMENT"
echo "Total Tests:    $TOTAL_TESTS"
echo "Passed:         $PASSED_TESTS ✓"
echo "Failed:         $FAILED_TESTS ✗"
echo "Success Rate:   $(awk "BEGIN {printf \"%.1f\", ($PASSED_TESTS/$TOTAL_TESTS)*100}")%"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo "============================================"
    echo "✓ ALL SMOKE TESTS PASSED!"
    echo "============================================"
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
    exit 0
else
    echo "============================================"
    echo "✗ SMOKE TESTS FAILED"
    echo "============================================"
    echo ""
    echo "$FAILED_TESTS test(s) failed. Deployment may have issues."
    echo ""
    echo "Troubleshooting Steps:"
    echo "  1. Check container logs:"
    echo "     ssh ec2-user@$EC2_HOST 'docker-compose logs'"
    echo ""
    echo "  2. Check container status:"
    echo "     ssh ec2-user@$EC2_HOST 'docker ps -a'"
    echo ""
    echo "  3. Check container health:"
    echo "     ssh ec2-user@$EC2_HOST 'docker inspect --format=\"{{.State.Health.Status}}\" face-analysis-backend'"
    echo "     ssh ec2-user@$EC2_HOST 'docker inspect --format=\"{{.State.Health.Status}}\" face-analysis-frontend'"
    echo ""
    echo "  4. Check AWS CloudWatch for system metrics"
    echo ""
    echo "  5. Verify security group rules allow:"
    echo "     - Port 80 (HTTP) for frontend"
    echo "     - Port 8000 for backend API"
    echo ""
    echo "  6. Test locally:"
    echo "     curl -v http://$EC2_HOST/health"
    echo "     curl -v http://$EC2_HOST:8000/health"
    echo ""
    exit 1
fi
