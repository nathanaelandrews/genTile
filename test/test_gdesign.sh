#!/bin/bash

# Test script for design_guides.sh
# Tests various functionality and error cases

# Determine script location
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$SCRIPT_DIR" )"
BIN_DIR="$REPO_DIR/bin"
TEST_DATA_DIR="$SCRIPT_DIR/data"
TEST_OUTPUT_DIR="$SCRIPT_DIR/output"
EXPECTED_DIR="$SCRIPT_DIR/expected"

# Create test directories
mkdir -p "$TEST_DATA_DIR"
mkdir -p "$TEST_OUTPUT_DIR"
mkdir -p "$EXPECTED_DIR"

# Create test data
echo ">Test_Sequence
ACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTG" > "$TEST_DATA_DIR/test.fa"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Run test function
run_test() {
    local test_name="$1"
    local command="$2"
    
    echo -n "Running test: $test_name... "
    
    # Run the command and capture output
    eval "$command" > "$TEST_OUTPUT_DIR/${test_name}.out" 2> "$TEST_OUTPUT_DIR/${test_name}.err"
    
    # Check return code
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}PASSED${NC}"
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        echo "Command: $command"
        echo "See: $TEST_OUTPUT_DIR/${test_name}.err"
        return 1
    fi
}

# Main function to run tests
main() {
    local failures=0
    
    echo "Starting tests for design_guides.sh..."
    
    # Test 1: Basic usage
    run_test "basic_usage" "$BIN_DIR/design_guides.sh -i $TEST_DATA_DIR/test.fa"
    failures=$((failures + $?))
    
    # Test 2: Custom output
    run_test "custom_output" "$BIN_DIR/design_guides.sh -i $TEST_DATA_DIR/test.fa -o $TEST_OUTPUT_DIR/custom.out"
    failures=$((failures + $?))
    
    # Test 3: Verbose mode
    run_test "verbose_mode" "$BIN_DIR/design_guides.sh -i $TEST_DATA_DIR/test.fa -v"
    failures=$((failures + $?))
    
    # Add more tests here...
    
    # Summarize results
    if [ $failures -eq 0 ]; then
        echo -e "\n${GREEN}All tests passed!${NC}"
    else
        echo -e "\n${RED}$failures test(s) failed${NC}"
    fi
    
    return $failures
}

# Run tests
main
exit $?
