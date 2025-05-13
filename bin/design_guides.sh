#!/bin/bash

# design_guides.sh - A wrapper script for running FlashFry guide design
#
# This script automates the process of running FlashFry's discover and score
# steps with sensible defaults for CRISPRi applications. It allows users to
# simply provide an input FASTA file and get scored guides, while also
# offering the flexibility to customize any FlashFry parameter.

# Determine script location regardless of where it's called from
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$SCRIPT_DIR" )"

# Default values for parameters
DEFAULT_OUTPUT="guides.scored.txt"
DEFAULT_DATABASE="$REPO_DIR/data/reference/flashfry_db/hg38_spcas9ngg19.db"
DEFAULT_FLASHFRY="$REPO_DIR/external/flashfry/FlashFry-assembly-1.15.jar"
DEFAULT_JAVA_MEMORY="4G"
DEFAULT_SCORING_METRICS="dangerous,minot,reciprocalofftargets"

# Help/usage function to display available options
show_usage() {
  echo "Usage: $(basename "$0") [options]"
  echo
  echo "A wrapper for FlashFry to design and score CRISPR guides."
  echo
  echo "Required Options:"
  echo "  -i, --input <file>         Input FASTA file with target sequences"
  echo
  echo "Common Options:"
  echo "  -o, --output <file>        Output file for scored guides (default: $DEFAULT_OUTPUT)"
  echo "  -d, --database <path>      Path to FlashFry database (default: repository database)"
  echo "  -f, --flashfry <path>      Path to FlashFry JAR file (default: repository JAR)"
  echo "  -m, --java-memory <size>   Java heap memory size (default: $DEFAULT_JAVA_MEMORY)"
  echo "  -v, --verbose              Show detailed progress information"
  echo "  -h, --help                 Show this help message"
  echo
  echo "Advanced Options:"
  echo "  --discover-args \"<args>\"   Additional arguments to pass to FlashFry discover step"
  echo "  --score-args \"<args>\"      Additional arguments to pass to FlashFry score step"
  echo "  --keep-intermediate <file> Keep the intermediate discovery output file"
  echo
  echo "Examples:"
  echo "  # Basic usage with defaults"
  echo "  $(basename "$0") --input sequences.fa"
  echo
  echo "  # Custom output file"
  echo "  $(basename "$0") --input sequences.fa --output my_guides.txt"
  echo
  echo "  # Custom parameters for discover and score steps"
  echo "  $(basename "$0") --input sequences.fa \\"
  echo "    --discover-args \"--maxMismatch 3\" \\"
  echo "    --score-args \"--scoringMetrics dangerous,minot\""
}

# Initialize variables with defaults
INPUT=""
OUTPUT="$DEFAULT_OUTPUT"
DATABASE="$DEFAULT_DATABASE"
FLASHFRY="$DEFAULT_FLASHFRY"
JAVA_MEMORY="$DEFAULT_JAVA_MEMORY"
VERBOSE=false
KEEP_INTERMEDIATE=""
DISCOVER_ARGS=""
SCORE_ARGS=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input)
      # Input FASTA file (required)
      INPUT="$2"
      shift 2
      ;;
    -o|--output)
      # Output file for scored guides
      OUTPUT="$2"
      shift 2
      ;;
    -d|--database)
      # Path to FlashFry database
      DATABASE="$2"
      shift 2
      ;;
    -f|--flashfry)
      # Path to FlashFry JAR
      FLASHFRY="$2"
      shift 2
      ;;
    -m|--java-memory)
      # Java heap memory size
      # If just a number is provided, assume gigabytes
      if [[ "$2" =~ ^[0-9]+$ ]]; then
        JAVA_MEMORY="${2}G"
      else
        JAVA_MEMORY="$2"
      fi
      shift 2
      ;;
    -v|--verbose)
      # Enable verbose output
      VERBOSE=true
      shift
      ;;
    --discover-args)
      # Custom arguments for discover step
      DISCOVER_ARGS="$2"
      shift 2
      ;;
    --score-args)
      # Custom arguments for score step
      SCORE_ARGS="$2"
      shift 2
      ;;
    --keep-intermediate)
      # Keep intermediate discovery output
      KEEP_INTERMEDIATE="$2"
      shift 2
      ;;
    -h|--help)
      # Show help and exit
      show_usage
      exit 0
      ;;
    *)
      # Unknown option
      echo "Unknown option: $1"
      show_usage
      exit 1
      ;;
  esac
done

# Function for verbose output
verbose() {
  if [ "$VERBOSE" = true ]; then
    echo "[INFO] $1"
  fi
}

# Validate required arguments
if [ -z "$INPUT" ]; then
  echo "Error: Input FASTA file is required (-i, --input)"
  show_usage
  exit 1
fi

# Check if input file exists
if [ ! -f "$INPUT" ]; then
  echo "Error: Input file not found: $INPUT"
  exit 1
fi

# Check if FlashFry JAR exists
if [ ! -f "$FLASHFRY" ]; then
  echo "Error: FlashFry JAR not found: $FLASHFRY"
  echo "You can specify a custom path with --flashfry or run setup.sh to download it."
  exit 1
fi

# Check if database exists
if [ ! -f "$DATABASE" ]; then
  echo "Error: FlashFry database not found: $DATABASE"
  echo "You need to create a database or specify an existing one with --database."
  exit 1
fi

# Set up Java memory parameter
JAVA_OPTS="-Xmx$JAVA_MEMORY"

# Create a temporary file for the intermediate output if not specified
if [ -z "$KEEP_INTERMEDIATE" ]; then
  # Create a temporary file that will be deleted at the end
  INTERMEDIATE_OUTPUT="$(mktemp).flashfry.discover"
  verbose "Created temporary file for intermediate output: $INTERMEDIATE_OUTPUT"
else
  # Use the specified file path for the intermediate output
  INTERMEDIATE_OUTPUT="$KEEP_INTERMEDIATE"
  verbose "Will save intermediate output to: $INTERMEDIATE_OUTPUT"
fi

# Display configuration in verbose mode
verbose "Configuration:"
verbose "  Input: $INPUT"
verbose "  Output: $OUTPUT"
verbose "  Database: $DATABASE"
verbose "  FlashFry JAR: $FLASHFRY"
verbose "  Java Memory: $JAVA_MEMORY"
verbose "  Discover Args: $DISCOVER_ARGS"
verbose "  Score Args: $SCORE_ARGS"

# Step 1: Run FlashFry discover
verbose "Starting FlashFry discover step..."

# Build discover command
# Start with the basic command
DISCOVER_CMD="java $JAVA_OPTS -jar \"$FLASHFRY\" discover --database \"$DATABASE\" --fasta \"$INPUT\" --output \"$INTERMEDIATE_OUTPUT\""

# Add default parameters (can be overridden by user-provided args)
# We don't add defaults if user specified the same parameter in DISCOVER_ARGS
if [[ ! "$DISCOVER_ARGS" =~ --maxMismatch ]]; then
  DISCOVER_CMD="$DISCOVER_CMD --maxMismatch 4"
fi
if [[ ! "$DISCOVER_ARGS" =~ --flankingSequence ]]; then
  DISCOVER_CMD="$DISCOVER_CMD --flankingSequence 10" 
fi
if [[ ! "$DISCOVER_ARGS" =~ --maximumOffTargets ]]; then
  DISCOVER_CMD="$DISCOVER_CMD --maximumOffTargets 2000"
fi

# Add any user-provided additional arguments
if [ -n "$DISCOVER_ARGS" ]; then
  DISCOVER_CMD="$DISCOVER_CMD $DISCOVER_ARGS"
fi

# Execute discover command
verbose "Running: $DISCOVER_CMD"
eval "$DISCOVER_CMD"

# Check if discover was successful
if [ $? -ne 0 ]; then
  echo "Error: FlashFry discover step failed."
  # Clean up temporary file if it exists and we're not keeping it
  if [ -z "$KEEP_INTERMEDIATE" ] && [ -f "$INTERMEDIATE_OUTPUT" ]; then
    verbose "Removing temporary file: $INTERMEDIATE_OUTPUT"
    rm -f "$INTERMEDIATE_OUTPUT"
  fi
  exit 1
fi

verbose "FlashFry discover step completed successfully."

# Step 2: Run FlashFry score
verbose "Starting FlashFry score step..."

# Build score command
# Start with the basic command
SCORE_CMD="java $JAVA_OPTS -jar \"$FLASHFRY\" score --database \"$DATABASE\" --input \"$INTERMEDIATE_OUTPUT\" --output \"$OUTPUT\""

# Add default scoring metrics if not specified by user
if [[ ! "$SCORE_ARGS" =~ --scoringMetrics ]]; then
  SCORE_CMD="$SCORE_CMD --scoringMetrics $DEFAULT_SCORING_METRICS"
fi

# Add any user-provided additional arguments
if [ -n "$SCORE_ARGS" ]; then
  SCORE_CMD="$SCORE_CMD $SCORE_ARGS"
fi

# Execute score command
verbose "Running: $SCORE_CMD"
eval "$SCORE_CMD"

# Check if score was successful
if [ $? -ne 0 ]; then
  echo "Error: FlashFry score step failed."
  # Clean up temporary file if it exists and we're not keeping it
  if [ -z "$KEEP_INTERMEDIATE" ] && [ -f "$INTERMEDIATE_OUTPUT" ]; then
    verbose "Removing temporary file: $INTERMEDIATE_OUTPUT"
    rm -f "$INTERMEDIATE_OUTPUT"
  fi
  exit 1
fi

verbose "FlashFry score step completed successfully."

# Clean up intermediate file if not keeping it
if [ -z "$KEEP_INTERMEDIATE" ] && [ -f "$INTERMEDIATE_OUTPUT" ]; then
  verbose "Removing temporary file: $INTERMEDIATE_OUTPUT"
  rm -f "$INTERMEDIATE_OUTPUT"
else
  echo "Intermediate discovery output saved to: $INTERMEDIATE_OUTPUT"
fi

# Output success message
echo "Guide design complete! Scored guides saved to: $OUTPUT"
echo "Used scoring metrics: $(if [[ "$SCORE_ARGS" =~ --scoringMetrics ]]; then echo "$SCORE_ARGS" | grep -o "scoringMetrics[[:space:]]\+[^ ]\+" | sed 's/scoringMetrics[[:space:]]\+//'; else echo "$DEFAULT_SCORING_METRICS"; fi)"

# Exit successfully
exit 0
