#!/bin/bash

# Test script for genTile
# Tests the functionality of get_sequence.sh

# Determine script and repository locations
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$SCRIPT_DIR" )"
BIN_DIR="$REPO_DIR/bin"
TEST_DATA_DIR="$SCRIPT_DIR/data"
TEST_EXPECTED_DIR="$SCRIPT_DIR/expected"
TEST_OUTPUT_DIR="$SCRIPT_DIR/output"

# Create output directory if it doesn't exist
mkdir -p "$TEST_OUTPUT_DIR"

# Set path to test reference genome
# Note: This assumes the real genome is available at this path during testing
GENOME="$REPO_DIR/data/reference/genome/hg38/hg38.fa"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to run a test
run_test() {
    local test_name="$1"
    local command="$2"
    local expected_file="$3"
    local output_file="$TEST_OUTPUT_DIR/${test_name}.out"
    
    echo -n "Running test: $test_name... "
    
    # Run the command and capture output
    eval "$command" > "$output_file" 2>"$TEST_OUTPUT_DIR/${test_name}.err"
    
    # Compare output to expected result
    if [ -f "$expected_file" ]; then
        # Skip header lines with date/time when comparing
        if diff <(grep -v "^#" "$output_file") <(grep -v "^#" "$expected_file") > /dev/null; then
            echo -e "${GREEN}PASSED${NC}"
            return 0
        else
            echo -e "${RED}FAILED${NC} - Output differs from expected"
            echo "See: $output_file"
            return 1
        fi
    else
        echo -e "${RED}FAILED${NC} - Expected output file not found: $expected_file"
        return 1
    fi
}

# Function to prepare test data
prepare_test_data() {
    # Create sample gene list
    echo -e "TP53\nBRCA1\nPTEN" > "$TEST_DATA_DIR/test_genes.txt"
    
    # Create file with a duplicate gene name
    echo "WASH7P" > "$TEST_DATA_DIR/duplicate_gene.txt"
    
    # Create file with a non-existent gene
    echo "FAKE_GENE_XYZ" > "$TEST_DATA_DIR/nonexistent_gene.txt"
}

# Main test runner
main() {
    local failures=0
    
    echo "Starting genTile tests..."
    echo "Repository: $REPO_DIR"
    echo "Test directory: $SCRIPT_DIR"
    echo "================================"
    
    # Prepare test data
    prepare_test_data
    
    # Test 1: Basic gene lookup
    run_test "basic_gene" "$BIN_DIR/get_sequence.sh -i TP53 -r $GENOME -d 1000" "$TEST_EXPECTED_DIR/basic_gene.out"
    failures=$((failures + $?))
    
    # Test 2: Multiple genes from file
    run_test "multiple_genes" "$BIN_DIR/get_sequence.sh -i $TEST_DATA_DIR/test_genes.txt -r $GENOME -d 1000" "$TEST_EXPECTED_DIR/multiple_genes.out"
    failures=$((failures + $?))
    
    # Test 3: Duplicate gene warning
    run_test "duplicate_gene" "$BIN_DIR/get_sequence.sh -i $TEST_DATA_DIR/duplicate_gene.txt -r $GENOME -d 1000" "$TEST_EXPECTED_DIR/duplicate_gene.out"
    failures=$((failures + $?))
    
    # Test 4: ENSEMBL ID
    run_test "ensembl_id" "$BIN_DIR/get_sequence.sh -i ENSG00000141510 -r $GENOME -d 1000" "$TEST_EXPECTED_DIR/ensembl_id.out"
    failures=$((failures + $?))
    
    # Test 5: Non-existent gene
    run_test "nonexistent_gene" "$BIN_DIR/get_sequence.sh -i $TEST_DATA_DIR/nonexistent_gene.txt -r $GENOME -d 1000" "$TEST_EXPECTED_DIR/nonexistent_gene.out"
    failures=$((failures + $?))
    
    # Test 6: Varied distance
    run_test "varied_distance" "$BIN_DIR/get_sequence.sh -i TP53 -r $GENOME -d 5000" "$TEST_EXPECTED_DIR/varied_distance.out"
    failures=$((failures + $?))
    
    # Summary
    echo "================================"
    if [ $failures -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}$failures test(s) failed${NC}"
        return 1
    fi
}

# Run the tests
main
exit $?
