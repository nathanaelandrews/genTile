#!/bin/bash

# get_TSS.sh - Get TSS coordinates using CAGE data or fallback to APPRIS/Gencode
# Usage: get_TSS.sh <gene_name> <cell_line> [options]

# Determine script location
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$SCRIPT_DIR" )" )"

# Paths
APPRIS_TSS_TABLE="$REPO_DIR/data/reference/gene_annotations/gencode.v47.annotation.tsv"
FETCH_CAGE_SCRIPT="$SCRIPT_DIR/fetch_CAGE_data.sh"

# Default values
VERBOSE=false

# Function to show usage
show_usage() {
    echo "Usage: $(basename "$0") <gene_name> <cell_line> [options]"
    echo
    echo "Get TSS coordinates using CAGE data with APPRIS/Gencode fallback."
    echo
    echo "Arguments:"
    echo "  gene_name     Gene symbol or Ensembl ID (e.g., TP53, ENSG00000141510)"
    echo "  cell_line     Cell line short name (e.g., K562, HeLa, HepG2)"
    echo
    echo "Options:"
    echo "  -v, --verbose Show detailed progress information"
    echo "  -h, --help    Show this help message"
    echo
    echo "Output format: chr:position:strand:source"
}

# Function for verbose output
verbose() {
    if [ "$VERBOSE" = true ]; then
        echo "[TSS] $1" >&2
    fi
}

# Parse command line arguments
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
            if [ -z "$GENE_NAME" ]; then
                GENE_NAME="$1"
            elif [ -z "$CELL_LINE" ]; then
                CELL_LINE="$1"
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
if [ -z "$GENE_NAME" ] || [ -z "$CELL_LINE" ]; then
    echo "Error: Both gene name and cell line are required"
    show_usage
    exit 1
fi

# Check if required files exist
if [ ! -f "$APPRIS_TSS_TABLE" ]; then
    echo "Error: APPRIS/Gencode annotation file not found: $APPRIS_TSS_TABLE"
    exit 1
fi

if [ ! -f "$FETCH_CAGE_SCRIPT" ]; then
    echo "Error: CAGE fetch script not found: $FETCH_CAGE_SCRIPT"
    exit 1
fi

verbose "Looking up gene: $GENE_NAME"

# Look up gene in APPRIS/Gencode table (support both gene symbols and Ensembl IDs)
GENE_INFO=$(awk -F'\t' -v gene="$GENE_NAME" '
    NR > 1 && ($8 == gene || $6 == gene) {
        print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 "\t" $8 "\t" $11
        found=1
        exit
    }
    END { if (!found) exit 1 }
' "$APPRIS_TSS_TABLE")

# Check if gene was found
if [ $? -ne 0 ]; then
    echo "Error: Gene '$GENE_NAME' not found in annotation file"
    exit 1
fi

# Extract gene information
CHR=$(echo "$GENE_INFO" | cut -f1)
TSS=$(echo "$GENE_INFO" | cut -f2)
GENE_START=$(echo "$GENE_INFO" | cut -f3)
GENE_END=$(echo "$GENE_INFO" | cut -f4)
STRAND=$(echo "$GENE_INFO" | cut -f5)
GENE_ID=$(echo "$GENE_INFO" | cut -f6)
GENE_SYMBOL=$(echo "$GENE_INFO" | cut -f7)
TSS_SOURCE=$(echo "$GENE_INFO" | cut -f8)

verbose "Found gene: $GENE_SYMBOL ($GENE_ID) at $CHR:$TSS ($STRAND)"
verbose "Gene boundaries: $CHR:$GENE_START-$GENE_END"
verbose "TSS source in annotation file: $TSS_SOURCE"

# Calculate search region (gene boundaries + 1kb upstream)
if [ "$STRAND" = "+" ]; then
    # Plus strand: search from 1kb upstream of gene start to gene end
    SEARCH_START=$((GENE_START - 1000))
    SEARCH_END=$GENE_END
else
    # Minus strand: search from gene start to 1kb downstream of gene end
    SEARCH_START=$GENE_START
    SEARCH_END=$((GENE_END + 1000))
fi

# Ensure start doesn't go below 1
if [ $SEARCH_START -lt 1 ]; then
    SEARCH_START=1
fi

verbose "CAGE search region: $CHR:$SEARCH_START-$SEARCH_END"

# Fetch CAGE data
verbose "Fetching CAGE data for $CELL_LINE..."
CAGE_FILE=$("$FETCH_CAGE_SCRIPT" "$CELL_LINE" 2>/dev/null)

if [ $? -ne 0 ] || [ ! -f "$CAGE_FILE" ]; then
    echo "Warning: Failed to fetch CAGE data for $CELL_LINE, using $TSS_SOURCE TSS" >&2
    echo "$CHR:$TSS:$STRAND:$TSS_SOURCE"
    exit 0
fi

verbose "Using CAGE file: $CAGE_FILE"

# Search for CAGE peaks in the region on the correct strand
verbose "Searching for CAGE peaks..."
CAGE_PEAKS=$(gunzip -c "$CAGE_FILE" | awk -F'\t' -v chr="$CHR" -v start="$SEARCH_START" -v end="$SEARCH_END" -v strand="$STRAND" '
    $1 == chr && $6 == strand && $2 <= end && $3 >= start {
        # Calculate overlap with search region
        overlap_start = ($2 > start) ? $2 : start
        overlap_end = ($3 < end) ? $3 : end
        
        if (overlap_start <= overlap_end) {
            # Determine TSS position based on strand
            if (strand == "+") {
                tss_pos = $2  # Use start for plus strand
            } else {
                tss_pos = $3  # Use end for minus strand
            }
            
            # Output: score, tss_position, peak_start, peak_end
            print $5, tss_pos, $2, $3
        }
    }
' | sort -k1,1nr)

# Check if any peaks were found
if [ -z "$CAGE_PEAKS" ]; then
    verbose "No CAGE peaks found in search region"
    echo "Warning: No CAGE peaks found for $GENE_SYMBOL in $CELL_LINE, using $TSS_SOURCE TSS" >&2
    echo "$CHR:$TSS:$STRAND:$TSS_SOURCE"
    exit 0
fi

# Count total peaks
PEAK_COUNT=$(echo "$CAGE_PEAKS" | wc -l)
verbose "Found $PEAK_COUNT CAGE peaks in region"

# Get the highest score and count how many peaks have that score
HIGHEST_SCORE=$(echo "$CAGE_PEAKS" | head -n1 | awk '{print $1}')
TOP_PEAKS=$(echo "$CAGE_PEAKS" | awk -v score="$HIGHEST_SCORE" '$1 == score')
TOP_PEAK_COUNT=$(echo "$TOP_PEAKS" | wc -l)

verbose "Highest CAGE score: $HIGHEST_SCORE"

# Check for ties and warn if multiple peaks have the same highest score
if [ $TOP_PEAK_COUNT -gt 1 ]; then
    echo "Warning: Found $TOP_PEAK_COUNT CAGE peaks with tied highest score ($HIGHEST_SCORE) for $GENE_SYMBOL in $CELL_LINE, selecting most upstream" >&2
    verbose "Tied peaks found, selecting most upstream"
fi

# Select the most upstream peak among those with the highest score
if [ "$STRAND" = "+" ]; then
    # Plus strand: select smallest coordinate (leftmost/most upstream)
    SELECTED_PEAK=$(echo "$TOP_PEAKS" | sort -k2,2n | head -n1)
else
    # Minus strand: select largest coordinate (rightmost/most upstream) 
    SELECTED_PEAK=$(echo "$TOP_PEAKS" | sort -k2,2nr | head -n1)
fi

# Extract the TSS position
CAGE_TSS=$(echo "$SELECTED_PEAK" | awk '{print $2}')
PEAK_START=$(echo "$SELECTED_PEAK" | awk '{print $3}')
PEAK_END=$(echo "$SELECTED_PEAK" | awk '{print $4}')
SELECTED_SCORE=$(echo "$SELECTED_PEAK" | awk '{print $1}')

verbose "Selected CAGE peak: $CHR:$PEAK_START-$PEAK_END (score: $SELECTED_SCORE)"
verbose "CAGE TSS position: $CHR:$CAGE_TSS ($STRAND)"

# Output the result with CAGE as source
echo "$CHR:$CAGE_TSS:$STRAND:CAGE"
