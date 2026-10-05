# imgt-refbuilder
Small Bash utility for building IgBLAST-ready immunoglobulin reference databases
from the official IMGT reference data.

## Requirements

Install these separately; imgt-refbuilder does not install or manage them:

- NCBI IgBLAST — provides `igblastn`, `makeblastdb` and `edit_imgt_file.pl`
  (in the `bin` directory of the release package):
  https://ftp.ncbi.nlm.nih.gov/blast/executables/igblast/release/
  (documentation: https://ncbi.github.io/igblast/)
- `perl` (for `edit_imgt_file.pl`) and `curl`

## Usage

Download IMGT reference FASTAs (https://www.imgt.org/vquest/refseqh.html):

    ./scripts/imgt-refbuilder.sh download --organism Homo_sapiens --chain all

Process them into IgBLAST-compatible V/D/J FASTAs:

    ./scripts/imgt-refbuilder.sh process --organism Homo_sapiens \
        --edit-imgt-file /path/to/edit_imgt_file.pl

Build the V/D/J BLAST databases into `data/database/<organism>/`:

    ./scripts/imgt-refbuilder.sh build --organism Homo_sapiens

Run a small IgBLAST check against the generated databases (writes
`data/test/<organism>/igblast.out`):

    ./scripts/imgt-refbuilder.sh test --organism Homo_sapiens --query query.fasta \
        --igblastn /path/to/igblastn --igdata /path/to/igblast/data

`test` currently supports the built-in IgBLAST organisms only: Homo_sapiens,
Mus_musculus, Rattus_norvegicus, Oryctolagus_cuniculus, Macaca_mulatta. Other
organisms need NCBI's custom-organism annotation setup, which this tool does not
provide. IgBLAST's `internal_data`/`optional_file` are located via `--igdata <path>`
or the `IGDATA` environment variable.

## Tool paths

Each subcommand finds its tool (`curl`, `perl`, `makeblastdb`, `igblastn`) in
`PATH`. If a tool is not in `PATH`, pass it explicitly:

    --curl <path>
    --perl <path>
    --makeblastdb <path>
    --igblastn <path>
    --igdata <path>          # directory containing internal_data/ and optional_file/
    --edit-imgt-file <path>  # required for process; from the IgBLAST release package

## License and third-party material

imgt-refbuilder itself is MIT licensed (see LICENSE); this applies only to the
code in this repository.

- NCBI IgBLAST is an external dependency. `edit_imgt_file.pl`, `igblastn` and
  `makeblastdb` are obtained from the official NCBI IgBLAST distribution and are
  not redistributed by this project. IgBLAST is a U.S. Government Work, freely
  available for public use (https://ncbi.github.io/igblast/dev/copyright.html).
- IMGT reference data are not included. They are downloaded directly from IMGT
  when you run `download` and are subject to the IMGT Terms of Use (CC BY 4.0,
  with IMGT attribution/citation required): https://www.imgt.org/about/termsofuse.php
