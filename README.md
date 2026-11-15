# imgt-refbuilder

Bash utility for downloading IMGT immunoglobulin reference FASTAs and building
organism-level IgBLAST V/D/J nucleotide databases.

## Requirements

- NCBI IgBLAST — provides `igblastn`, `makeblastdb` and `edit_imgt_file.pl`.
  IgBLAST is an external dependency and is not included in this repository.
  Obtain the official release from NCBI:
  https://ftp.ncbi.nlm.nih.gov/blast/executables/igblast/release/
  (documentation: https://ncbi.github.io/igblast/)
- `perl` (to run `edit_imgt_file.pl`)
- `curl`

`edit_imgt_file.pl` is not included in this repository. It ships in the `bin/`
directory of the IgBLAST release package. `process` looks for it in `PATH`;
otherwise pass its path with `--edit-imgt-file`.

`build` uses `makeblastdb` from `PATH`, or `makeigblastdb` if `makeblastdb` is
not there. The Bioconda `igblast` package installs NCBI's `makeblastdb` under
the name `makeigblastdb`. `--makeblastdb <path>` accepts either executable.

## Quick start

1. Obtain NCBI IgBLAST (see above).
2. Download the IMGT references:

   ```bash
   ./scripts/imgt-refbuilder.sh download \
       --organism Homo_sapiens \
       --chain all
   ```

3. Process them with `edit_imgt_file.pl`:

   ```bash
   ./scripts/imgt-refbuilder.sh process \
       --organism Homo_sapiens
   ```

   Add `--edit-imgt-file /path/to/edit_imgt_file.pl` if it is not in `PATH`
   (`edit_imgt_file.pl` is not included in this repository and must be obtained
   separately from the official NCBI IgBLAST release).

4. Build the BLAST databases:

   ```bash
   ./scripts/imgt-refbuilder.sh build \
       --organism Homo_sapiens
   ```

5. Optionally run the IgBLAST check (writes `data/test/<organism>/igblast.out`):

   ```bash
   ./scripts/imgt-refbuilder.sh test \
       --organism Homo_sapiens \
       --query query.fasta
   ```

The downloader discovers available IG V, D and J FASTAs from the organism's
IMGT `IG/` directory at runtime. Not every organism has every IG group (missing
groups are normal), and some IMGT entries are TR-only with no `IG/` directory.
`--chain all` selects every available IG group — including unusual groups such
as `IGI` — while excluding TR references.

## Database layout

`build` produces one database directory per organism (`data/database/<organism>/`)
containing combined `V`, `D` and `J` BLAST nucleotide databases across all
available IG loci (for example, `IGHV`, `IGKV` and `IGLV` combined into `V`).
This follows [NCBI's IgBLAST setup workflow](https://ncbi.github.io/igblast/cook/How-to-set-up.html):
the same organism-level databases are used for both heavy- and light-chain
queries, and separate heavy/light database folders are not required.

## Tool paths

Tools are first looked up in `PATH`. If a tool is not there, provide its path
explicitly:

    --curl <path>
    --perl <path>
    --edit-imgt-file <path>
    --makeblastdb <path>      # makeblastdb or makeigblastdb
    --igblastn <path>
    --igdata <path>           # directory containing internal_data/ and optional_file/

## Organism support

IMGT reference availability is separate from IgBLAST built-in organism support.
An organism with available IMGT IG references can be downloaded, processed and
built into BLAST databases, but that does not mean IgBLAST has built-in
annotation support for it. The `test` command supports only the built-in IgBLAST
organisms: `Homo_sapiens`, `Mus_musculus`, `Rattus_norvegicus`,
`Oryctolagus_cuniculus` and `Macaca_mulatta`. Other organisms require NCBI's
custom-organism annotation files and configuration (`internal_data/` and
`optional_file/`), which this tool deliberately does not generate.

## License

The original code in imgt-refbuilder is licensed under the MIT License (see
LICENSE).

IMGT reference data are not included in this repository. They are downloaded
directly from IMGT by the user and are subject to IMGT's current Terms of Use
(IMGT data and metadata are provided under CC BY 4.0) and attribution
requirements; users should follow IMGT's citation guidance when using the
downloaded reference data:

- https://www.imgt.org/about/termsofuse.php
- https://www.imgt.org/about/CitingIMGT.php
- https://www.imgt.org/vquest/refseqh.html

NCBI IgBLAST is an external dependency and is not included in this repository.
Obtain it directly from NCBI.

imgt-refbuilder is an independent project and is not affiliated with or
endorsed by IMGT® or NCBI.
