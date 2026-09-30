# imgt-refbuilder
Automated pipeline for downloading IMGT antibody reference sequences and generating IgBLAST reference databases.

## Usage

Download IMGT reference FASTAs:

    ./scripts/imgt-refbuilder.sh download --organism Homo_sapiens --chain all

Convert them to IgBLAST-compatible V/D/J FASTAs (requires `perl` in PATH, e.g. from a micromamba environment):

    ./scripts/imgt-refbuilder.sh process --organism Homo_sapiens

Build the V/D/J BLAST databases into `data/database/<organism>/` (uses `makeblastdb`
from PATH, e.g. from a micromamba environment):

    ./scripts/imgt-refbuilder.sh build --organism Homo_sapiens

If `makeblastdb` is not in PATH, pass it explicitly:

    ./scripts/imgt-refbuilder.sh build --organism Homo_sapiens --makeblastdb /path/to/makeblastdb

`scripts/edit_imgt_file.pl` is the official NCBI utility, copied unchanged from the
IgBLAST 1.22.0 release (https://ftp.ncbi.nih.gov/blast/executables/igblast/release/);
the release is a US Government work in the public domain (see the LICENSE file in the
IgBLAST release package).
