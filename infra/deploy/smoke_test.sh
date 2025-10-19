#!/bin/bash

# Smoke Test Script for Face Analysis Pipeline
# This script performs basic health checks on deployed services
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

echo "Running Smoke Tests for $ENVIRONMENT Environment"
echo "Target Host: $EC2_HOST"
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
    echo "Test: $test_name"

    # Execute the test
    if eval "$test_command"; then
        if [ "$expected_status" = "success" ]; then
            echo "   PASSED"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo "   FAILED (expected failure but got success)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        if [ "$expected_status" = "failure" ]; then
            echo "   PASSED (expected failure)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo "   FAILED"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    fi
    echo ""
}

# Test 1: Frontend Health Check
run_test "Frontend Health Check" \
    "curl -f -s http://$EC2_HOST/health -w 'Status: %{http_code}' | grep -q 'Status: 200'" \
    "success"

# Test 2: Frontend Main Page
run_test "Frontend Main Page" \
    "curl -f -s http://$EC2_HOST/ -w 'Status: %{http_code}' | grep -q 'Status: 200'" \
    "success"

# Test 3: Backend Health Check
run_test "Backend Health Check" \
    "curl -f -s http://$EC2_HOST:8000/health -w 'Status: %{http_code}' | grep -q 'Status: 200'" \
    "success"

# Test 4: Backend API Documentation Available
run_test "Backend API Documentation" \
    "curl -f -s http://$EC2_HOST:8000/docs -w 'Status: %{http_code}' | grep -q 'Status: 200'" \
    "success"

# Test 5: Backend JSON Response Format
run_test "Backend JSON Response Format" \
    "curl -f -s http://$EC2_HOST:8000/health -H 'Accept: application/json' | jq -e '.status' > /dev/null" \
    "success"

# Test 6: Frontend Contains Expected Content
run_test "Frontend Contains Face Analysis Content" \
    "curl -f -s http://$EC2_HOST/ | grep -qi 'Face Analysis'" \
    "success"

# Test 7: Check if both services are running via Docker
run_test "Docker Containers Running" \
    "ssh -i \"\$SSH_KEY\" -o StrictHostKeyChecking=no ec2-user@$EC2_HOST 'docker ps | grep -q face-analysis'" \
    "success"

# Summary
echo "Smoke Test Summary for $ENVIRONMENT:"
echo "   Total Tests: $TOTAL_TESTS"
echo "   Passed: $PASSED_TESTS"
echo "   Failed: $FAILED_TESTS"

if [ $FAILED_TESTS -eq 0 ]; then
    echo ""
    echo "All smoke tests passed! $ENVIRONMENT deployment is healthy."
    echo ""
    echo "Service URLs:"
    echo "   Frontend: http://$EC2_HOST"
    echo "   Backend: http://$EC2_HOST:8000"
    echo "   Health: http://$EC2_HOST/health"
    exit 0
else
    echo ""
    echo "$FAILED_TESTS test(s) failed. Please check the deployment."
    echo ""
    echo "Troubleshooting steps:"
    echo "   1. Check container logs: ssh to $EC2_HOST and run 'docker-compose logs'"
    echo "   2. Verify container status: ssh to $EC2_HOST and run 'docker ps'"
    echo "   3. Check AWS CloudWatch for system metrics"
    echo "   4. Verify security group allows HTTP/HTTPS traffic"
    exit 1
fi
