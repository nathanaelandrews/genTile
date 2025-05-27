#!/bin/bash

# Get sequence upstream of TSS for gene(s) or specified positions
# 
# Usage: get_sequence.sh (-g <genes> | -p <positions>) -r <genome> (-c <cell_line> | -G) [options]

# Determine script location regardless of where it's called from
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( dirname "$SCRIPT_DIR" )"

# Default values
UPSTREAM_DISTANCE=1500   # Default bp upstream of TSS
DOWNSTREAM_DISTANCE=500  # Default bp downstream of TSS
OUTPUT="output/sequences.fa" # Default output
VERBOSE=false

show_usage() {
  echo "Usage: $(basename "$0") (-g <genes> | -p <positions>) -r <genome> (-c <cell_line> | -G) [options]"
  echo
  echo "Extract genomic sequences around TSS using CAGE data or Gencode annotations."
  echo
  echo "Input Options (choose one):"
  echo "  -g, --genes <file>       Gene names/IDs file (one gene per line)"
  echo "  -p, --positions <file>   Position file (format: name,chr:pos,strand)"
  echo
  echo "TSS Source Options (required for gene mode):"
  echo "  -c, --cell-line <name>   Use CAGE data for specified cell line"
  echo "  -G, --gencode-only       Force use of Gencode TSS (not recommended)"
  echo
  echo "Required Options:"
  echo "  -r, --reference <file>   Path to reference genome FASTA"
  echo
  echo "Sequence Options:"
  echo "  -u, --upstream <bp>      Distance upstream of TSS (default: $UPSTREAM_DISTANCE)"
  echo "  -d, --downstream <bp>    Distance downstream of TSS (default: $DOWNSTREAM_DISTANCE)"
  echo "  -o, --output <file>      Output file (default: $OUTPUT)"
  echo "  -v, --verbose            Show detailed progress"
  echo "  -h, --help               Show this help message"
  echo
  echo "Examples:"
  echo "  # Use CAGE data for K562 cell line"
  echo "  $(basename "$0") -g genes.txt -r hg38.fa -c K562"
  echo
  echo "  # Use Gencode TSS (not recommended)"
  echo "  $(basename "$0") -g genes.txt -r hg38.fa -G"
  echo
  echo "  # Use custom positions"
  echo "  $(basename "$0") -p positions.txt -r hg38.fa"
  echo
  echo "Position file format:"
  echo "  enhancer1,chr8:127736230,+"
  echo "  promoter2,chr17:7687546,-"
}

# Parse command line arguments
GENES_FILE=""
POSITIONS_FILE=""
REFERENCE=""
CELL_LINE=""
GENCODE_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--genes)
      GENES_FILE="$2"
      shift 2
      ;;
    -p|--positions)
      POSITIONS_FILE="$2"
      shift 2
      ;;
    -r|--reference)
      REFERENCE="$2"
      shift 2
      ;;
    -c|--cell-line)
      CELL_LINE="$2"
      shift 2
      ;;
    -G|--gencode-only)
      GENCODE_ONLY=true
      shift
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
if [ -z "$GENES_FILE" ] && [ -z "$POSITIONS_FILE" ]; then
  echo "Error: Either genes file (-g) or positions file (-p) is required"
  show_usage
  exit 1
fi

if [ -n "$GENES_FILE" ] && [ -n "$POSITIONS_FILE" ]; then
  echo "Error: Cannot use both genes file (-g) and positions file (-p) at the same time"
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

# Validate TSS source for gene mode
if [ -n "$GENES_FILE" ]; then
  if [ -z "$CELL_LINE" ] && [ "$GENCODE_ONLY" != true ]; then
    echo "Error: For gene mode, you must specify either:"
    echo "  -c <cell_line>  (recommended: use CAGE data)"
    echo "  -G              (use Gencode TSS, not recommended)"
    show_usage
    exit 1
  fi
  
  if [ -n "$CELL_LINE" ] && [ "$GENCODE_ONLY" = true ]; then
    echo "Error: Cannot use both -c (cell line) and -G (gencode-only) options"
    show_usage
    exit 1
  fi
fi

# Validate that positions mode doesn't use TSS source options
if [ -n "$POSITIONS_FILE" ]; then
  if [ -n "$CELL_LINE" ]; then
    echo "Error: Position mode (-p) does not use cell line option (-c)"
    show_usage
    exit 1
  fi
  
  if [ "$GENCODE_ONLY" = true ]; then
    echo "Error: Position mode (-p) does not use gencode-only option (-G)"
    show_usage
    exit 1
  fi
fi

# Check if input file exists
INPUT_FILE=""
if [ -n "$GENES_FILE" ]; then
  INPUT_FILE="$GENES_FILE"
  INPUT_TYPE="genes"
else
  INPUT_FILE="$POSITIONS_FILE"
  INPUT_TYPE="positions"
fi

if [ ! -f "$INPUT_FILE" ]; then
  echo "Error: Input file not found: $INPUT_FILE"
  exit 1
fi

# Validate cell line if provided
if [ -n "$CELL_LINE" ]; then
  verbose "Validating cell line: $CELL_LINE"
  if ! "$REPO_DIR/bin/lib/fetch_CAGE_data.sh" "$CELL_LINE" >/dev/null 2>&1; then
    echo "Error: Invalid cell line or failed to fetch CAGE data: $CELL_LINE"
    exit 1
  fi
  verbose "Cell line validation successful"
fi

# Show warning for Gencode-only mode
if [ "$GENCODE_ONLY" = true ]; then
  echo "Warning: Using Gencode TSS instead of CAGE data is not recommended." >&2
  echo "         CAGE data provides more accurate cell-type-specific TSS positions." >&2
fi

# Create output directory if it doesn't exist
OUTPUT_DIR=$(dirname "$OUTPUT")
if [ ! -d "$OUTPUT_DIR" ]; then
  verbose "Creating output directory: $OUTPUT_DIR"
  mkdir -p "$OUTPUT_DIR" || { echo "Error: Failed to create output directory: $OUTPUT_DIR"; exit 1; }
fi

# Set paths for TSS lookup
TSS_FILE="$REPO_DIR/data/reference/gene_annotations/gencode.v47.annotation.tsv"
GET_TSS_SCRIPT="$REPO_DIR/bin/lib/get_TSS.sh"

# Create temporary files
TMP_DIR=$(mktemp -d)
TMP_BED="$TMP_DIR/regions.bed"
verbose "Created temporary directory: $TMP_DIR"

# Initialize BED file and output
> "$TMP_BED"
> "$OUTPUT"

# Add output header with mode information
if [ "$INPUT_TYPE" = "genes" ]; then
  if [ -n "$CELL_LINE" ]; then
    echo "# Sequences extracted using CAGE data from cell line: $CELL_LINE" >> "$OUTPUT"
  else
    echo "# Sequences extracted using Gencode TSS annotations" >> "$OUTPUT"
  fi
else
  echo "# Sequences extracted from custom positions" >> "$OUTPUT"
fi
echo "# Upstream distance: ${UPSTREAM_DISTANCE}bp, Downstream distance: ${DOWNSTREAM_DISTANCE}bp" >> "$OUTPUT"
echo "# Generated on: $(date)" >> "$OUTPUT"

# Process input based on type
if [ "$INPUT_TYPE" = "genes" ]; then
  verbose "Processing genes file: $INPUT_FILE"
  
  # Read genes and process each one
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    if [ -z "$line" ] || [[ "$line" =~ ^# ]]; then
      continue
    fi
    
    # Trim whitespace
    gene=$(echo "$line" | tr -d '[:space:]')
    if [ -z "$gene" ]; then
      continue
    fi
    
    verbose "Processing gene: $gene"
    
    # Get TSS coordinates
    if [ -n "$CELL_LINE" ]; then
      # Use CAGE data
      TSS_COORDS=$("$GET_TSS_SCRIPT" "$gene" "$CELL_LINE" 2>/dev/null)
    else
      # Use Gencode TSS (fallback mode)
      verbose "Looking up Gencode TSS for: $gene"
      
      # First check for duplicates if this is a gene symbol
      if [[ ! "$gene" =~ ^ENSG[0-9]+ ]]; then
        # This is a gene symbol, check for duplicates
        DUPLICATE_COUNT=$(awk -F'\t' -v gene="$gene" 'NR > 1 && $8 == gene' "$TSS_FILE" | wc -l)
        if [ "$DUPLICATE_COUNT" -gt 1 ]; then
          echo "Error: Ambiguous gene name: $gene" >&2
          echo "This gene name is associated with multiple ENSEMBL IDs:" >&2
          awk -F'\t' -v gene="$gene" 'NR > 1 && $8 == gene {print "  - " $6 " (" $1 ":" $2 " " $5 " " $7 ")"}' "$TSS_FILE" >&2
          echo "Please use a specific ENSEMBL ID instead to avoid ambiguity." >&2
          continue
        fi
      fi
      
      # Perform lookup based on gene type
      if [[ "$gene" =~ ^ENSG[0-9]+ ]]; then
        # Search by ENSEMBL ID (gene_id column)
        TSS_LOOKUP=$(awk -F'\t' -v gene="$gene" 'NR > 1 && $6 == gene {print $1 ":" $2 ":" $5; exit}' "$TSS_FILE")
      else
        # Search by gene symbol (gene_name column)
        TSS_LOOKUP=$(awk -F'\t' -v gene="$gene" 'NR > 1 && $8 == gene {print $1 ":" $2 ":" $5; exit}' "$TSS_FILE")
      fi
      
      if [ -n "$TSS_LOOKUP" ]; then
        TSS_COORDS="$TSS_LOOKUP"
      else
        echo "Warning: Gene not found: $gene" >&2
        continue
      fi
    fi
    
    if [ -z "$TSS_COORDS" ]; then
      echo "Warning: Failed to get TSS coordinates for: $gene" >&2
      continue
    fi
    
    # Parse TSS coordinates (format: chr:position:strand)
    chromosome=$(echo "$TSS_COORDS" | cut -d: -f1)
    tss_position=$(echo "$TSS_COORDS" | cut -d: -f2)
    strand=$(echo "$TSS_COORDS" | cut -d: -f3)
    
    if [ -z "$chromosome" ] || [ -z "$tss_position" ] || [ -z "$strand" ]; then
      echo "Warning: Invalid TSS coordinates for $gene: $TSS_COORDS" >&2
      continue
    fi
    
    verbose "Found TSS: $chromosome:$tss_position ($strand)"
    
    # Calculate region based on strand and distances
    if [ "$strand" = "+" ]; then
      # For positive strand
      start=$((tss_position - UPSTREAM_DISTANCE))
      end=$((tss_position + DOWNSTREAM_DISTANCE))
    else
      # For negative strand (reverse the directions)
      start=$((tss_position - DOWNSTREAM_DISTANCE))
      end=$((tss_position + UPSTREAM_DISTANCE))
    fi
    
    # Handle edge case: start cannot be negative
    if [ $start -lt 1 ]; then
      verbose "Warning: Region extends beyond chromosome start, truncating"
      start=1
    fi
    
    # Add to BED file with TSS information in the name
    echo -e "$chromosome\t$start\t$end\t$gene\t0\t$strand\t$tss_position" >> "$TMP_BED"
    verbose "Added region: $chromosome:$start-$end (TSS at $tss_position, strand $strand)"
    
  done < "$INPUT_FILE"
  
else
  verbose "Processing positions file: $INPUT_FILE"
  
  # Process positions file (format: name,chr:pos,strand)
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    if [ -z "$line" ] || [[ "$line" =~ ^# ]]; then
      continue
    fi
    
    # Parse comma-separated values
    if [[ "$line" =~ ^([^,]+),([^:]+):([0-9]+),([+-])$ ]]; then
      name="${BASH_REMATCH[1]}"
      chromosome="${BASH_REMATCH[2]}"
      position="${BASH_REMATCH[3]}"
      strand="${BASH_REMATCH[4]}"
    else
      echo "Warning: Invalid position format: $line" >&2
      echo "Expected format: name,chr:position,strand" >&2
      continue
    fi
    
    verbose "Processing position: $name at $chromosome:$position ($strand)"
    
    # Calculate region based on strand and distances
    if [ "$strand" = "+" ]; then
      start=$((position - UPSTREAM_DISTANCE))
      end=$((position + DOWNSTREAM_DISTANCE))
    else
      start=$((position - DOWNSTREAM_DISTANCE))
      end=$((position + UPSTREAM_DISTANCE))
    fi
    
    # Handle edge case: start cannot be negative
    if [ $start -lt 1 ]; then
      verbose "Warning: Region extends beyond chromosome start, truncating"
      start=1
    fi
    
    # Add to BED file with position information
    echo -e "$chromosome\t$start\t$end\t$name\t0\t$strand\t$position" >> "$TMP_BED"
    verbose "Added region: $chromosome:$start-$end (position at $position, strand $strand)"
    
  done < "$INPUT_FILE"
fi

# Check if we have any regions
if [ ! -s "$TMP_BED" ]; then
  echo "Error: No valid regions found for any of the input entries"
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
bedtools getfasta -fi "$REFERENCE" -bed "$TMP_BED" -fo "$TMP_FASTA" -s -name

# Check if extraction succeeded
if [ ! -s "$TMP_FASTA" ]; then
    echo "Error: Failed to extract sequences from reference genome"
    rm -rf "$TMP_DIR"
    exit 1
fi

# Process FASTA to add TSS information to headers
while IFS= read -r line; do
  if [[ "$line" =~ ^\> ]]; then
    # Parse header - bedtools creates headers like ">name" or ">name::(+)" 
    header_name=$(echo "$line" | sed 's/^>//' | sed 's/::.*$//')
    
    verbose "Processing header for: $header_name"
    
    # Find corresponding BED entry to get TSS position
    bed_entry=$(awk -F'\t' -v name="$header_name" '$4 == name {print; exit}' "$TMP_BED")
    
    if [ -n "$bed_entry" ]; then
      chromosome=$(echo "$bed_entry" | cut -f1)
      start=$(echo "$bed_entry" | cut -f2)
      end=$(echo "$bed_entry" | cut -f3)
      strand=$(echo "$bed_entry" | cut -f6)
      tss_pos=$(echo "$bed_entry" | cut -f7)
      
      # Create enhanced header with TSS information
      echo ">${header_name}::${chromosome}:${start}-${end}(${strand})::TSS_${chromosome}:${tss_pos}" >> "$OUTPUT"
      verbose "Enhanced header for $header_name"
    else
      # Fallback to original header if BED lookup fails
      echo "$line" >> "$OUTPUT"
      verbose "Warning: Could not enhance header for $header_name, using original"
    fi
  else
    # Copy sequence line as-is
    echo "$line" >> "$OUTPUT"
  fi
done < "$TMP_FASTA"

# Count sequences
#SEQ_COUNT=$(grep -c "^>" "$OUTPUT" | tail -n +4)  # Skip header comments
SEQ_COUNT=$(grep -c "^>" "$OUTPUT")
verbose "Extracted $SEQ_COUNT sequences"

# Clean up temporary files
rm -rf "$TMP_DIR"
verbose "Cleaned up temporary files"

echo "Successfully extracted sequences for $SEQ_COUNT entries"
verbose "Output written to: $OUTPUT"
