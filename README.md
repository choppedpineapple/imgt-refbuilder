# imgt-refbuilder
Automated pipeline for downloading IMGT antibody reference sequences and generating IgBLAST reference databases.

## Usage

Download IMGT reference FASTAs:

    ./scripts/imgt-refbuilder.sh download --organism Homo_sapiens --chain all

Convert them to IgBLAST-compatible V/D/J FASTAs:

    ./scripts/imgt-refbuilder.sh process --organism Homo_sapiens

Build the V/D/J BLAST databases into `data/database/<organism>/`:

    ./scripts/imgt-refbuilder.sh build --organism Homo_sapiens

Run a small IgBLAST check against the generated databases (writes
`data/test/<organism>/igblast.out`):

    ./scripts/imgt-refbuilder.sh test --organism Homo_sapiens --query path/to/query.fasta

`test` currently supports the built-in IgBLAST organisms only: Homo_sapiens,
Mus_musculus, Rattus_norvegicus, Oryctolagus_cuniculus, Macaca_mulatta. Other
organisms need NCBI's custom-organism annotation setup, which this tool does not
provide yet. IgBLAST's `internal_data`/`optional_file` are located via `--igdata <path>`
or the `IGDATA` environment variable.

## External tools

Each subcommand needs one external tool: `curl` (download), `perl` (process),
`makeblastdb` (build) and `igblastn` (test). The tool is taken
from `PATH`; the program does not install or manage these tools (micromamba is one
possible way to install them). If a tool is not in `PATH`, pass its path explicitly:

    --curl <path>
    --perl <path>
    --makeblastdb <path>
    --igblastn <path>
    --igdata <path>   # directory containing internal_data/ and optional_file/

For example:

    ./scripts/imgt-refbuilder.sh build --organism Homo_sapiens --makeblastdb /path/to/makeblastdb

`scripts/edit_imgt_file.pl` is the official NCBI utility, copied unchanged from the
IgBLAST 1.22.0 release (https://ftp.ncbi.nih.gov/blast/executables/igblast/release/);
the release is a US Government work in the public domain (see the LICENSE file in the
IgBLAST release package).
