#!/bin/bash

# select_guides.sh - Select guides with multiple mode support and optimization
# Supports tiling, CRISPRi, and CRISPRa guide selection with configurable scoring

# Default values
DEFAULT_OUTPUT="output/selected_guides.txt"
DEFAULT_ZONE_SIZE=50
DEFAULT_SCORE_METRIC="Hsu2013"
DEFAULT_HSU_CUTOFF=80
DEFAULT_DOENCH_CUTOFF=0.6
DEFAULT_TARGET_GUIDES=5

# Parse command line arguments
INPUT=""
OUTPUT="$DEFAULT_OUTPUT"
ZONE_SIZE="$DEFAULT_ZONE_SIZE"
SCORE_METRIC="$DEFAULT_SCORE_METRIC"
SCORE_CUTOFF=""
TARGET_GUIDES="$DEFAULT_TARGET_GUIDES"
RESTRICTION_ENZYMES=""
VERBOSE=false

# Mode flags
INCLUDE_TILING=false
INCLUDE_CRISPRI=false
INCLUDE_CRISPRA=false

# Help function
show_usage() {
  echo "Usage: $(basename "$0") -i <input_file> [selection_modes] [options]"
  echo
  echo "Select high-scoring guides with multiple mode support from FlashFry scored output."
  echo
  echo "Required:"
  echo "  -f, --input <file>       Input scored guides file from FlashFry"
  echo
  echo "Selection Modes (at least one required):"
  echo "  -t, --include-tiling     Select guides with optimal spacing across entire region"
  echo "  -i, --include-crispri    Select best guides for CRISPRi (-50 to +300bp from TSS)"
  echo "  -a, --include-crispra    Select best guides for CRISPRa (-400 to -50bp from TSS)"
  echo
  echo "Options:"
  echo "  -o, --output <file>      Output selected guides file (default: $DEFAULT_OUTPUT)"
  echo "  -n, --target-guides <N>  Target number of guides for CRISPRi/a modes (default: $DEFAULT_TARGET_GUIDES)"
  echo "  -m, --score-metric <metric>  Scoring metric to use (default: $DEFAULT_SCORE_METRIC)"
  echo "                           Options: Hsu2013, doench2016cfd"
  echo "  -c, --score-cutoff <score>   Minimum score threshold (default: auto-set based on metric)"
  echo "  -z, --zone-size <bp>     Exclusion zone radius for tiling mode (default: $DEFAULT_ZONE_SIZE)"
  echo "  -R, --restriction-enzymes <list>  Filter out guides with restriction sites (comma-separated)"
  echo "  -v, --verbose            Show detailed progress"
  echo "  -h, --help               Show this help message"
  echo
  echo "Default Score Cutoffs:"
  echo "  Hsu2013: $DEFAULT_HSU_CUTOFF"
  echo "  doench2016cfd: $DEFAULT_DOENCH_CUTOFF"
  echo
  echo "Note: CRISPRi/a modes are designed for genes with TSS information."
  echo "      Using with enhancers/arbitrary positions may not be optimal."
  echo
  echo "Examples:"
  echo "  # Tiling mode only"
  echo "  $(basename "$0") -f guides.scored.txt -t"
  echo
  echo "  # CRISPRi mode with custom target"
  echo "  $(basename "$0") -f guides.scored.txt -i -n 3"
  echo
  echo "  # All modes (short flags)"
  echo "  $(basename "$0") -f guides.scored.txt -t -i -a"
  echo
  echo "  # All modes with custom scoring"
  echo "  $(basename "$0") -f guides.scored.txt -t -i -a -m doench2016cfd -c 0.7"
  echo
  echo "  # Filter restriction enzymes"
  echo "  $(basename "$0") -f guides.scored.txt -t -R BsaI"
  echo "  $(basename "$0") -f guides.scored.txt -t -R BsaI,BsmBI,EcoRI"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--input) INPUT="$2"; shift 2 ;;
    -o|--output) OUTPUT="$2"; shift 2 ;;
    -n|--target-guides) TARGET_GUIDES="$2"; shift 2 ;;
    -m|--score-metric) SCORE_METRIC="$2"; shift 2 ;;
    -c|--score-cutoff) SCORE_CUTOFF="$2"; shift 2 ;;
    -z|--zone-size) ZONE_SIZE="$2"; shift 2 ;;
    -R|--restriction-enzymes) RESTRICTION_ENZYMES="$2"; shift 2 ;;
    -t|--include-tiling) INCLUDE_TILING=true; shift ;;
    -i|--include-crispri) INCLUDE_CRISPRI=true; shift ;;
    -a|--include-crispra) INCLUDE_CRISPRA=true; shift ;;
    -v|--verbose) VERBOSE=true; shift ;;
    -h|--help) show_usage; exit 0 ;;
    *) echo "Unknown option: $1"; show_usage; exit 1 ;;
  esac
done

# Function for verbose output
verbose() {
  if [ "$VERBOSE" = true ]; then
    echo "[INFO] $1"
  fi
}

# Validate required inputs
if [ -z "$INPUT" ]; then
  echo "Error: Input file is required (-f, --input)"
  show_usage
  exit 1
fi

if [ ! -f "$INPUT" ]; then
  echo "Error: Input file not found: $INPUT"
  exit 1
fi

# Check that at least one mode is selected
if [ "$INCLUDE_TILING" = false ] && [ "$INCLUDE_CRISPRI" = false ] && [ "$INCLUDE_CRISPRA" = false ]; then
  echo "Error: A selection mode must be specified."
  echo "Available modes:"
  echo "  -t, --include-tiling     Select guides with optimal spacing across entire region"
  echo "  -i, --include-crispri    Select best guides for CRISPRi (-50 to +300bp from TSS)"
  echo "  -a, --include-crispra    Select best guides for CRISPRa (-400 to -50bp from TSS)"
  echo
  echo "Use -n/--target-guides N to specify target number for CRISPRi/a modes."
  exit 1
fi

# Set default score cutoff if not provided
if [ -z "$SCORE_CUTOFF" ]; then
  case "$SCORE_METRIC" in
    Hsu2013) SCORE_CUTOFF="$DEFAULT_HSU_CUTOFF" ;;
    doench2016cfd) SCORE_CUTOFF="$DEFAULT_DOENCH_CUTOFF" ;;
    *) echo "Error: Unknown score metric: $SCORE_METRIC"; echo "Available: Hsu2013, doench2016cfd"; exit 1 ;;
  esac
fi

# Check bedtools availability
if ! command -v bedtools &> /dev/null; then
  echo "Error: bedtools is required but not found in PATH"
  exit 1
fi

# Set up paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FILTER_SCRIPT="$SCRIPT_DIR/lib/filter_restriction_sites.sh"

# Define output files
FULL_OUTPUT="$OUTPUT"
IGV_BED_OUTPUT="${OUTPUT%.*}.bed"

verbose "Configuration:"
verbose "  Input: $INPUT"
verbose "  Output: $FULL_OUTPUT"
verbose "  BED output: $IGV_BED_OUTPUT"
verbose "  Score metric: $SCORE_METRIC (cutoff: $SCORE_CUTOFF)"
verbose "  Modes: Tiling=$INCLUDE_TILING, CRISPRi=$INCLUDE_CRISPRI, CRISPRa=$INCLUDE_CRISPRA"
if [ "$INCLUDE_CRISPRI" = true ] || [ "$INCLUDE_CRISPRA" = true ]; then
  verbose "  Target guides for CRISPRi/a: $TARGET_GUIDES"
fi
if [ -n "$RESTRICTION_ENZYMES" ]; then
  verbose "  Restriction enzyme filtering: $RESTRICTION_ENZYMES"
fi

# Create temporary directory
TMP_DIR=$(mktemp -d)
verbose "Created temporary directory: $TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

# Step 1: Apply restriction enzyme filtering if requested
WORKING_INPUT="$INPUT"
if [ -n "$RESTRICTION_ENZYMES" ]; then
  verbose "Applying restriction enzyme filtering for: $RESTRICTION_ENZYMES"
  
  # Check if filter script exists
  if [ ! -f "$FILTER_SCRIPT" ]; then
    echo "Error: Restriction enzyme filter script not found: $FILTER_SCRIPT"
    exit 1
  fi
  
  # Apply filtering and save to temporary file
  FILTERED_INPUT="$TMP_DIR/filtered_guides.txt"
  if [ "$VERBOSE" = true ]; then
    "$FILTER_SCRIPT" "$INPUT" "$RESTRICTION_ENZYMES" --verbose > "$FILTERED_INPUT"
  else
    "$FILTER_SCRIPT" "$INPUT" "$RESTRICTION_ENZYMES" > "$FILTERED_INPUT" 2>/dev/null
  fi
  
  # Check if filtering was successful
  if [ $? -ne 0 ]; then
    echo "Error: Restriction enzyme filtering failed"
    exit 1
  fi
  
  # Use filtered input for rest of pipeline
  WORKING_INPUT="$FILTERED_INPUT"
  verbose "Restriction enzyme filtering complete"
fi

# Extract header and find column indices
HEADER=$(head -n 1 "$WORKING_INPUT")

# Find required columns
SCORE_COL=$(echo "$HEADER" | tr '\t' '\n' | grep -n "^${SCORE_METRIC}$" | cut -d: -f1)
DANGEROUS_GC_COL=$(echo "$HEADER" | tr '\t' '\n' | grep -n "^dangerous_GC" | cut -d: -f1)
DANGEROUS_POLYT_COL=$(echo "$HEADER" | tr '\t' '\n' | grep -n "^dangerous_polyT" | cut -d: -f1)
DANGEROUS_GENOME_COL=$(echo "$HEADER" | tr '\t' '\n' | grep -n "^dangerous_in_genome" | cut -d: -f1)
ORIENTATION_COL=$(echo "$HEADER" | tr '\t' '\n' | grep -n "^orientation" | cut -d: -f1)

if [ -z "$SCORE_COL" ]; then
  echo "Error: Score metric '$SCORE_METRIC' not found in input file"
  echo "Available columns:"
  echo "$HEADER" | tr '\t' '\n' | grep -E "(hsu|doench)" | head -5
  exit 1
fi

verbose "Column indices: Score=$SCORE_COL, GC=$DANGEROUS_GC_COL, polyT=$DANGEROUS_POLYT_COL, in_genome=$DANGEROUS_GENOME_COL"

# Process input file and extract guide information
verbose "Processing FlashFry output..."

awk -F'\t' -v score_col="$SCORE_COL" -v gc_col="$DANGEROUS_GC_COL" -v polyt_col="$DANGEROUS_POLYT_COL" \
    -v genome_col="$DANGEROUS_GENOME_COL" -v orientation_col="$ORIENTATION_COL" -v score_cutoff="$SCORE_CUTOFF" '
  BEGIN {OFS="\t"}
  
  NR > 1 && $gc_col == "NONE" && $polyt_col == "NONE" && $genome_col ~ /IN_GENOME=1/ && $score_col >= score_cutoff {
    # Parse header to extract target name, genomic coordinates, and TSS
    split($1, contig_parts, "::");
    target_name = contig_parts[1];
    region_info = contig_parts[2];
    tss_info = contig_parts[3];
    
    # Extract genomic region coordinates
    split(region_info, region_parts, ":");
    chr = region_parts[1];
    split(region_parts[2], pos_parts, "-");
    region_start = pos_parts[1] + 0;
    region_end = pos_parts[2] + 0;
    
    # Extract strand from region_info (format: chr:start-end(strand))
    if (region_info ~ /[(][+][)]/) {
      region_strand = "+";
    } else {
      region_strand = "-";
    }
    
    # Extract TSS position
    if (tss_info && tss_info ~ /TSS_[^:]+:[0-9]+/) {
      # Extract the number after the colon in TSS_chrX:position format
      split(tss_info, tss_parts, ":");
      tss_pos = tss_parts[2] + 0;
    } else {
      # Fallback: assume position input where position = TSS
      tss_pos = region_start;
    }
    
    # Calculate absolute genomic coordinates for this guide
    rel_start = $2 + 0;
    rel_end = $3 + 0;
    abs_start = region_start + rel_start;
    abs_end = region_start + rel_end;
    
    # Get guide orientation
    orientation = $orientation_col;
    
    # Calculate TSS-relative position (use guide start for positioning)
    tss_relative_pos = abs_start - tss_pos;
    
    # Create unique guide ID using absolute coordinates
    guide_id = target_name "_" chr "_" abs_start "_" region_strand "_" orientation;
    
    # Output guide information
    print guide_id, target_name, chr, abs_start, abs_end, region_strand, orientation, $score_col, tss_relative_pos, rel_start, rel_end, $0;
  }
' "$WORKING_INPUT" > "$TMP_DIR/processed_guides.txt"

# Check if any guides passed filtering
if [ ! -s "$TMP_DIR/processed_guides.txt" ]; then
  echo "Error: No guides found matching the filtering criteria (score >= $SCORE_CUTOFF)"
  exit 1
fi

TOTAL_GUIDES=$(wc -l < "$TMP_DIR/processed_guides.txt")
verbose "Found $TOTAL_GUIDES guides passing filters"

# Get list of unique targets
awk '{print $2}' "$TMP_DIR/processed_guides.txt" | sort | uniq > "$TMP_DIR/target_names.txt"
TARGET_COUNT=$(wc -l < "$TMP_DIR/target_names.txt")
verbose "Processing $TARGET_COUNT unique targets"

# Initialize results files
> "$TMP_DIR/selected_guides.txt"

# Process each target
while read -r TARGET; do
  verbose "Processing target: $TARGET"
  
  # Extract guides for this target
  awk -v target="$TARGET" '$2 == target' "$TMP_DIR/processed_guides.txt" > "$TMP_DIR/${TARGET}_guides.txt"
  
  TARGET_GUIDE_COUNT=$(wc -l < "$TMP_DIR/${TARGET}_guides.txt")
  verbose "  Found $TARGET_GUIDE_COUNT guides for $TARGET"
  
  if [ "$TARGET_GUIDE_COUNT" -eq 0 ]; then
    continue
  fi
  
  # Initialize mode results for this target
  > "$TMP_DIR/${TARGET}_tiling.txt"
  > "$TMP_DIR/${TARGET}_crispri.txt"
  > "$TMP_DIR/${TARGET}_crispra.txt"
  
  # TILING MODE SELECTION
  if [ "$INCLUDE_TILING" = true ]; then
    verbose "  Running tiling selection..."
    
    # Sort by score (descending) for tiling
    sort -k8,8nr "$TMP_DIR/${TARGET}_guides.txt" > "$TMP_DIR/${TARGET}_sorted.txt"
    
    # Tiling selection with exclusion zones
    > "$TMP_DIR/${TARGET}_exclusions.bed"
    
    while read -r GUIDE; do
      GUIDE_CHR=$(echo "$GUIDE" | cut -f3)
      GUIDE_START=$(echo "$GUIDE" | cut -f4)
      GUIDE_END=$(echo "$GUIDE" | cut -f5)
      GUIDE_ID=$(echo "$GUIDE" | cut -f1)
      
      # Check overlap with existing exclusion zones
      if [ -s "$TMP_DIR/${TARGET}_exclusions.bed" ]; then
        OVERLAP=$(echo -e "${GUIDE_CHR}\t${GUIDE_START}\t${GUIDE_END}" | \
                 bedtools intersect -a stdin -b "$TMP_DIR/${TARGET}_exclusions.bed" -u | wc -l)
      else
        OVERLAP=0
      fi
      
      if [ "$OVERLAP" -eq 0 ]; then
        # No overlap - select this guide for tiling
        echo "$GUIDE" >> "$TMP_DIR/${TARGET}_tiling.txt"
        
        # Add exclusion zone
        EXCL_START=$((GUIDE_START - ZONE_SIZE))
        EXCL_END=$((GUIDE_END + ZONE_SIZE))
        if [ "$EXCL_START" -lt 0 ]; then EXCL_START=0; fi
        echo -e "${GUIDE_CHR}\t${EXCL_START}\t${EXCL_END}" >> "$TMP_DIR/${TARGET}_exclusions.bed"
      fi
    done < "$TMP_DIR/${TARGET}_sorted.txt"
    
    TILING_COUNT=$(wc -l < "$TMP_DIR/${TARGET}_tiling.txt")
    verbose "    Selected $TILING_COUNT guides for tiling"
  fi
  
  # CRISPRI MODE SELECTION
  if [ "$INCLUDE_CRISPRI" = true ]; then
    verbose "  Running CRISPRi selection..."
    
    # Filter guides in CRISPRi window (-50 to +300 from TSS)
    awk '$9 >= -50 && $9 <= 300' "$TMP_DIR/${TARGET}_guides.txt" | \
    sort -k8,8nr | \
    head -n "$TARGET_GUIDES" > "$TMP_DIR/${TARGET}_crispri.txt"
    
    CRISPRI_COUNT=$(wc -l < "$TMP_DIR/${TARGET}_crispri.txt")
    verbose "    Selected $CRISPRI_COUNT guides for CRISPRi"
  fi
  
  # CRISPRA MODE SELECTION  
  if [ "$INCLUDE_CRISPRA" = true ]; then
    verbose "  Running CRISPRa selection..."
    
    # Filter guides in CRISPRa window (-400 to -50 from TSS)
    awk '$9 >= -400 && $9 <= -50' "$TMP_DIR/${TARGET}_guides.txt" | \
    sort -k8,8nr | \
    head -n "$TARGET_GUIDES" > "$TMP_DIR/${TARGET}_crispra.txt"
    
    CRISPRA_COUNT=$(wc -l < "$TMP_DIR/${TARGET}_crispra.txt")
    verbose "    Selected $CRISPRA_COUNT guides for CRISPRa"
  fi
  
  # Merge results and add boolean flags
  cat "$TMP_DIR/${TARGET}_tiling.txt" "$TMP_DIR/${TARGET}_crispri.txt" "$TMP_DIR/${TARGET}_crispra.txt" | \
  sort | uniq | \
  while read -r GUIDE; do
    if [ -n "$GUIDE" ]; then
      GUIDE_ID=$(echo "$GUIDE" | cut -f1)
      
      # Check which modes this guide was selected for
      TILING_FLAG="FALSE"
      CRISPRI_FLAG="FALSE"
      CRISPRA_FLAG="FALSE"
      
      if grep -q "^$GUIDE_ID" "$TMP_DIR/${TARGET}_tiling.txt" 2>/dev/null; then
        TILING_FLAG="TRUE"
      fi
      if grep -q "^$GUIDE_ID" "$TMP_DIR/${TARGET}_crispri.txt" 2>/dev/null; then
        CRISPRI_FLAG="TRUE"
      fi
      if grep -q "^$GUIDE_ID" "$TMP_DIR/${TARGET}_crispra.txt" 2>/dev/null; then
        CRISPRA_FLAG="TRUE"
      fi
      
      # Output with boolean flags
      echo "$GUIDE" | awk -v tiling="$TILING_FLAG" -v crispri="$CRISPRI_FLAG" -v crispra="$CRISPRA_FLAG" \
        '{print $0 "\t" tiling "\t" crispri "\t" crispra}'
    fi
  done >> "$TMP_DIR/selected_guides.txt"
  
done < "$TMP_DIR/target_names.txt"

# Check if any guides were selected
if [ ! -s "$TMP_DIR/selected_guides.txt" ]; then
  echo "Error: No guides were selected with the current criteria"
  exit 1
fi

# Create final output files
verbose "Creating output files..."

# Create header for full output (add guide_id as first column, keep original header)
ORIGINAL_HEADER=$(head -n 1 "$WORKING_INPUT")
echo -e "guide_id\t${ORIGINAL_HEADER}\ttiling_guide\tcrispri_guide\tcrispra_guide" > "$FULL_OUTPUT"

# Add selected guides to output (add guide_id as first column, keep all original FlashFry data + boolean flags)
awk '{
  # Add guide_id as first column, then all original FlashFry data, then boolean flags
  guide_id = $1;
  original_data = "";
  for (i=12; i<=NF-3; i++) {
    if (i > 12) original_data = original_data "\t";
    original_data = original_data $i;
  }
  print guide_id "\t" original_data "\t" $(NF-2) "\t" $(NF-1) "\t" $NF;
}' "$TMP_DIR/selected_guides.txt" >> "$FULL_OUTPUT"

# Create BED file for IGV
awk '{print $3 "\t" $4 "\t" $5 "\t" $1 "\t" $8 "\t" $6}' "$TMP_DIR/selected_guides.txt" | \
sort -k1,1 -k2,2n > "$IGV_BED_OUTPUT"

# Generate summary
TOTAL_SELECTED=$(wc -l < "$TMP_DIR/selected_guides.txt")
TILING_SELECTED=$(awk '$(NF-2) == "TRUE"' "$TMP_DIR/selected_guides.txt" | wc -l)
CRISPRI_SELECTED=$(awk '$(NF-1) == "TRUE"' "$TMP_DIR/selected_guides.txt" | wc -l)
CRISPRA_SELECTED=$(awk '$NF == "TRUE"' "$TMP_DIR/selected_guides.txt" | wc -l)

echo "Guide selection complete!"
echo "Selected $TOTAL_SELECTED unique guides across $TARGET_COUNT targets"
echo "Mode breakdown:"
echo "  Tiling: $TILING_SELECTED guides"
echo "  CRISPRi: $CRISPRI_SELECTED guides" 
echo "  CRISPRa: $CRISPRA_SELECTED guides"
echo "Output files:"
echo "  Full data: $FULL_OUTPUT"
echo "  BED format: $IGV_BED_OUTPUT"

exit 0
