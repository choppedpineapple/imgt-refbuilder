# imgt-refbuilder
Automated pipeline for downloading IMGT antibody reference sequences and generating IgBLAST reference databases.

## Usage

Download IMGT reference FASTAs:

    ./scripts/download_imgt_refs.sh --organism Homo_sapiens --chain all

Convert them to IgBLAST-compatible FASTAs (requires `perl` in PATH, e.g. from a micromamba environment):

    ./scripts/process_imgt_refs.sh --organism Homo_sapiens

`scripts/edit_imgt_file.pl` is the official NCBI utility, copied unchanged from the
IgBLAST 1.22.0 release (https://ftp.ncbi.nih.gov/blast/executables/igblast/release/);
the release is a US Government work in the public domain (see the LICENSE file in the
IgBLAST release package).
