#!/bin/bash

# Get sequence upstream of TSS for gene(s)
# 
#TODO: Change the usage when done:
# Usage: get_sequence.sh [options] <gene_name | gene_file>

# Determine script location regardless of where it's called from
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$SCRIPT_DIR" )"


# Default values
#DISTANCE=2000 -- From when we had a fixed window from TSS and upstream.
UPSTREAM_DISTANCE=1500   # Default bp upstream of TSS
DOWNSTREAM_DISTANCE=500  # Default bp downstream of TSS
OUTPUT="output/sequences.fa" # Default output to stdout
VERBOSE=false

show_usage() {
  echo "Usage: $(basename "$0") [options]"
  echo
  echo "Options:"
  echo "  -i, --input <gene|file>  Gene name/ID or file with gene names (required)"
  echo "  -r, --reference <file>   Path to reference genome FASTA (required)"
  echo "  -u, --upstream <bp>      Distance upstream of TSS (default: $UPSTREAM_DISTANCE)"
  echo "  -d, --downstream <bp>    Distance downstream of TSS (default: $DOWNSTREAM_DISTANCE)"
  echo "  -o, --output <file>      Output file (default: stdout)"
  echo "  -v, --verbose            Show detailed progress"
  echo "  -h, --help               Show this help message"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input)
      INPUT="$2"
      shift 2
      ;;
    -r|--reference)
      REFERENCE="$2"
      shift 2
      ;;
    -u|--upstream)
      UPSTREAM_DISTANCE="$2"
      shift 2
      ;;
    -d|--downstream)
      DOWNSTREAM_DISTANCE="$2"
      shift 2
      ;;
    -o|--output)
      OUTPUT="$2"
      shift 2
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
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

# Function to print verbose messages
verbose() {
  if [ "$VERBOSE" = true ]; then
    echo "[INFO] $1"
  fi
}

# Validate required arguments
if [ -z "$INPUT" ]; then
  echo "Error: Input gene or file is required (-i, --input)"
  show_usage
  exit 1
fi

if [ -z "$REFERENCE" ]; then
  echo "Error: Reference genome is required (-r, --reference)"
  show_usage
  exit 1
fi

# Check if reference genome exists
if [ ! -f "$REFERENCE" ]; then
  echo "Error: Reference genome file not found: $REFERENCE"
  exit 1
fi

# # Create output directory if it doesn't exist
OUTPUT_DIR=$(dirname "$OUTPUT")
if [ ! -d "$OUTPUT_DIR" ]; then
  verbose "Creating output directory: $OUTPUT_DIR"
  mkdir -p "$OUTPUT_DIR" || { echo "Error: Failed to create output directory: $OUTPUT_DIR"; exit 1; }
fi

# Determine if input is a file or gene name
if [ -f "$INPUT" ]; then
  verbose "Input is a file: $INPUT"
  INPUT_TYPE="file"
else
  verbose "Input is a gene name: $INPUT"
  INPUT_TYPE="gene"
fi

# Process gene input and determine type (ENSEMBL ID or gene symbol)
genes=()
gene_types=()

if [ "$INPUT_TYPE" = "file" ]; then
  # Read genes from file, one per line
  verbose "Reading genes from file: $INPUT"
  
  # Check if file exists and is readable
  if [ ! -r "$INPUT" ]; then
    echo "Error: Cannot read input file: $INPUT"
    exit 1
  fi
  
  # Read file line by line
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    if [ -n "$line" ] && [[ ! "$line" =~ ^# ]]; then
      # Trim whitespace
      gene=$(echo "$line" | tr -d '[:space:]')
      if [ -n "$gene" ]; then
        genes+=("$gene")
        
        # Determine gene type (ENSEMBL ID or gene symbol)
        if [[ "$gene" =~ ^ENSG[0-9]+ ]]; then
          gene_types+=("ensembl")
          verbose "  - $gene (ENSEMBL ID)"
        else
          gene_types+=("symbol")
          verbose "  - $gene (gene symbol)"
        fi
      fi
    fi
  done < "$INPUT"
  
  # Check if we got any genes
  if [ ${#genes[@]} -eq 0 ]; then
    echo "Error: No valid genes found in file: $INPUT"
    exit 1
  fi
  
  verbose "Found ${#genes[@]} genes in input file"
  
else
  # Single gene input
  genes+=("$INPUT")
  
  # Determine gene type (ENSEMBL ID or gene symbol)
  if [[ "$INPUT" =~ ^ENSG[0-9]+ ]]; then
    gene_types+=("ensembl")
    verbose "Processing single gene: $INPUT (ENSEMBL ID)"
  else
    gene_types+=("symbol")
    verbose "Processing single gene: $INPUT (gene symbol)"
  fi
fi

# Display genes if in verbose mode
if [ "$VERBOSE" = true ] && [ ${#genes[@]} -le 10 ]; then
  echo "Genes to process:"
  for i in "${!genes[@]}"; do
    echo "  - ${genes[$i]} (${gene_types[$i]})"
  done
elif [ "$VERBOSE" = true ]; then
  echo "Processing ${#genes[@]} genes (first 5 shown):"
  for i in {0..4}; do
    if [ $i -lt ${#genes[@]} ]; then
      echo "  - ${genes[$i]} (${gene_types[$i]})"
    fi
  done
  echo "  - ... and $((${#genes[@]} - 5)) more"
fi

# TSS lookup from annotation file
TSS_FILE="$REPO_DIR/data/reference/gene_annotations/gencode.v48.annotation.TSS.tsv"
verbose "Using TSS annotation file: $TSS_FILE"

# Create temporary files
TMP_DIR=$(mktemp -d)
TMP_BED="$TMP_DIR/regions.bed"
verbose "Created temporary directory: $TMP_DIR"

# Initialize BED file
> "$TMP_BED"

# First, identify all duplicate gene names in the TSS file
verbose "Checking for duplicate gene names in annotation file..."
DUPLICATE_GENES=$(awk 'NR>1 {print $6}' "$TSS_FILE" | sort | uniq -d)

# Store duplicates for faster lookup
 if [ -n "$DUPLICATE_GENES" ]; then
  DUP_COUNT=$(echo "$DUPLICATE_GENES" | wc -l)
  verbose "Found $DUP_COUNT duplicate gene names in annotations"
fi
  

# Process each gene
for i in "${!genes[@]}"; do
  gene="${genes[$i]}"
  gene_type="${gene_types[$i]}"
  
  verbose "Looking up TSS for: $gene ($gene_type)"
  
  # Check for duplicate gene names if this is a gene symbol
  if [ "$gene_type" = "symbol" ] && echo "$DUPLICATE_GENES" | grep -q "^$gene$"; then 
    echo "Error: Ambiguous gene name: $gene"
    echo "This gene name is associated with multiple ENSEMBL IDs:"
    
    # Display all ENSEMBL IDs for this gene name
    awk -v gene="$gene" '$6 == gene {print "  - " $4 " (" $1 ":" $2 " " $3 " " $5 ")"}' "$TSS_FILE"
    
    echo "Please use a specific ENSEMBL ID instead to avoid ambiguity."
    continue
  fi
  
  # Perform lookup based on gene type
  if [ "$gene_type" = "ensembl" ]; then
    # Search by ENSEMBL ID (gene_id column)
    matches=$(awk -v gene="$gene" '$4 == gene' "$TSS_FILE")
  else
    # Search by gene symbol (gene_name column)
    matches=$(awk -v gene="$gene" '$6 == gene' "$TSS_FILE")
  fi
  
  # Count matches
  match_count=$(echo "$matches" | grep -c "^chr" || true)
  
  if [ "$match_count" -eq 0 ]; then
    echo "Warning: No TSS found for gene: $gene"
    continue
  elif [ "$match_count" -gt 1 ] && [ "$gene_type" = "ensembl" ]; then
    # This shouldn't happen with ENSEMBL IDs but handle just in case
    echo "Warning: Multiple TSS entries found for ENSEMBL ID: $gene"
    if [ "$VERBOSE" = true ]; then
      echo "$matches" | awk '{print "  - " $1 ":" $2 " (" $3 ") " $5 " [" $6 "]"}'
    fi
    echo "Using the first entry..."
    matches=$(echo "$matches" | head -n 1)
  fi
  
  # Extract TSS information
  chromosome=$(echo "$matches" | awk '{print $1}')
  tss_position=$(echo "$matches" | awk '{print $2}')
  strand=$(echo "$matches" | awk '{print $3}')
  annotation_gene_type=$(echo "$matches" | awk '{print $5}')
  
  verbose "Found TSS: $chromosome:$tss_position ($strand) $annotation_gene_type"
  
  # Calculate upstream region based on strand and distance
  if [ "$strand" = "+" ]; then
    # For positive strand
    start=$((tss_position - UPSTREAM_DISTANCE))
    end=$((tss_position + DOWNSTREAM_DISTANCE))
  
  # Handle edge case: start cannot be negative
    if [ $start -lt 0 ]; then
      verbose "Warning: Region extends beyond chromosome start, truncating"
      start=1
    fi
  else
    # For negative strand (reverse the directions)
    start=$((tss_position - DOWNSTREAM_DISTANCE))
    end=$((tss_position + UPSTREAM_DISTANCE))
  
    # Handle edge case: start cannot be negative
    if [ $start -lt 0 ]; then
      verbose "Warning: Region extends beyond chromosome start, truncating"
      start=1
    fi
  fi

  # Add to BED file
  echo -e "$chromosome\t$start\t$end\t$gene\t0\t$strand" >> "$TMP_BED"
  verbose "Added region: $chromosome:$start-$end (${UPSTREAM_DISTANCE}bp upstream, ${DOWNSTREAM_DISTANCE}bp downstream of TSS)"
done

# Check if we have any regions
if [ ! -s "$TMP_BED" ]; then
  echo "Error: No valid regions found for any of the input genes"
  rm -rf "$TMP_DIR"
  exit 1
fi

verbose "Created BED file with $(wc -l < "$TMP_BED") regions"

# Extract sequences using bedtools
verbose "Extracting sequences from reference genome: $REFERENCE"

# Check if bedtools is available
if ! command -v bedtools &> /dev/null; then
    echo "Error: bedtools is required but not found in PATH"
    echo "Please install bedtools: https://github.com/arq5x/bedtools2"
    rm -rf "$TMP_DIR"
    exit 1
fi

# Create temporary FASTA
TMP_FASTA="$TMP_DIR/sequences.fa"

# Extract sequences with bedtools getfasta
# -fi: reference genome
# -bed: our regions
# -fo: output file
# -s: force strandedness (reverse complement sequences on negative strand)
# -name: use the name field for the FASTA header
bedtools getfasta -fi "$REFERENCE" -bed "$TMP_BED" -fo "$TMP_FASTA" -s -name

# Check if extraction succeeded
if [ ! -s "$TMP_FASTA" ]; then
    echo "Error: Failed to extract sequences from reference genome"
    rm -rf "$TMP_DIR"
    exit 1
fi

# Count sequences
SEQ_COUNT=$(grep -c "^>" "$TMP_FASTA")
verbose "Extracted $SEQ_COUNT sequences"

# Write to output
verbose "Writing sequences to: $OUTPUT"
cat "$TMP_FASTA" > "$OUTPUT"

# Clean up temporary files
rm -rf "$TMP_DIR"
verbose "Cleaned up temporary files"

echo "Successfully extracted sequences for $SEQ_COUNT genes"
