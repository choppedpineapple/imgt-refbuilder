# imgt-refbuilder

Bash utility for building IgBLAST-ready immunoglobulin reference databases from
the official IMGT reference data.

## Requirements

- NCBI IgBLAST — provides `igblastn`, `makeblastdb` and `edit_imgt_file.pl`.
  IgBLAST is an external dependency and is not included in this repository.
  Obtain the official release from NCBI:
  https://ftp.ncbi.nlm.nih.gov/blast/executables/igblast/release/
  (documentation: https://ncbi.github.io/igblast/)
- `perl` (to run `edit_imgt_file.pl`)
- `curl`

`edit_imgt_file.pl` is not included in this repository. It ships in the `bin/`
directory of the IgBLAST release package; pass its path with `--edit-imgt-file`
when running `process`.

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
       --organism Homo_sapiens \
       --edit-imgt-file /path/to/edit_imgt_file.pl
   ```

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

The download, process and build commands work for organisms in the IMGT
reference directory. Not every organism has IGH, IGK and IGL reference files —
the downloader simply uses the reference files IMGT provides for that organism,
and missing groups are normal.

## Tool paths

Tools are first looked up in `PATH`. If a tool is not there, provide its path
explicitly:

    --curl <path>
    --perl <path>
    --edit-imgt-file <path>   # required for process
    --makeblastdb <path>
    --igblastn <path>
    --igdata <path>           # directory containing internal_data/ and optional_file/

## Organism support

IMGT reference availability is separate from IgBLAST built-in organism support.
Any IMGT organism can be downloaded, processed and built. The `test` command
currently supports only the built-in IgBLAST organisms: Homo_sapiens,
Mus_musculus, Rattus_norvegicus, Oryctolagus_cuniculus and Macaca_mulatta. Other
organisms require NCBI's custom-organism annotation setup, which this tool does
not generate.

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
