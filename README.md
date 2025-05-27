# genTile

A tool for designing optimally spaced CRISPR guide libraries for precise dosage modulation across gene targets.

## Overview

genTile is a pipeline, primarily intended for internal use in the Lappalainen lab, for designing CRISPR guide RNAs with optimal spacing for CRISPRi/a applications. It extracts sequences from target genomic regions using CAGE data or custom positions, designs candidate guides, and selects high-scoring guides with appropriate spacing for effective tiling.

## Requirements

- Bash (4.0+)
- bedtools
- Java (for FlashFry)
- Reference genome (currently only supports hg38)
- wget or curl (for downloading CAGE data)

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

### Setup Process

The setup script:
- Downloads FlashFry (if not already installed)
- Creates a FlashFry database for guide design

The database creation is the most time-consuming step of setup and is a one-time process (per enzyme). The FlashFry database for a full human genome is around 2.5 GB.

### Setup Options

- `-m, --memory <size>`: Java heap memory allocation for database creation (default: 4G)
  - For full human genome database, recommend 16G+ if available
- `-e, --enzyme <enzyme>`: CRISPR enzyme to use (default: spcas9ngg)
  - Options: spcas9ngg (standard Cas9), spcas9ngg19 (CRISPRi), spcas9nag, cpf1

## Complete Workflow Example

Here's a complete example workflow using CAGE data for K562 cells:

```bash
# Step 1: Extract sequences for target genes using CAGE data
./bin/get_sequence.sh -g examples/input/test_genes.txt -r data/reference/genome/hg38/hg38.fa -c K562 -v

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

The `get_sequence.sh` script extracts genomic sequences around transcription start sites (TSS) or custom positions. It uses ENCODE CAGE data for accurate, cell-type-specific TSS identification, with Gencode annotations as fallback.

#### Features

- **CAGE-based TSS identification**: Uses ENCODE CAGE data for cell-type-specific TSS positions (recommended)
- **Custom positions**: Support for user-defined genomic coordinates  
- **Gencode fallback**: Falls back to Gencode annotations when CAGE data unavailable
- **Strand-aware sequences**: Reverse-complemented for negative strand genes
- **Batch processing**: Handle multiple genes or positions from files

#### Usage

```bash
# Using CAGE data (recommended)
./bin/get_sequence.sh -g <genes_file> -r <reference_genome> -c <cell_line> [options]

# Using custom positions
./bin/get_sequence.sh -p <positions_file> -r <reference_genome> [options]

# Using Gencode TSS (not recommended)
./bin/get_sequence.sh -g <genes_file> -r <reference_genome> -G [options]
```

#### Available Cell Lines for CAGE Data

The tool supports multiple ENCODE cell lines including:
- **K562**: Chronic myelogenous leukemia (ENCODE reference)
- **HepG2**: Hepatocellular carcinoma (liver cancer)
- **GM12878**: B-lymphoblastoid (ENCODE reference)
- **HeLa**: Cervical cancer cell line
- **H1**: Human embryonic stem cells
- And many others (see full list with `./bin/lib/fetch_CAGE_data.sh`)

#### Options

- `-g, --genes <file>`: Gene names/IDs file (one gene per line)
- `-p, --positions <file>`: Position file (format: name,chr:pos,strand)
- `-r, --reference <file>`: Path to reference genome FASTA (required)
- `-c, --cell-line <name>`: Use CAGE data for specified cell line
- `-G, --gencode-only`: Force use of Gencode TSS (not recommended)
- `-u, --upstream <bp>`: Distance upstream of TSS (default: 1500)
- `-d, --downstream <bp>`: Distance downstream of TSS (default: 500)
- `-o, --output <file>`: Output file (default: output/sequences.fa)
- `-v, --verbose`: Show detailed progress
- `-h, --help`: Show help message

#### Examples

```bash
# Extract sequences using K562 CAGE data
./bin/get_sequence.sh -g examples/input/test_genes.txt -r path/to/hg38.fa -c K562

# Use custom genomic positions
./bin/get_sequence.sh -p examples/input/test_positions.txt -r path/to/hg38.fa

# Use different upstream/downstream distances
./bin/get_sequence.sh -g genes.txt -r hg38.fa -c HepG2 -u 2000 -d 1000
```

#### Position File Format

For custom positions, use this format:
```
enhancer1,chr8:127736230,+
promoter2,chr17:7687546,-
```

### 2. Design Guides: design_guides.sh

The `design_guides.sh` script uses FlashFry to identify and score potential CRISPR guide RNAs from input sequences. It handles both the discovery and scoring steps of guide design with sensible defaults while allowing extensive customization.

#### Usage

```bash
./bin/design_guides.sh -i <sequences.fa> [options]
```

#### Key Options

- `-i, --input <file>`: Input FASTA file with target sequences (required)
- `-o, --output <file>`: Output file for scored guides (default: output/guides.scored.txt)
- `-v, --verbose`: Show detailed progress information
- `--discover-args "<args>"`: Additional arguments for FlashFry discover step
- `--score-args "<args>"`: Additional arguments for FlashFry score step

#### Default Scoring Metrics

- `doench2016cfd`: CFD specificity score
- `dangerous`: Flags for dangerous sequence elements
- `minot`: Minimum off-target analysis
- `hsu2013`: MIT scoring algorithm
- `doench2014ontarget`: On-target scoring

### 3. Select Guides: select_guides.sh

The `select_guides.sh` script analyzes FlashFry output to select optimally spaced guide RNAs with high scores. It prioritizes guides by score while ensuring proper spacing for good representation over the region of interest.

#### Features

- Selects guides based on Hsu 2013 metric with highest scores prioritized
- Creates non-overlapping guide sets with customizable spacing (default 50 bp exclusion zones)
- Generates BED files for visualization in genome browsers
- Filters out potentially problematic guides (polyT, extreme GC content)

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

#### Output Files

1. **Selected guides file** (text format): Full FlashFry guide information for selected guides
2. **BED file** (for visualization): Compatible with genome browsers like IGV

## Acknowledgments

genTile relies heavily on the excellent FlashFry tool for guide RNA design and scoring. FlashFry provides the core functionality for guide identification and off-target analysis.

**FlashFry Citation**:
McKenna A, Shendure J. FlashFry: a fast and flexible tool for large-scale CRISPR target design. *BMC Biology* 16, 74 (2018). https://doi.org/10.1186/s12915-018-0545-0

The tool also uses ENCODE CAGE data for accurate TSS identification, which is based on FANTOM5 CAGE profiles.

**CAGE Data Citation**:
Abugessaisa I, Noguchi S, Hasegawa A, et al. FANTOM5 CAGE profiles of human and mouse reprocessed for GRCh38 and GRCm38 genome assemblies. *Sci Data* 4, 170107 (2017). https://doi.org/10.1038/sdata.2017.107

## Contact

For issues or questions, please contact [GitHub: nathanaelandrews](https://github.com/nathanaelandrews)
