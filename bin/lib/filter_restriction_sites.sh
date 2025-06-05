#!/bin/bash

# filter_restriction_sites.sh - Filter FlashFry output to remove guides with restriction sites
# Usage: filter_restriction_sites.sh <input_file> <enzyme_list> [options]

# Determine script location
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$( dirname "$SCRIPT_DIR" )" )"

# Paths
ENZYMES_DB="$REPO_DIR/data/reference/restriction_enzymes/enzymes.tsv"

# Default values
VERBOSE=false

# Function to show usage
show_usage() {
    echo "Usage: $(basename "$0") <input_file> <enzyme_list> [options]"
    echo
    echo "Filter FlashFry output to remove guides containing restriction enzyme sites."
    echo
    echo "Arguments:"
    echo "  input_file       FlashFry scored output file"
    echo "  enzyme_list      Comma-separated list of enzyme names (case-sensitive)"
    echo
    echo "Options:"
    echo "  -v, --verbose    Show detailed filtering information"
    echo "  -h, --help       Show this help message"
    echo
    echo "Examples:"
    echo "  $(basename "$0") guides.scored.txt BsaI"
    echo "  $(basename "$0") guides.scored.txt BsaI,BsmBI,EcoRI"
}

# Function for verbose output
verbose() {
    if [ "$VERBOSE" = true ]; then
        echo "[FILTER] $1" >&2
    fi
}

# Function to expand IUPAC codes to all possible sequences
expand_iupac() {
    local sequence="$1"
    local result=()
    
    # Convert to array of characters
    local chars=()
    for ((i=0; i<${#sequence}; i++)); do
        chars+=("${sequence:$i:1}")
    done
    
    # Start with empty result
    result=("")
    
    # Process each character
    for char in "${chars[@]}"; do
        local new_result=()
        case "$char" in
            A) for seq in "${result[@]}"; do new_result+=("${seq}A"); done ;;
            T) for seq in "${result[@]}"; do new_result+=("${seq}T"); done ;;
            G) for seq in "${result[@]}"; do new_result+=("${seq}G"); done ;;
            C) for seq in "${result[@]}"; do new_result+=("${seq}C"); done ;;
            R) for seq in "${result[@]}"; do new_result+=("${seq}A" "${seq}G"); done ;;
            Y) for seq in "${result[@]}"; do new_result+=("${seq}C" "${seq}T"); done ;;
            M) for seq in "${result[@]}"; do new_result+=("${seq}A" "${seq}C"); done ;;
            K) for seq in "${result[@]}"; do new_result+=("${seq}G" "${seq}T"); done ;;
            S) for seq in "${result[@]}"; do new_result+=("${seq}G" "${seq}C"); done ;;
            W) for seq in "${result[@]}"; do new_result+=("${seq}A" "${seq}T"); done ;;
            B) for seq in "${result[@]}"; do new_result+=("${seq}C" "${seq}G" "${seq}T"); done ;;
            D) for seq in "${result[@]}"; do new_result+=("${seq}A" "${seq}G" "${seq}T"); done ;;
            H) for seq in "${result[@]}"; do new_result+=("${seq}A" "${seq}C" "${seq}T"); done ;;
            V) for seq in "${result[@]}"; do new_result+=("${seq}A" "${seq}C" "${seq}G"); done ;;
            N) for seq in "${result[@]}"; do new_result+=("${seq}A" "${seq}C" "${seq}G" "${seq}T"); done ;;
            *) 
                echo "Error: Unknown IUPAC code '$char' in sequence '$sequence'" >&2
                exit 1
                ;;
        esac
        result=("${new_result[@]}")
    done
    
    # Output all expanded sequences, one per line
    printf '%s\n' "${result[@]}"
}

# Function to create reverse complement
reverse_complement() {
    local sequence="$1"
    local complement=""
    local length=${#sequence}
    
    # Build complement in reverse order
    for ((i=length-1; i>=0; i--)); do
        case "${sequence:$i:1}" in
            A) complement="${complement}T" ;;
            T) complement="${complement}A" ;;
            G) complement="${complement}C" ;;
            C) complement="${complement}G" ;;
            *) 
                echo "Error: Cannot reverse complement sequence with ambiguous bases: $sequence" >&2
                echo "Please ensure enzyme sequences are expanded before reverse complementing." >&2
                exit 1
                ;;
        esac
    done
    
    echo "$complement"
}

# Parse command line arguments
INPUT_FILE=""
ENZYME_LIST=""

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
            elif [ -z "$ENZYME_LIST" ]; then
                ENZYME_LIST="$1"
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
if [ -z "$INPUT_FILE" ] || [ -z "$ENZYME_LIST" ]; then
    echo "Error: Both input file and enzyme list are required"
    show_usage
    exit 1
fi

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file not found: $INPUT_FILE"
    exit 1
fi

# Check if database exists
if [ ! -f "$ENZYMES_DB" ]; then
    echo "Error: Restriction enzymes database not found: $ENZYMES_DB"
    exit 1
fi

# Parse enzyme list
IFS=',' read -ra ENZYMES <<< "$ENZYME_LIST"
verbose "Requested enzymes: ${ENZYMES[*]}"

# Validate enzymes and collect recognition sequences
ALL_PATTERNS=()
for enzyme in "${ENZYMES[@]}"; do
    # Trim whitespace
    enzyme=$(echo "$enzyme" | tr -d '[:space:]')
    
    if [ -z "$enzyme" ]; then
        continue
    fi
    
    verbose "Looking up enzyme: $enzyme"
    
    # Look up enzyme in database (case-sensitive)
    ENZYME_INFO=$(awk -F'\t' -v enzyme="$enzyme" 'NR>1 && $1 == enzyme {print $2 "\t" $3; exit}' "$ENZYMES_DB")
    
    if [ -z "$ENZYME_INFO" ]; then
        echo "Error: Enzyme '$enzyme' not found in database"
        echo "Use the following command to search for available enzymes:"
        echo "  $REPO_DIR/bin/list_enzymes.sh $enzyme"
        exit 1
    fi
    
    # Extract recognition sequences
    RECOGNITION_SEQ=$(echo "$ENZYME_INFO" | cut -f1)
    ANTISENSE_SEQ=$(echo "$ENZYME_INFO" | cut -f2)
    
    verbose "  Recognition sequence: $RECOGNITION_SEQ"
    verbose "  Antisense sequence: $ANTISENSE_SEQ"
    
    # Expand IUPAC codes for recognition sequence
    verbose "  Expanding IUPAC codes for recognition sequence..."
    EXPANDED_RECOGNITION=$(expand_iupac "$RECOGNITION_SEQ")
    
    # Add all expanded patterns
    while IFS= read -r pattern; do
        if [ -n "$pattern" ]; then
            ALL_PATTERNS+=("$pattern")
            verbose "    Pattern: $pattern"
            
            # Also add reverse complement of each pattern
            RC_PATTERN=$(reverse_complement "$pattern")
            ALL_PATTERNS+=("$RC_PATTERN")
            verbose "    Reverse complement: $RC_PATTERN"
        fi
    done <<< "$EXPANDED_RECOGNITION"
    
    # If antisense is different from recognition, expand it too
    if [ "$ANTISENSE_SEQ" != "$RECOGNITION_SEQ" ]; then
        verbose "  Expanding IUPAC codes for antisense sequence..."
        EXPANDED_ANTISENSE=$(expand_iupac "$ANTISENSE_SEQ")
        
        while IFS= read -r pattern; do
            if [ -n "$pattern" ]; then
                ALL_PATTERNS+=("$pattern")
                verbose "    Antisense pattern: $pattern"
                
                # Also add reverse complement
                RC_PATTERN=$(reverse_complement "$pattern")
                ALL_PATTERNS+=("$RC_PATTERN")
                verbose "    Antisense reverse complement: $RC_PATTERN"
            fi
        done <<< "$EXPANDED_ANTISENSE"
    fi
done

# Remove duplicates from patterns
UNIQUE_PATTERNS=($(printf '%s\n' "${ALL_PATTERNS[@]}" | sort -u))
verbose "Total unique patterns to check: ${#UNIQUE_PATTERNS[@]}"

# Get target sequence column from FlashFry output
HEADER=$(head -n 1 "$INPUT_FILE")
TARGET_COL=$(echo "$HEADER" | tr '\t' '\n' | grep -n "^target$" | cut -d: -f1)

if [ -z "$TARGET_COL" ]; then
    echo "Error: Could not find 'target' column in FlashFry output"
    echo "Available columns:"
    echo "$HEADER" | tr '\t' '\n' | nl
    exit 1
fi

verbose "Target sequence column: $TARGET_COL"

# Create temporary file for patterns
TMP_PATTERNS=$(mktemp)
printf '%s\n' "${UNIQUE_PATTERNS[@]}" > "$TMP_PATTERNS"
verbose "Created temporary patterns file: $TMP_PATTERNS"

# Filter guides using awk
verbose "Filtering guides..."

INITIAL_COUNT=$(awk 'NR>1' "$INPUT_FILE" | wc -l)
verbose "Initial guide count: $INITIAL_COUNT"

# Create awk script that checks if any pattern matches the target sequence
awk -F'\t' -v target_col="$TARGET_COL" -v patterns_file="$TMP_PATTERNS" '
BEGIN {
    # Load all patterns
    pattern_count = 0
    while ((getline pattern < patterns_file) > 0) {
        patterns[++pattern_count] = pattern
    }
    close(patterns_file)
}
NR == 1 {
    # Print header
    print
    next
}
{
    target_seq = $target_col
    has_site = 0
    
    # Check if target sequence contains any restriction site
    for (i = 1; i <= pattern_count; i++) {
        if (index(target_seq, patterns[i]) > 0) {
            has_site = 1
            break
        }
    }
    
    # Print line only if no restriction sites found
    if (!has_site) {
        print
    }
}' "$INPUT_FILE"

# Count remaining guides by re-running the same filter logic
TMP_PATTERNS2=$(mktemp)
printf '%s\n' "${UNIQUE_PATTERNS[@]}" > "$TMP_PATTERNS2"

FINAL_COUNT=$(awk -F'\t' -v target_col="$TARGET_COL" -v patterns_file="$TMP_PATTERNS2" '
BEGIN {
    # Load all patterns
    pattern_count = 0
    while ((getline pattern < patterns_file) > 0) {
        patterns[++pattern_count] = pattern
    }
    close(patterns_file)
}
NR > 1 {
    target_seq = $target_col
    has_site = 0
    
    # Check if target sequence contains any restriction site
    for (i = 1; i <= pattern_count; i++) {
        if (index(target_seq, patterns[i]) > 0) {
            has_site = 1
            break
        }
    }
    
    # Count lines without restriction sites
    if (!has_site) {
        count++
    }
}
END {
    print count + 0
}' "$INPUT_FILE")

FILTERED_COUNT=$((INITIAL_COUNT - FINAL_COUNT))

# Clean up temporary files
rm -f "$TMP_PATTERNS" "$TMP_PATTERNS2"

verbose "Filtering complete:"
verbose "  Initial guides: $INITIAL_COUNT"
verbose "  Guides with restriction sites: $FILTERED_COUNT"
verbose "  Remaining guides: $FINAL_COUNT"

if [ "$FILTERED_COUNT" -gt 0 ]; then
    echo "Filtered out $FILTERED_COUNT guides containing restriction sites for: $ENZYME_LIST" >&2
fi
