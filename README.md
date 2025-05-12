# genTile

## Requirements

### genTile currently only works with human genome hg38, which can be downloaded from UCSC:
- Reference genome in FASTA format
  - For human hg38: Download from [UCSC](https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz)

## Usage

```bash
# Extract sequences using your own genome
./bin/get_sequence.sh --gene TP53 --genome /path/to/your/genome.fa --distance 2000
```

## Development/Testing

For local development:
```bash
# Using the local reference genome (not included in repository)
./bin/get_sequence.sh --gene TP53 --genome data/reference/genome/hg38/hg38.fa --distance 2000
```
