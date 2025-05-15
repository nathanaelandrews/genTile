#!/bin/bash

# Determine script location
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$SCRIPT_DIR" )"

# Default values
DEFAULT_MEMORY="4G"
DEFAULT_ENZYME="spcas9ngg"  # CRISPRi default

# Help function
show_usage() {
  echo "Usage: $(basename "$0") [options]"
  echo
  echo "Options:"
  echo "  -m, --memory <size>    Java heap memory allocation (default: $DEFAULT_MEMORY)"
  echo "                         Examples: 4G, 8G, 16G, etc."
  echo "  -e, --enzyme <enzyme>  CRISPR enzyme to use (default: $DEFAULT_ENZYME)"
  echo "                         Options: spcas9ngg19 (CRISPRi), spcas9ngg, spcas9nag, cpf1"
  echo "  -h, --help             Show this help message"
  echo
  echo "Example:"
  echo "  $(basename "$0") --memory 16G --enzyme spcas9ngg"
}

# Parse command line arguments
MEMORY="$DEFAULT_MEMORY"
ENZYME="$DEFAULT_ENZYME"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--memory)
      # Check if memory has a unit (G, M, etc.)
      if [[ "$2" =~ ^[0-9]+$ ]]; then
        # No unit provided, assume G
        MEMORY="${2}G"
      else
        MEMORY="$2"
      fi
      shift 2
      ;;
    -e|--enzyme)
      ENZYME="$2"
      shift 2
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_usage
      exit 1
      ;;
  esac
done

# Set paths
GENOME_DIR="$REPO_DIR/data/reference/genome/hg38"
GENOME_FA="$GENOME_DIR/hg38.fa"
DATABASE_DIR="$REPO_DIR/data/reference/flashfry_db"
DATABASE_FILE="$DATABASE_DIR/hg38_${ENZYME}.db"
TMP_DIR="$REPO_DIR/tmp"

# Create directories
mkdir -p "$DATABASE_DIR"
mkdir -p "$TMP_DIR"
mkdir -p "$REPO_DIR/external/flashfry"

# Check if FlashFry JAR exists
FLASHFRY_JAR="$REPO_DIR/external/flashfry/FlashFry-assembly-1.15.jar"
if [ ! -f "$FLASHFRY_JAR" ]; then
  echo "FlashFry JAR not found. Downloading..."
  wget -O "$FLASHFRY_JAR" https://github.com/mckennalab/FlashFry/releases/download/1.15/FlashFry-assembly-1.15.jar
  
  if [ $? -eq 0 ]; then
    echo "FlashFry downloaded successfully!"
  else
    echo "Error: Failed to download FlashFry. Please download manually:"
    echo "wget -O $FLASHFRY_JAR https://github.com/mckennalab/FlashFry/releases/download/1.15/FlashFry-assembly-1.15.jar"
    exit 1
  fi
else
  echo "FlashFry JAR already exists at: $FLASHFRY_JAR"
fi

# Validate enzyme choice
valid_enzymes=("spcas9ngg19" "spcas9ngg" "spcas9nag" "cpf1" "spcas9")
if ! [[ " ${valid_enzymes[*]} " =~ " ${ENZYME} " ]]; then
  echo "Error: Invalid enzyme '$ENZYME'"
  echo "Valid options: ${valid_enzymes[*]}"
  exit 1
fi

# Set Java memory allocation
JAVA_MEM="-Xmx$MEMORY"

echo "Starting FlashFry database creation..."
echo "This process may take several hours for a full genome."
echo "Genome: $GENOME_FA"
echo "Database: $DATABASE_DIR"
echo "Enzyme: $ENZYME"
echo "Memory allocation: $MEMORY"

# Run FlashFry index command
java $JAVA_MEM -jar "$REPO_DIR/external/flashfry/FlashFry-assembly-1.15.jar" \
  index \
  --tmpLocation "$TMP_DIR" \
  --database "$DATABASE_FILE" \
  --reference "$GENOME_FA" \
  --enzyme "$ENZYME"

# Check if successful
if [ $? -eq 0 ]; then
  echo "FlashFry database creation completed successfully!"
  echo "Database location: $DATABASE_DIR"
  
  # Clean up temporary files
  echo "Cleaning up temporary files..."
  rm -rf "$TMP_DIR"
else
  echo "Error: FlashFry database creation failed."
  echo "Please check the error messages above."
fi
