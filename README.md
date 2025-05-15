# genTile

A tool for designing optimally spaced CRISPR guide libraries for precise dosage modulation across gene targets.

## Overview

genTile is a pipeline, primarily intended for internal use in the Lappalainen lab, for designing CRISPR guide RNAs with optimal spacing for CRISPRi/a applications. It extracts sequences from target genomic regions, designs candidate guides, and selects high-scoring guides with appropriate spacing for effective tiling. 

## Requirements

- Bash (4.0+)
- bedtools
- Java (for FlashFry)
- Reference genome (currently only supports hg38)

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

Here's a complete example workflow using the example gene list:

```bash
# Step 1: Extract sequences for target genes
./bin/get_sequence.sh -i examples/input/test_genes.txt -r data/reference/genome/hg38/hg38.fa -v

# Step 2: Design guides using FlashFry
./bin/design_guides.sh -i output/sequences.fa -v

# Step 3: Select optimal guides with 50bp exclusion zones
./bin/select_guides.sh -i output/guides.scored.txt -v

# Results will be in:
# - output/selected_guides.txt (Full guide details)
# - output/selected_guides.bed (For visualization in genome browsers)
```

## Usage

The pipeline consists of three main steps:

### 1. Extract Sequences: get_sequence.sh

The `get_sequence.sh` script extracts genomic sequences around gene transcription start sites (TSS). It accepts either a single gene or a file containing multiple genes, and retrieves the specified upstream and downstream regions around each gene's TSS.

#### Features

- Supports both gene symbols and Ensembl IDs
- Handles single genes or batch processing from files
- Produces strand-aware sequences (reverse-complemented for negative strand)
- Outputs in FASTA format 
- Currently selects TSS based on Gencode v47

#### Usage

```bash
./bin/get_sequence.sh -i <gene|file> -r <reference_genome> [options]
```

#### Options

- `-i, --input <gene|file>`: Gene name/ID or file with gene names (required)
- `-r, --reference <file>`: Path to reference genome FASTA (required)
- `-u, --upstream <bp>`: Distance upstream of TSS (default: 1500)
- `-d, --downstream <bp>`: Distance downstream of TSS (default: 500)
- `-o, --output <file>`: Output file (default: "output/sequences.fa")
- `-v, --verbose`: Show detailed progress
- `-h, --help`: Show this help message

#### Examples

Extract 1500bp upstream and 500bp downstream (default range) of 5 example genes:
```bash
./bin/get_sequence.sh -i examples/input/test_genes.txt -r path/to/hg38.fa
```

#### Output Format

The script produces FASTA format output with headers containing gene name, chromosome, start-end coordinates, and strand.


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

##### Required Options:
- `-i, --input <file>`: Input FASTA file with target sequences

##### Common Options:
- `-o, --output <file>`: Output file for scored guides (default: output/guides.scored.txt)
- `-d, --database <path>`: Path to FlashFry database (default: repository database)
- `-f, --flashfry <path>`: Path to FlashFry JAR file (default: repository JAR)
- `-m, --java-memory <size>`: Java heap memory size (default: 4G)
- `-v, --verbose`: Show detailed progress information
- `-h, --help`: Show this help message

##### Advanced Options:
- `--discover-args "<args>"`: Additional arguments to pass to FlashFry discover step (see FlashFry documentation: https://github.com/mckennalab/FlashFry)
- `--score-args "<args>"`: Additional arguments to pass to FlashFry score step (see FlashFry documentation: https://github.com/mckennalab/FlashFry)
- `--keep-intermediate <file>`: Keep the intermediate discovery output file

#### Examples

Basic usage with defaults:
```bash
./bin/design_guides.sh --input output/sequences.fa
```

Custom output file:
```bash
./bin/design_guides.sh --input sequences.fa --output my_guides.txt
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

The `select_guides.sh` script analyzes FlashFry output to select optimally spaced guide RNAs with high scores. It prioritizes guides by score while ensuring they maintain proper spacing for decent representation over the region of interest.

#### Features

- Selects guides based on Hsu 2013 metric with highest scores prioritized
- Creates non-overlapping guide sets with customizable spacing (default at least 50 bp upstream or downstream)
- Preserves all guide information from FlashFry
- Generates BED files for visualization in genome browsers
- Filters out potentially problematic guides (polyT, extreme GC content)
- Warns about low-scoring guides that pass other criteria

#### Usage

```bash
./bin/select_guides.sh -i <guides.scored.txt> [options]
```

#### Options

- `-i, --input <file>`: Input scored guides file from FlashFry (required)
- `-o, --output <file>`: Output selected guides file (default: output/selected_guides.txt)
- `-z, --zone-size <bp>`: Exclusion zone radius around each guide (default: 50)
- `-m, --min-score <score>`: Minimum acceptable Hsu score (default: 60)
- `-v, --verbose`: Show detailed progress
- `-h, --help`: Show this help message

#### Example

Select guides with default settings:
```bash
./bin/select_guides.sh -i output/guides.scored.txt
```

Use a smaller exclusion zone for denser tiling:
```bash
./bin/select_guides.sh -i output/guides.scored.txt -z 25
```

#### Output Files

The script produces two main outputs:

1. **Selected guides file** (text format):
   - Full FlashFry guide information for selected guides
   - Includes all original scoring metrics and annotations
   - Tab-delimited format with headers from FlashFry

2. **BED file** (for visualization):
   - Chromosome, start, end, guide name, score, and strand
   - Compatible with genome browsers like IGV
   - Guides represented by genomic coordinates

#### How It Works

1. Reads FlashFry output and extracts guide information
2. Converts relative positions to absolute genomic coordinates
3. Sorts guides by score (highest first)
4. For each gene:
   - Selects highest-scoring guide first
   - Creates an exclusion zone (guide ± zone_size)
   - Tests subsequent guides against all exclusion zones
   - Selects non-overlapping guides in score order
5. Generates output files with selected guides

## Acknowledgments

genTile relies heavily on the excellent FlashFry tool for guide RNA design and scoring. FlashFry provides the core functionality for guide identification and off-target analysis.

**FlashFry Citation**:
McKenna A, Shendure J. FlashFry: a fast and flexible tool for large-scale CRISPR target design. *BMC Biology* 16, 74 (2018). https://doi.org/10.1186/s12915-018-0545-0

FlashFry is a fast, flexible, and comprehensive CRISPR target design tool that scales to analyze entire genomes. It outperforms existing tools in speed while maintaining accuracy, and offers extensive customization for various CRISPR applications. Please visit [FlashFry on GitHub](https://github.com/mckennalab/FlashFry) for more information.

## Contact

For issues or questions, please contact [GitHub: nathanaelandrews](https://github.com/nathanaelandrews)
