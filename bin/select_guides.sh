#!/bin/bash

# select_guides.sh - Select optimally-spaced guides from FlashFry output
# This script uses bedtools to select guides with optimal spacing

# Default values
DEFAULT_OUTPUT="output/selected_guides.txt"
DEFAULT_ZONE_SIZE=50
DEFAULT_MIN_SCORE=60

# Parse command line arguments
INPUT=""
OUTPUT="$DEFAULT_OUTPUT"
ZONE_SIZE="$DEFAULT_ZONE_SIZE"
MIN_SCORE="$DEFAULT_MIN_SCORE"
VERBOSE=false

# Help function
show_usage() {
  echo "Usage: $(basename "$0") -i <input_file> [options]"
  echo
  echo "Select high-scoring guides with optimal spacing from FlashFry scored output."
  echo
  echo "Options:"
  echo "  -i, --input <file>       Input scored guides file (required)"
  echo "  -o, --output <file>      Output selected guides file (default: $DEFAULT_OUTPUT)"
  echo "  -z, --zone-size <bp>     Exclusion zone radius around each guide (default: $DEFAULT_ZONE_SIZE)"
  echo "  -m, --min-score <score>  Minimum acceptable Hsu score (default: $DEFAULT_MIN_SCORE)"
  echo "  -v, --verbose            Show detailed progress"
  echo "  -h, --help               Show this help message"
  echo
  echo "Example:"
  echo "  $(basename "$0") -i guides.scored.txt -o guides.selected.txt -z 50"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input) INPUT="$2"; shift 2 ;;
    -o|--output) OUTPUT="$2"; shift 2 ;;
    -z|--zone-size) ZONE_SIZE="$2"; shift 2 ;;
    -m|--min-score) MIN_SCORE="$2"; shift 2 ;;
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

# Check required inputs
if [ -z "$INPUT" ]; then
  echo "Error: Input file is required (-i, --input)"
  show_usage
  exit 1
fi

if [ ! -f "$INPUT" ]; then
  echo "Error: Input file not found: $INPUT"
  exit 1
fi

if ! command -v bedtools &> /dev/null; then
  echo "Error: bedtools is required but not found in PATH"
  exit 1
fi

# Define output files
FULL_OUTPUT="$OUTPUT"
IGV_BED_OUTPUT="${OUTPUT%.*}.bed"

verbose "Will generate two output files:"
verbose "  Full data: $FULL_OUTPUT"
verbose "  BED format for IGV: $IGV_BED_OUTPUT"

# Create temporary directory
TMP_DIR=$(mktemp -d)
verbose "Created temporary directory: $TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

# Extract header
HEADER=$(head -n 1 "$INPUT")

# Find column indices
HSU_COL=$(echo "$HEADER" | tr '\t' '\n' | grep -n "^Hsu2013" | cut -d: -f1)
DANGEROUS_GC_COL=$(echo "$HEADER" | tr '\t' '\n' | grep -n "^dangerous_GC" | cut -d: -f1)
DANGEROUS_POLYT_COL=$(echo "$HEADER" | tr '\t' '\n' | grep -n "^dangerous_polyT" | cut -d: -f1)
DANGEROUS_GENOME_COL=$(echo "$HEADER" | tr '\t' '\n' | grep -n "^dangerous_in_genome" | cut -d: -f1)
ORIENTATION_COL=$(echo "$HEADER" | tr '\t' '\n' | grep -n "^orientation" | cut -d: -f1)

verbose "Column indices: Hsu=$HSU_COL, GC=$DANGEROUS_GC_COL, polyT=$DANGEROUS_POLYT_COL, in_genome=$DANGEROUS_GENOME_COL"

# Process input file and create working files
awk -F'\t' -v hsu_col="$HSU_COL" -v gc_col="$DANGEROUS_GC_COL" -v polyt_col="$DANGEROUS_POLYT_COL" -v genome_col="$DANGEROUS_GENOME_COL" -v orientation_col="$ORIENTATION_COL" '
  BEGIN {OFS="\t"}
  
  NR > 1 && $gc_col == "NONE" && $polyt_col == "NONE" && $genome_col ~ /IN_GENOME=1/ {
    # Extract gene name
    split($1, contig_parts, "::");
    gene = contig_parts[1];
    region = contig_parts[2];
    
    # Extract chromosome and genomic region start
    split(region, region_parts, ":");
    chr = region_parts[1];
    
    # Extract genomic start position
    split(region_parts[2], pos_parts, "-");
    genome_start = pos_parts[1] + 0;  # Convert to number
    
    # Extract strand 
    if (region ~ /[(][+][)]/) {
      strand = "+";
    } else {
      strand = "-";
    }
    
    # Get relative positions and calculate absolute coordinates
    rel_start = $2 + 0;  # Convert to number
    rel_end = $3 + 0;    # Convert to number
    
    # Calculate absolute positions (always add to region start)
    abs_start = genome_start + rel_start;
    abs_end = genome_start + rel_end;
    
    # Get orientation (FWD/RVS)
    orientation = $orientation_col;
    
    # Create a unique guide ID using gene, relative positions, and orientation
    guide_id = gene "_" rel_start "_" rel_end "_" orientation;
    
    # Store coordinates for guide selection (using relative positions)
    print chr, rel_start, rel_end, guide_id, $hsu_col, strand > "'$TMP_DIR'/guides_rel.bed";
    
    # Store absolute coordinates for IGV output
    print chr, abs_start, abs_end, guide_id, $hsu_col, strand > "'$TMP_DIR'/guides_abs.bed";
    
    # Store original data for lookup
    print guide_id, $0 > "'$TMP_DIR'/guide_lookup.txt";
  }
' "$INPUT"


# Check if guides were found
if [ ! -s "$TMP_DIR/guides_rel.bed" ]; then
  echo "Error: No guides found matching the filtering criteria"
  exit 1
fi

# Sort by score (descending)
sort -k5,5nr "$TMP_DIR/guides_rel.bed" > "$TMP_DIR/guides_sorted.bed"

# Process each gene separately
awk '{split($4, parts, "_"); print parts[1]}' "$TMP_DIR/guides_sorted.bed" | sort | uniq > "$TMP_DIR/gene_names.txt"
GENE_COUNT=$(wc -l < "$TMP_DIR/gene_names.txt")
verbose "Found $GENE_COUNT unique genes to process"

# Initialize collection for selected guides
> "$TMP_DIR/selected_guides.bed"
> "$TMP_DIR/selected_ids.txt"

# Process each gene
TOTAL_SELECTED=0

while read -r GENE; do
 verbose "Processing gene: $GENE"
 
 # Extract guides for this gene - use standard grep with word boundaries
 grep -E "^[^\t]+\t[^\t]+\t[^\t]+\t${GENE}_" "$TMP_DIR/guides_sorted.bed" > "$TMP_DIR/${GENE}.bed"
 GUIDE_COUNT=$(wc -l < "$TMP_DIR/${GENE}.bed")
 verbose "  Found $GUIDE_COUNT guides for $GENE"
 
 if [ "$GUIDE_COUNT" -eq 0 ]; then
   verbose "  No guides found for $GENE after filtering, skipping"
   continue
 fi
 
 # Start with empty selected guides and exclusion zones files
 > "$TMP_DIR/${GENE}_selected.bed"
 > "$TMP_DIR/${GENE}_exclusion_zones.bed"
 
 # Loop through each guide from highest to lowest score
 while read -r GUIDE; do
   # Extract guide information
   GUIDE_CHR=$(echo "$GUIDE" | cut -f1)
   GUIDE_START=$(echo "$GUIDE" | cut -f2)
   GUIDE_END=$(echo "$GUIDE" | cut -f3)
   GUIDE_ID=$(echo "$GUIDE" | cut -f4)
   GUIDE_SCORE=$(echo "$GUIDE" | cut -f5)
   GUIDE_STRAND=$(echo "$GUIDE" | cut -f6)
   
   # Check if this guide overlaps with any exclusion zone
   if [ ! -s "$TMP_DIR/${GENE}_exclusion_zones.bed" ]; then
     # No exclusion zones yet, so no overlap - select this guide
     IS_OVERLAPPING=0
   else
     # Check if the current guide overlaps with any exclusion zone
     IS_OVERLAPPING=$(echo -e "${GUIDE_CHR}\t${GUIDE_START}\t${GUIDE_END}\t${GUIDE_ID}\t${GUIDE_SCORE}\t${GUIDE_STRAND}" | 
                    bedtools intersect -a stdin -b "$TMP_DIR/${GENE}_exclusion_zones.bed" -wa -u | 
                    wc -l)
   fi
   
   if [ "$IS_OVERLAPPING" -eq 0 ]; then
     # No overlap with exclusion zones - select this guide
     echo "$GUIDE" >> "$TMP_DIR/${GENE}_selected.bed"
     
     # Create the exclusion zone for this guide (guide region plus flanking regions)
     EXCLUSION_START=$((GUIDE_START - ZONE_SIZE))
     if [ "$EXCLUSION_START" -lt 0 ]; then
       EXCLUSION_START=0
     fi
     EXCLUSION_END=$((GUIDE_END + ZONE_SIZE))
     
     # Add the exclusion zone to the exclusion zones file
     echo -e "${GUIDE_CHR}\t${EXCLUSION_START}\t${EXCLUSION_END}\t${GUIDE_ID}\t${GUIDE_SCORE}\t${GUIDE_STRAND}" >> "$TMP_DIR/${GENE}_exclusion_zones.bed"
     
     # Check if score is below threshold
     if (( $(echo "$GUIDE_SCORE < $MIN_SCORE" | bc -l) )); then
       echo "Warning: Selected guide with low score: $GUIDE_ID (score: $GUIDE_SCORE, threshold: $MIN_SCORE)"
     fi
     
     verbose "  Selected guide: $GUIDE_ID"
   fi
 done < "$TMP_DIR/${GENE}.bed"
 
 # Sort selected guides by position
 sort -k2,2n "$TMP_DIR/${GENE}_selected.bed" >> "$TMP_DIR/selected_guides.bed"
 
 # Extract guide IDs
 cut -f4 "$TMP_DIR/${GENE}_selected.bed" >> "$TMP_DIR/selected_ids.txt"
 
 # Count selected guides
 SELECTED_COUNT=$(wc -l < "$TMP_DIR/${GENE}_selected.bed")
 TOTAL_SELECTED=$((TOTAL_SELECTED + SELECTED_COUNT))
 verbose "  Selected $SELECTED_COUNT guides for $GENE with average spacing of $((ZONE_SIZE * 2)) bp"
done < "$TMP_DIR/gene_names.txt"


verbose "Creating output files..."

# Write header to full output
head -n 1 "$INPUT" > "$FULL_OUTPUT"

# Add selected guides to full output
while read -r ID; do
  # Use basic grep for compatibility (with tab character)
  grep "^$ID	" "$TMP_DIR/guide_lookup.txt" | cut -f2- >> "$FULL_OUTPUT"
done < "$TMP_DIR/selected_ids.txt"

# Create the IGV BED file directly in a temporary file first
TMP_BED="${TMP_DIR}/igv_temp.bed"
> "$TMP_BED"

# Process each selected guide ID
while read -r ID; do
  # Find the absolute coordinates
  LINE=$(grep -E "^[^	]*	[^	]*	[^	]*	$ID	" "$TMP_DIR/guides_abs.bed" || echo "")
  if [ -n "$LINE" ]; then
    CHR=$(echo "$LINE" | cut -f1)
    START=$(echo "$LINE" | cut -f2)
    END=$(echo "$LINE" | cut -f3)
    SCORE=$(echo "$LINE" | cut -f5)
    STRAND=$(echo "$LINE" | cut -f6)
    
    # Validate entry before adding
    if [[ $CHR == chr* ]] && [[ "$START" =~ ^[0-9]+$ ]] && [[ "$END" =~ ^[0-9]+$ ]]; then
      echo -e "${CHR}\t${START}\t${END}\t${ID}\t${SCORE}\t${STRAND}" >> "$TMP_BED"
    else
      verbose "  Warning: Skipping invalid entry: $LINE"
    fi
  else
    verbose "  Warning: Could not find absolute coordinates for $ID"
  fi
done < "$TMP_DIR/selected_ids.txt"

# Sort the temporary BED file
if [ -s "$TMP_BED" ]; then
  sort -k1,1 -k2,2n "$TMP_BED" > "${TMP_DIR}/igv_sorted.bed"
  
  # Make sure the output file is completely empty before writing
  rm -f "$IGV_BED_OUTPUT"
  
  # Copy the sorted file to the final location
  cp "${TMP_DIR}/igv_sorted.bed" "$IGV_BED_OUTPUT"
  
  # Double-check the file was created correctly
  if [ -s "$IGV_BED_OUTPUT" ]; then
    verbose "BED file created successfully with $(wc -l < "$IGV_BED_OUTPUT") entries"
  else
    echo "Error: Failed to create BED file"
  fi
else
  echo "Warning: No valid BED entries were found. Check your input data."
  # Create an empty BED file
  > "$IGV_BED_OUTPUT"
fi

echo "Guide selection complete! Selected $TOTAL_SELECTED guides across $GENE_COUNT genes."
echo "Full data saved to: $FULL_OUTPUT"
echo "BED format for IGV visualization saved to: $IGV_BED_OUTPUT"

exit 0
