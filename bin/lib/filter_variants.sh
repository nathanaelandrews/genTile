#!/bin/bash

# filter_variants.sh - Filter guides that overlap with genomic variants
# Usage: filter_variants.sh <input_file> <variants_bed> [options]

# Default values
VERBOSE=false

# Function to show usage
show_usage() {
    echo "Usage: $(basename "$0") <input_file> <variants_bed> [options]"
    echo
    echo "Filter guides that overlap with genomic variants (e.g., K562 variants)."
    echo
    echo "Arguments:"
    echo "  input_file      Processed guides file with genomic coordinates"
    echo "  variants_bed    BED file with variant positions to avoid"
    echo
    echo "Options:"
    echo "  -v, --verbose   Show detailed filtering information"
    echo "  -h, --help      Show this help message"
    echo
    echo "Input format expected:"
    echo "  Tab-delimited with columns: guide_id, target_name, chr, abs_start, abs_end, ..."
    echo
    echo "Examples:"
    echo "  $(basename "$0") processed_guides.txt K562_variants.bed"
    echo "  $(basename "$0") processed_guides.txt variants.bed.gz --verbose"
}

# Function for verbose output
verbose() {
    if [ "$VERBOSE" = true ]; then
        echo "[VARIANTS] $1" >&2
    fi
}

# Parse command line arguments
INPUT_FILE=""
VARIANTS_BED=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            if [ -z "$INPUT_FILE" ]; then
                INPUT_FILE="$1"
            elif [ -z "$VARIANTS_BED" ]; then
                VARIANTS_BED="$1"
            else
                echo "Error: Too many arguments"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Check required arguments
if [ -z "$INPUT_FILE" ] || [ -z "$VARIANTS_BED" ]; then
    echo "Error: Both input file and variants BED file are required"
    show_usage
    exit 1
fi

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file not found: $INPUT_FILE"
    exit 1
fi

# Check if variants BED file exists (handle both .bed and .bed.gz)
if [ ! -f "$VARIANTS_BED" ]; then
    echo "Error: Variants BED file not found: $VARIANTS_BED"
    exit 1
fi

# Check if bedtools is available
if ! command -v bedtools &> /dev/null; then
    echo "Error: bedtools is required but not found in PATH"
    exit 1
fi

verbose "Starting variant filtering..."
verbose "Input file: $INPUT_FILE"
verbose "Variants BED: $VARIANTS_BED"

# Create temporary files
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Create BED file from input guides (extract genomic coordinates)
verbose "Converting guides to BED format..."
awk 'BEGIN{OFS="\t"} {
    # Extract: chr, abs_start, abs_end, guide_id
    # Input format: guide_id, target_name, chr, abs_start, abs_end, strand, orientation, score, ...
    print $3, $4, $5, $1
}' "$INPUT_FILE" > "$TMP_DIR/guides.bed"

# Count initial guides
INITIAL_COUNT=$(wc -l < "$TMP_DIR/guides.bed")
verbose "Initial guide count: $INITIAL_COUNT"

# Use bedtools intersect to find guides that DON'T overlap variants (-v flag)
verbose "Finding guides that don't overlap variants..."
bedtools intersect -v -a "$TMP_DIR/guides.bed" -b "$VARIANTS_BED" > "$TMP_DIR/non_overlapping_guides.bed"

# Count remaining guides  
REMAINING_COUNT=$(wc -l < "$TMP_DIR/non_overlapping_guides.bed")
FILTERED_COUNT=$((INITIAL_COUNT - REMAINING_COUNT))

verbose "Variant filtering results:"
verbose "  Initial guides: $INITIAL_COUNT"
verbose "  Guides overlapping variants: $FILTERED_COUNT"
verbose "  Remaining guides: $REMAINING_COUNT"

# Create lookup of guide IDs that passed filtering
cut -f4 "$TMP_DIR/non_overlapping_guides.bed" > "$TMP_DIR/passed_guide_ids.txt"

# Output only the guides that passed variant filtering
verbose "Outputting filtered guides..."
awk 'BEGIN{
    # Load guide IDs that passed filtering
    while ((getline guide_id < "'$TMP_DIR'/passed_guide_ids.txt") > 0) {
        passed[guide_id] = 1
    }
    close("'$TMP_DIR'/passed_guide_ids.txt")
}
{
    # Check if this guide ID passed filtering
    if ($1 in passed) {
        print
    }
}' "$INPUT_FILE"

# Report filtering statistics to stderr
if [ "$FILTERED_COUNT" -gt 0 ]; then
    echo "Filtered out $FILTERED_COUNT guides overlapping genomic variants" >&2
else
    verbose "No guides overlapped variants"
fi
