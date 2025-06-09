# genTile

A tool for designing optimally spaced CRISPR guide libraries for precise dosage modulation across gene targets.

## Overview

genTile is a pipeline, primarily intended for internal use in the Lappalainen lab, for designing CRISPR guide RNAs with optimal spacing and positioning for CRISPRi/a applications. It extracts sequences from target genomic regions, designs candidate guides using FlashFry, and selects high-scoring guides with appropriate spacing and TSS-relative positioning for effective tiling, interference, or activation experiments.

## Requirements

- Bash (4.0+)
- bedtools
- Java (for FlashFry)
- Reference genome (currently only supports hg38)
- wget or curl (for CAGE data download)

## Installation

```bash
git clone https://github.com/nathanaelandrews/genTile.git
cd genTile
./bin/setup.sh
```

You'll need the hg38 reference genome. If you don't already have it, you can download it and place it in the expected location:

```bash
mkdir -p data/reference/genome/hg38
wget -O data/reference/genome/hg38/hg38.fa.gz https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz
gunzip data/reference/genome/hg38/hg38.fa.gz
```

Alternatively, you can use an existing reference genome by specifying its path when running the scripts.

### Setup Process

The setup script:
- Downloads FlashFry (if not already installed)
- Creates a FlashFry database for guide design 

The database creation is the most time-consuming step of setup:
This is a one-time process (per enzyme); the database is then reused for all future guide designs
The FlashFry database for a full human genome is around 2.5 Gb

### Setup Options

- `-m, --memory <size>`: Java heap memory allocation for database creation (default: 4G)
  - For full human genome database, recommend 16G+ if available
  - Examples: `-m 16G`, `-m 32G`

- `-e, --enzyme <enzyme>`: CRISPR enzyme to use (default: spcas9ngg)
  - Options: spcas9ngg (standard Cas9), spcas9ngg19 (CRISPRi), spcas9nag, cpf1
  - Example: `-e spcas9ngg` 

## Complete Workflow Example

Here's a complete example workflow using the example gene list for multi-modal guide selection:

```bash
# Step 1: Extract sequences for target genes using CAGE data
./bin/get_sequence.sh -g examples/input/test_genes.txt -r data/reference/genome/hg38/hg38.fa -c K562 -v

# Step 2: Design guides using FlashFry
./bin/design_guides.sh -i output/sequences.fa -v

# Step 3: Select guides for all three modes with filtering
./bin/select_guides.sh -f output/guides.scored.txt -t -i -a -R BsaI -v

# Results will be in:
# - output/selected_guides.txt (Full guide details with mode flags)
# - output/selected_guides.bed (For visualization in genome browsers)
```

### Alternative: Using Custom Positions

```bash
# Step 1: Extract sequences from custom genomic positions
./bin/get_sequence.sh -p examples/input/test_positions.txt -r data/reference/genome/hg38/hg38.fa -v

# Steps 2-3: Same as above
```

### Alternative: Using Gencode TSS (Not Recommended)

```bash
# Step 1: Extract sequences using Gencode annotations instead of CAGE
./bin/get_sequence.sh -g examples/input/test_genes.txt -r data/reference/genome/hg38/hg38.fa -G -v

# Steps 2-3: Same as above
```

## Advanced Filtering Options

genTile supports advanced filtering to remove guides with potential issues for cloning and cell line compatibility:

### Restriction Enzyme Filtering

Filter out guides containing restriction sites that would interfere with cloning workflows:

```bash
# Filter guides with BsaI sites (Golden Gate assembly)
./bin/select_guides.sh -f guides.scored.txt -t -R BsaI

# Filter multiple enzymes
./bin/select_guides.sh -f guides.scored.txt -t -R BsaI,BsmBI,EcoRI

# Search available enzymes
./bin/list_enzymes.sh bsa                    # Find enzymes containing 'bsa'
./bin/list_enzymes.sh --sequences            # Show all enzymes with sequences
./bin/list_enzymes.sh                        # Show all available enzymes
```

### Genomic Variant Filtering

Filter out guides overlapping known genomic variants in your cell line:

```bash
# Filter using cell-line specific variants (user must provide BED file)
./bin/select_guides.sh -f guides.scored.txt -t -V data/personal/K562_variants.bed.gz

# Combined filtering for comprehensive guide selection
./bin/select_guides.sh -f guides.scored.txt -t -i -a -R BsaI -V variants.bed
```

**Note**: Variant filtering requires a user-prepared BED file of variant positions. See [Variant Filtering Setup](#variant-filtering-setup) below.

## Usage

The pipeline consists of three main steps:

### 1. Extract Sequences: get_sequence.sh

The `get_sequence.sh` script extracts genomic sequences around gene transcription start sites (TSS) using either CAGE data or Gencode annotations. It accepts gene lists or custom genomic positions, and retrieves specified upstream and downstream regions.

#### Features

- Supports both gene symbols and Ensembl IDs
- Cell-type-specific TSS from ENCODE CAGE data (recommended)
- Gencode TSS fallback (not recommended)
- Custom genomic position input
- Handles single genes or batch processing from files
- Produces strand-aware sequences (reverse-complemented for negative strand)
- Outputs in FASTA format with enhanced headers

#### Usage

```bash
# Gene mode (recommended)
./bin/get_sequence.sh -g <gene_file> -r <reference_genome> -c <cell_line> [options]

# Gene mode with Gencode TSS (not recommended)
./bin/get_sequence.sh -g <gene_file> -r <reference_genome> -G [options]

# Position mode
./bin/get_sequence.sh -p <position_file> -r <reference_genome> [options]
```

#### Options

**Input Options (choose one):**
- `-g, --genes <file>`: Gene names/IDs file (one gene per line)
- `-p, --positions <file>`: Position file (format: name,chr:pos,strand)

**TSS Source Options (required for gene mode):**
- `-c, --cell-line <name>`: Use CAGE data for specified cell line (recommended)
- `-G, --gencode-only`: Force use of Gencode TSS (not recommended)

**Required Options:**
- `-r, --reference <file>`: Path to reference genome FASTA (required)

**Sequence Options:**
- `-u, --upstream <bp>`: Distance upstream of TSS (default: 1500)
- `-d, --downstream <bp>`: Distance downstream of TSS (default: 500)
- `-o, --output <file>`: Output file (default: "output/sequences.fa")
- `-v, --verbose`: Show detailed progress
- `-h, --help`: Show this help message

#### Available Cell Lines

The following ENCODE CAGE datasets are available:

| Cell Line | Description |
|-----------|-------------|
| K562 | Chronic myelogenous leukemia (ENCODE reference) |
| HeLa | Cervical cancer cell line |
| HepG2 | Hepatocellular carcinoma (liver cancer) |
| GM12878 | B-lymphoblastoid cell line (ENCODE reference) |
| H1 | Human embryonic stem cells |
| IMR90 | Normal human lung fibroblasts |
| HUVEC | Umbilical vein endothelial cells |
| keratinocyte | Primary skin barrier cells |
| CD14_monocyte | Primary immune cells |
| muscle_satellite | Adult muscle stem cells |
| osteoblast | Bone-forming cells |
| dermal_fibroblast | Primary skin connective tissue |
| SK-N-SH | Neuroblastoma with neuronal characteristics |

#### Examples

Extract sequences using CAGE data from K562 cells:
```bash
./bin/get_sequence.sh -g examples/input/test_genes.txt -r path/to/hg38.fa -c K562
```

Extract sequences from custom positions:
```bash
./bin/get_sequence.sh -p examples/input/test_positions.txt -r path/to/hg38.fa
```

#### Input File Formats

**Gene file format** (one gene per line):
```
TP53
BRCA1
ENSG00000141510
```

**Position file format** (name,chr:position,strand):
```
tp53_region,chr17:7687546,-
enhancer1,chr8:127736230,+
```

#### Output Format

The script produces FASTA format output with enhanced headers containing gene name, genomic coordinates, strand, and TSS position:

```
>TP53::chr17:7687546-7688546(-)::TSS_chr17:7687546
SEQUENCE...
```

### 2. Design Guides: design_guides.sh

The `design_guides.sh` script uses FlashFry to identify and score potential CRISPR guide RNAs from input sequences. It handles both the discovery and scoring steps of guide design with sensible defaults while allowing extensive customization.

#### Features

- Automated discovery and scoring of candidate guides in one step
- Uses FlashFry for comprehensive off-target analysis
- Multiple scoring metrics to evaluate guide quality and specificity

#### Usage

```bash
./bin/design_guides.sh -i <sequences.fa> [options]
```

#### Options

**Required Options:**
- `-i, --input <file>`: Input FASTA file with target sequences

**Common Options:**
- `-o, --output <file>`: Output file for scored guides (default: output/guides.scored.txt)
- `-d, --database <path>`: Path to FlashFry database (default: repository database)
- `-f, --flashfry <path>`: Path to FlashFry JAR file (default: repository JAR)
- `-m, --java-memory <size>`: Java heap memory size (default: 4G)
- `-v, --verbose`: Show detailed progress information
- `-h, --help`: Show this help message

**Advanced Options:**
- `--discover-args "<args>"`: Additional arguments to pass to FlashFry discover step (see FlashFry documentation: https://github.com/mckennalab/FlashFry)
- `--score-args "<args>"`: Additional arguments to pass to FlashFry score step (see FlashFry documentation: https://github.com/mckennalab/FlashFry)
- `--keep-intermediate <file>`: Keep the intermediate discovery output file

#### Examples

Basic usage with defaults:
```bash
./bin/design_guides.sh -i output/sequences.fa
```

Custom output file and memory:
```bash
./bin/design_guides.sh -i sequences.fa -o my_guides.txt -m 8G
```

#### Output Format

The script produces a tab-delimited text file with detailed information about each guide RNA, including:
- Contig, start, stop positions
- Target and context sequences
- Orientation (FWD/RVS)
- Multiple scoring metrics (Doench 2016, Hsu 2013, etc.)
- Off-target counts and specificity scores
- Filtering flags (dangerous GC content, polyT stretches, etc.)

#### Default Scoring Metrics

By default, the script applies these scoring metrics:
- `doench2016cfd`: CFD specificity score (Doench 2016)
- `dangerous`: Flags for dangerous sequence elements (polyT, high/low GC)
- `minot`: Minimum off-target analysis
- `hsu2013`: MIT scoring algorithm (Hsu 2013)
- `doench2014ontarget`: On-target scoring (Doench 2014)

### 3. Select Guides: select_guides.sh

The `select_guides.sh` script analyzes FlashFry output to select guides for different CRISPR applications. It supports three modes: tiling (spaced guides across regions), CRISPRi (TSS-proximal interference), and CRISPRa (TSS-upstream activation), with advanced filtering options for cloning compatibility and cell-line specificity.

#### Features

- **Multi-modal selection**: Tiling, CRISPRi, and CRISPRa modes with application-specific positioning
- **TSS-relative positioning**: CRISPRi targets -50 to +300bp from TSS, CRISPRa targets -400 to -50bp
- **Advanced filtering**: Remove guides with restriction sites or genomic variants
- **Flexible scoring**: Supports multiple scoring metrics (currently Hsu2013 working)
- **Guide deduplication**: Guides selected by multiple modes appear once with boolean flags
- **Quality filtering**: Excludes guides with problematic sequences (polyT, extreme GC content)
- **BED file generation**: Compatible output for genome browsers like IGV

#### Usage

```bash
./bin/select_guides.sh -f <guides.scored.txt> [mode_options] [filtering_options] [other_options]
```

#### Mode Selection (Required)

You must specify at least one mode:
- `-t, --tiling`: Select guides for tiling screens (spaced coverage)
- `-i, --crispri`: Select guides for CRISPRi knockdown experiments
- `-a, --crispra`: Select guides for CRISPRa activation experiments

#### Filtering Options

**Restriction Enzyme Filtering:**
- `-R, --restriction-enzymes <list>`: Filter guides containing restriction sites (comma-separated)
  - Example: `-R BsaI` or `-R BsaI,BsmBI,EcoRI`
  - Useful for Golden Gate assembly and cloning workflows

**Variant Filtering:**
- `-V, --filter-variants <bed>`: Filter guides overlapping genomic variants (BED file)
  - Requires user-provided BED file of variant positions
  - Conservative filtering: any overlap removes the guide

#### Other Options

**Input/Output:**
- `-f, --input <file>`: Input scored guides file from FlashFry (required)
- `-o, --output <file>`: Output selected guides file (default: output/selected_guides.txt)

**Scoring Options:**
- `-m, --score-metric <metric>`: Scoring metric to use (default: hsu2013)
  - Options: hsu2013, doench2016cfd (others currently not working)
- `-c, --score-cutoff <score>`: Minimum acceptable score (default: 80 for hsu2013)

**Tiling-Specific Options:**
- `-z, --zone-size <bp>`: Exclusion zone radius around each guide (default: 50)

**CRISPRi/CRISPRa-Specific Options:**
- `-n, --target-guides <num>`: Number of guides to select per gene (default: 5)

**General Options:**
- `-v, --verbose`: Show detailed progress
- `-h, --help`: Show this help message

#### Examples

**Tiling mode only:**
```bash
./bin/select_guides.sh -f output/guides.scored.txt -t
```

**CRISPRi mode with restriction enzyme filtering:**
```bash
./bin/select_guides.sh -f output/guides.scored.txt -i -n 3 -R BsaI
```

**All three modes with comprehensive filtering:**
```bash
./bin/select_guides.sh -f output/guides.scored.txt -t -i -a -R BsaI,BsmBI -V variants.bed.gz
```

**Custom scoring and parameters:**
```bash
./bin/select_guides.sh -f output/guides.scored.txt -t -m doench2016cfd -c 0.5 -z 25
```

#### Output Files

The script produces two main outputs:

1. **Selected guides file** (TSV format):
   - All original FlashFry columns
   - Three additional boolean columns: `tiling_guide`, `crispri_guide`, `crispra_guide`
   - Guide ID format: `gene_chr_position_strand_orientation`

2. **BED file** (for visualization):
   - Chromosome, start, end, guide name, score, and strand
   - Compatible with genome browsers like IGV
   - File name: `{output_basename}.bed`

#### Mode-Specific Selection Logic

**Tiling Mode:**
- Selects highest-scoring guides with optimal spacing
- Uses exclusion zones (default 50bp radius) to ensure coverage
- Processes guides in score-descending order
- Maintains spacing across entire target region

**CRISPRi Mode:**
- Targets guides within -50 to +300bp of TSS
- Selects top N highest-scoring guides in this window
- No spacing requirements (guides can be close together)
- Optimized for maximum knockdown efficiency

**CRISPRa Mode:**
- Targets guides within -400 to -50bp upstream of TSS
- Selects top N highest-scoring guides in this window
- No spacing requirements
- Optimized for transcriptional activation

#### How Multi-Mode Selection Works

1. Reads FlashFry output and parses TSS information from FASTA headers
2. Applies restriction enzyme filtering (if specified)
3. Calculates TSS-relative positions for each guide
4. Applies variant filtering (if specified)
5. Applies mode-specific filtering and selection
6. Combines results with boolean flags indicating selection mode(s)
7. Generates deduplicated output with mode annotations

## Variant Filtering Setup

For cell-line specific variant filtering, you need to prepare a BED file of variant positions:

### From VCF Files

If you have VCF files (e.g., from ENCODE), convert to BED format:

```bash
# Extract variants and convert to BED
bcftools query -f '%CHROM\t%POS0\t%END\t%REF>%ALT\n' variants.vcf.gz > variants.bed

# Sort and compress
sort -k1,1 -k2,2n variants.bed > variants_sorted.bed
bgzip variants_sorted.bed
tabix -p bed variants_sorted.bed.gz
```

### Coordinate Systems

Ensure your variant BED file uses the same reference genome as your guides:
- **hg19 → hg38**: Use UCSC liftOver or CrossMap for coordinate conversion
- **Chromosome naming**: Ensure consistent format (chr1 vs 1)

### Usage

```bash
# Use compressed or uncompressed BED files
./bin/select_guides.sh -f guides.scored.txt -t -V data/personal/variants.bed.gz
```

The filtering is conservative: any guide overlapping any variant position will be removed.

## Utility Scripts

### List Available Restriction Enzymes

Use `list_enzymes.sh` to browse the restriction enzyme database:

```bash
# Search for specific enzymes (case-insensitive)
./bin/list_enzymes.sh bsa
./bin/list_enzymes.sh eco

# Show all enzymes in columns
./bin/list_enzymes.sh

# Show with recognition sequences
./bin/list_enzymes.sh bsa --sequences

# Show with commercial sources
./bin/list_enzymes.sh --sources
```

The database contains 584+ commercially available restriction enzymes with IUPAC ambiguous bases preserved for accurate filtering.

## Acknowledgments

genTile relies heavily on the excellent FlashFry tool for guide RNA design and scoring. FlashFry provides the core functionality for guide identification and off-target analysis.

**FlashFry Citation**:
McKenna A, Shendure J. FlashFry: a fast and flexible tool for large-scale CRISPR target design. *BMC Biology* 16, 74 (2018). https://doi.org/10.1186/s12915-018-0545-0

FlashFry is a fast, flexible, and comprehensive CRISPR target design tool that scales to analyze entire genomes. It outperforms existing tools in speed while maintaining accuracy, and offers extensive customization for various CRISPR applications. Please visit [FlashFry on GitHub](https://github.com/mckennalab/FlashFry) for more information.

## Contact

For issues or questions, please contact [GitHub: nathanaelandrews](https://github.com/nathanaelandrews)
