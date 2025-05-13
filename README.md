# genTile

A tool for designing optimally spaced CRISPR guide libraries for precise dosage modulation across gene targets. Primarily intended for internal use in the Lappalainen lab.

## Overview

genTile extracts sequences upstream of gene transcription start sites (TSS) and prepares them for CRISPR guide design. This tool aims to facilitate tiling of guides for CRISPRi/a applications with specific spacing to modulate effect size for dosage studies.

## Features

- Extract sequences upstream of gene TSS with customizable distance
- Support for both gene symbols and ENSEMBL IDs
- Handle single genes or batch processing from files
- Automatic disambiguation of duplicate gene names
- Strand-aware sequence extraction
- Output in FASTA format ready for guide design

## Requirements

### Dependencies

- **Bash** (version 4.0+)
- **bedtools** (must be in your PATH)
- **Reference genome** in FASTA format

### Genome Data

genTile currently works with human genome hg38, which can be downloaded from UCSC:
- For human hg38: Download from [UCSC](https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz)

After downloading:
```bash
# Uncompress the genome
gunzip hg38.fa.gz

# Create an index file (recommended)
samtools faidx hg38.fa
# OR
bedtools index -f hg38.fa
```

## Installation

```bash
# Clone the repository
git clone https://github.com/nathanaelandrews/genTile.git
cd genTile

# Verify bedtools is installed
bedtools --version
```

No additional installation is required. All scripts can be run directly from the bin directory.

## Usage

### Basic Usage

```bash
./bin/get_sequence.sh -i GENE -r /path/to/genome.fa
```

### Options

```
Options:
  -i, --input <gene|file>  Gene name/ID or file with gene names (required)
  -r, --reference <file>   Path to reference genome FASTA (required)
  -d, --distance <bp>      Distance upstream of TSS (default: 2000)
  -o, --output <file>      Output file (default: stdout)
  -v, --verbose            Show detailed progress
  -h, --help               Show this help message
```

### Examples

Extract 1000bp upstream of TP53:
```bash
./bin/get_sequence.sh -i TP53 -r /path/to/hg38.fa -d 1000
```

Process multiple genes from a file:
```bash
echo -e "TP53\nBRCA1\nPTEN" > genes.txt
./bin/get_sequence.sh -i genes.txt -r /path/to/hg38.fa -d 2000 -o sequences.fa
```

Use ENSEMBL ID for ambiguous gene names:
```bash
./bin/get_sequence.sh -i ENSG00000141510 -r /path/to/hg38.fa -d 1500
```

Show detailed progress:
```bash
./bin/get_sequence.sh -i TP53 -r /path/to/hg38.fa -v
```

### Output Format

The output is in FASTA format with headers containing gene name, coordinates, and strand:

```
>GENE::chromosome:start-end(strand)
SEQUENCE
```

## Development/Testing

For local development:
```bash
# Using the local reference genome (not included in repository)
./bin/get_sequence.sh -i TP53 -r data/reference/genome/hg38/hg38.fa -d 2000 -v
```

## Troubleshooting

### Common Issues

1. **"Error: bedtools is required but not found in PATH"**
   - Install bedtools or ensure it's in your PATH

2. **"Error: Ambiguous gene name"**
   - Use the ENSEMBL ID provided in the error message instead of the gene symbol

3. **"Warning: No TSS found for gene"**
   - Verify the gene name or ID is correct
   - Check if the gene is annotated in the GENCODE v48 reference

## Future Features

- Integration with FlashFry for guide design
- Guide filtering based on off-target potential
- Variant overlap analysis
- ATAC/histone marker overlap assessment

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contact

For issues or questions, please contact [GitHub: nathanaelandrews](https://github.com/nathanaelandrews)
