# imgt-refbuilder
Automated pipeline for downloading IMGT antibody reference sequences and generating IgBLAST reference databases.

## Usage

Download IMGT reference FASTAs:

    ./scripts/imgt-refbuilder.sh download --organism Homo_sapiens --chain all

Convert them to IgBLAST-compatible V/D/J FASTAs (requires `perl` in PATH, e.g. from a micromamba environment):

    ./scripts/imgt-refbuilder.sh process --organism Homo_sapiens

`scripts/edit_imgt_file.pl` is the official NCBI utility, copied unchanged from the
IgBLAST 1.22.0 release (https://ftp.ncbi.nih.gov/blast/executables/igblast/release/);
the release is a US Government work in the public domain (see the LICENSE file in the
IgBLAST release package).
