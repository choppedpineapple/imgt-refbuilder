# imgt-refbuilder
Automated pipeline for downloading IMGT antibody reference sequences and generating IgBLAST reference databases.

## Usage

Download IMGT reference FASTAs:

    ./scripts/imgt-refbuilder.sh download --organism Homo_sapiens --chain all

Convert them to IgBLAST-compatible V/D/J FASTAs:

    ./scripts/imgt-refbuilder.sh process --organism Homo_sapiens

Build the V/D/J BLAST databases into `data/database/<organism>/`:

    ./scripts/imgt-refbuilder.sh build --organism Homo_sapiens

## External tools

Each subcommand needs one external tool: `curl` (download), `perl` (process),
`makeblastdb` (build) and `igblastn` (test, not yet functional). The tool is taken
from `PATH`; the program does not install or manage these tools (micromamba is one
possible way to install them). If a tool is not in `PATH`, pass its path explicitly:

    --curl <path>
    --perl <path>
    --makeblastdb <path>
    --igblastn <path>

For example:

    ./scripts/imgt-refbuilder.sh build --organism Homo_sapiens --makeblastdb /path/to/makeblastdb

`scripts/edit_imgt_file.pl` is the official NCBI utility, copied unchanged from the
IgBLAST 1.22.0 release (https://ftp.ncbi.nih.gov/blast/executables/igblast/release/);
the release is a US Government work in the public domain (see the LICENSE file in the
IgBLAST release package).
