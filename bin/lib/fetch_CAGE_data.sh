#!/bin/bash

# fetch_CAGE_data.sh - Download and cache ENCODE CAGE BED files
# Usage: fetch_CAGE_data.sh <cell_line_name>

# Determine script location
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$SCRIPT_DIR" )" )"

# Paths
CAGE_TABLE="$REPO_DIR/data/reference/gene_annotations/ENCODE_CAGE_data.tsv"
CACHE_DIR="$REPO_DIR/data/reference/CAGE_cache"

# Function to show usage
show_usage() {
    echo "Usage: $(basename "$0") <cell_line_name>"
    echo
    echo "Download and cache ENCODE CAGE BED file for specified cell line."
    echo
    echo "Arguments:"
    echo "  cell_line_name    Cell line short name (e.g., K562, HeLa, HepG2)"
    echo
    echo "Available cell lines:"
    if [ -f "$CAGE_TABLE" ]; then
	printf "%-20s %-30s %-15s %s\n" "SHORT_NAME (input)" "FULL_NAME" "ENCODE_ID" "DESCRIPTION"
        printf "%-20s %-30s %-15s %s\n" "----------" "---------" "---------" "-----------"
        awk -F'\t' 'NR>1 {
            printf "%-20s %-30s %-15s %s\n", $2, substr($1,1,30), $4, substr($3,1,50)
        }' "$CAGE_TABLE" | sort
    else
        echo "  (CAGE data table not found)"
    fi
}

# Parse command line arguments
if [ $# -ne 1 ]; then
    echo "Error: Cell line name is required"
    show_usage
    exit 1
fi

CELL_LINE="$1"

# Check if CAGE table exists
if [ ! -f "$CAGE_TABLE" ]; then
    echo "Error: CAGE data table not found: $CAGE_TABLE"
    exit 1
fi

# Look up cell line in the table (case-insensitive)
CAGE_INFO=$(awk -F'\t' -v cell="$CELL_LINE" '
    BEGIN { IGNORECASE=1 }
    NR>1 && $2 == cell { 
        print $2 "\t" $6 
        found=1
        exit
    }
    END { if (!found) exit 1 }
' "$CAGE_TABLE")

# Check if cell line was found
if [ $? -ne 0 ]; then
    echo "Error: Cell line '$CELL_LINE' not found in CAGE data table"
    echo
    echo "Available cell lines:"
    printf "%-20s %-30s %-15s %s\n" "SHORT_NAME (input)" "FULL_NAME" "ENCODE_ID" "DESCRIPTION"
    printf "%-20s %-30s %-15s %s\n" "----------" "---------" "---------" "-----------"
    awk -F'\t' 'NR>1 {
        printf "%-20s %-30s %-15s %s\n", $2, substr($1,1,30), $4, substr($3,1,50)
    }' "$CAGE_TABLE" | sort
    exit 1
fi

# Extract info
SHORT_NAME=$(echo "$CAGE_INFO" | cut -f1)
DOWNLOAD_URL=$(echo "$CAGE_INFO" | cut -f2)

# Create cache directory if it doesn't exist
mkdir -p "$CACHE_DIR"

# Define cache file path
CACHE_FILE="$CACHE_DIR/${SHORT_NAME}.bed.gz"

# Check if file already exists in cache
if [ -f "$CACHE_FILE" ]; then
    echo "Using cached CAGE data: $CACHE_FILE" >&2
    echo "$CACHE_FILE"
    exit 0
fi

# Download the file
echo "Downloading CAGE data for $SHORT_NAME..." >&2
echo "URL: $DOWNLOAD_URL" >&2

if command -v wget > /dev/null 2>&1; then
    # Use wget if available
    wget -q -O "$CACHE_FILE" "$DOWNLOAD_URL"
elif command -v curl > /dev/null 2>&1; then
    # Use curl if wget not available
    curl -s -o "$CACHE_FILE" "$DOWNLOAD_URL"
else
    echo "Error: Neither wget nor curl found. Please install one of them."
    exit 1
fi

# Check if download was successful
if [ $? -eq 0 ] && [ -s "$CACHE_FILE" ]; then
    echo "Successfully downloaded and cached: $CACHE_FILE" >&2
    echo "$CACHE_FILE"
else
    echo "Error: Failed to download CAGE data from $DOWNLOAD_URL"
    rm -f "$CACHE_FILE"  # Clean up partial download
    exit 1
fi
