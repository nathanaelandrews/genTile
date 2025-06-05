#!/bin/bash

# list_enzymes.sh - Browse and search restriction enzymes database
# Usage: list_enzymes.sh [search_term] [options]

# Determine script location
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$SCRIPT_DIR" )"

# Paths
ENZYMES_DB="$REPO_DIR/data/reference/restriction_enzymes/enzymes.tsv"

# Default values
SEARCH_TERM=""
SHOW_SEQUENCES=false
SHOW_SOURCES=false
MAX_RESULTS=600

# Function to show usage
show_usage() {
    echo "Usage: $(basename "$0") [search_term] [options]"
    echo
    echo "Browse and search the restriction enzymes database."
    echo
    echo "Arguments:"
    echo "  search_term           Search for enzymes (case-insensitive, partial matches)"
    echo "                        Leave empty to list all enzymes"
    echo
    echo "Options:"
    echo "  -s, --sequences       Show recognition sequences"
    echo "  -c, --sources         Show commercial sources"
    echo "  -n, --max <number>    Maximum results to show (default: $MAX_RESULTS)"
    echo "  -h, --help           Show this help message"
    echo
    echo "Examples:"
    echo "  $(basename "$0")                    # List all enzymes"
    echo "  $(basename "$0") bsa               # Find enzymes containing 'bsa'"
    echo "  $(basename "$0") eco --sequences   # Find 'eco' enzymes with sequences"
    echo "  $(basename "$0") --sources         # List all with commercial sources"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--sequences)
            SHOW_SEQUENCES=true
            shift
            ;;
        -c|--sources)
            SHOW_SOURCES=true
            shift
            ;;
        -n|--max)
            MAX_RESULTS="$2"
            shift 2
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
            if [ -z "$SEARCH_TERM" ]; then
                SEARCH_TERM="$1"
            else
                echo "Error: Multiple search terms provided"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Check if database exists
if [ ! -f "$ENZYMES_DB" ]; then
    echo "Error: Restriction enzymes database not found: $ENZYMES_DB"
    echo "Please ensure the database file is present in the repository."
    exit 1
fi

# Validate max results
if ! [[ "$MAX_RESULTS" =~ ^[0-9]+$ ]] || [ "$MAX_RESULTS" -lt 1 ]; then
    echo "Error: --max must be a positive integer"
    exit 1
fi

# Build search command
if [ -n "$SEARCH_TERM" ]; then
    # Case-insensitive search in enzyme names
    SEARCH_CMD="awk -F'\t' 'BEGIN{IGNORECASE=1} NR>1 && tolower(\$1) ~ tolower(\"$SEARCH_TERM\") {print}' \"$ENZYMES_DB\""
else
    # Show all enzymes (skip header)
    SEARCH_CMD="awk -F'\t' 'NR>1 {print}' \"$ENZYMES_DB\""
fi

# Execute search and limit results
RESULTS=$(eval "$SEARCH_CMD" | head -n "$MAX_RESULTS")

# Check if any results found
if [ -z "$RESULTS" ]; then
    if [ -n "$SEARCH_TERM" ]; then
        echo "No enzymes found matching '$SEARCH_TERM'"
        echo
        echo "Try a broader search or use:"
        echo "  $(basename "$0") --help"
    else
        echo "Error: No enzymes found in database"
    fi
    exit 1
fi

# Count total results (before limiting)
if [ -n "$SEARCH_TERM" ]; then
    TOTAL_COUNT=$(eval "$SEARCH_CMD" | wc -l)
else
    TOTAL_COUNT=$(awk 'NR>1' "$ENZYMES_DB" | wc -l)
fi

# Display results header
if [ -n "$SEARCH_TERM" ]; then
    echo "Restriction enzymes matching '$SEARCH_TERM':"
else
    echo "All restriction enzymes:"
fi

if [ "$TOTAL_COUNT" -gt "$MAX_RESULTS" ]; then
    echo "Showing first $MAX_RESULTS of $TOTAL_COUNT results"
else
    echo "Found $TOTAL_COUNT enzyme(s)"
fi
echo

# Determine output format based on options
if [ "$SHOW_SEQUENCES" = true ] && [ "$SHOW_SOURCES" = true ]; then
    # Show everything
    printf "%-15s %-20s %-20s %-15s %s\n" "ENZYME" "RECOGNITION_SEQ" "ANTISENSE_SEQ" "PROTOTYPE" "SOURCES"
    printf "%-15s %-20s %-20s %-15s %s\n" "------" "---------------" "-------------" "---------" "-------"
    echo "$RESULTS" | while IFS=$'\t' read -r enzyme recognition antisense prototype sources; do
        printf "%-15s %-20s %-20s %-15s %s\n" "$enzyme" "$recognition" "$antisense" "$prototype" "$sources"
    done
elif [ "$SHOW_SEQUENCES" = true ]; then
    # Show sequences only
    printf "%-15s %-20s %-20s %s\n" "ENZYME" "RECOGNITION_SEQ" "ANTISENSE_SEQ" "PROTOTYPE"
    printf "%-15s %-20s %-20s %s\n" "------" "---------------" "-------------" "---------"
    echo "$RESULTS" | while IFS=$'\t' read -r enzyme recognition antisense prototype sources; do
        printf "%-15s %-20s %-20s %s\n" "$enzyme" "$recognition" "$antisense" "$prototype"
    done
elif [ "$SHOW_SOURCES" = true ]; then
    # Show sources only
    printf "%-15s %-15s %s\n" "ENZYME" "PROTOTYPE" "COMMERCIAL_SOURCES"
    printf "%-15s %-15s %s\n" "------" "---------" "------------------"
    echo "$RESULTS" | while IFS=$'\t' read -r enzyme recognition antisense prototype sources; do
        printf "%-15s %-15s %s\n" "$enzyme" "$prototype" "$sources"
    done
else
    # Show just enzyme names in columns (default)
    echo "ENZYME NAMES:"
    echo "-------------"
    
    # Get enzyme names and arrange in columns
    ENZYME_NAMES=$(echo "$RESULTS" | cut -f1 | sort)
    
    # Count total enzymes to display
    ENZYME_COUNT=$(echo "$ENZYME_NAMES" | wc -l)
    
    # Calculate columns (aim for ~10 columns, adjust based on terminal width)
    COLUMNS=10
    ROWS_PER_COL=$(( (ENZYME_COUNT + COLUMNS - 1) / COLUMNS ))  # Ceiling division
    
    # Create temporary file with sorted enzyme names
    TEMP_NAMES=$(mktemp)
    echo "$ENZYME_NAMES" > "$TEMP_NAMES"
    
    # Print in columns
    for ((row=1; row<=ROWS_PER_COL; row++)); do
        line=""
        for ((col=0; col<COLUMNS; col++)); do
            line_num=$((col * ROWS_PER_COL + row))
            if [ "$line_num" -le "$ENZYME_COUNT" ]; then
                enzyme=$(sed -n "${line_num}p" "$TEMP_NAMES")
                if [ -n "$enzyme" ]; then
                    printf "%-12s " "$enzyme"
                fi
            fi
        done
        echo  # New line after each row
    done
    
    # Clean up
    rm -f "$TEMP_NAMES"
fi

# Show usage hint if results were limited
if [ "$TOTAL_COUNT" -gt "$MAX_RESULTS" ]; then
    echo
    echo "Use --max <number> to see more results or refine your search term."
fi

# Show additional options hint for default view
if [ "$SHOW_SEQUENCES" = false ] && [ "$SHOW_SOURCES" = false ] && [ -n "$SEARCH_TERM" ]; then
    echo
    echo "Use --sequences to see recognition sites, --sources for commercial availability."
elif [ "$SHOW_SEQUENCES" = false ] && [ "$SHOW_SOURCES" = false ] && [ -z "$SEARCH_TERM" ]; then
    echo
    echo "Use --sequences to see recognition sites, --sources for commercial availability."
    echo "Search for specific enzymes: $(basename "$0") <search_term>"
fi
