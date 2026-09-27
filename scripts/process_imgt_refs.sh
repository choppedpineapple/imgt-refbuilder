#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

organism=""
while [[ ${#} -gt 0 ]]; do
    case "${1}" in
    --organism)
        organism="${2}"
        shift 2
        ;;
    *)
        echo "unknown argument: ${1}" >&2
        exit 2
        ;;
    esac
done

if [[ -z "${organism}" ]]; then
    echo "usage: ${0} --organism <IMGT_organism>" >&2
    exit 2
fi

if ! command -v perl >/dev/null; then
    echo "error: perl is required but not found in PATH; make it available in your micromamba environment" >&2
    exit 1
fi

if [[ ! -d "data/raw/${organism}" ]]; then
    echo "error: no raw data for '${organism}'; run scripts/download_imgt_refs.sh first" >&2
    exit 1
fi

# NCBI-documented usage: edit_imgt_file.pl imgt_file > my_seq_file
# (rewrites IMGT deflines to germline gene names, strips alignment dots)
for raw in data/raw/"${organism}"/*/*.fasta; do
    out="data/processed/${organism}/$(basename "$(dirname "${raw}")")/$(basename "${raw}")"
    mkdir -p "$(dirname "${out}")"
    perl "${SCRIPT_DIR}/edit_imgt_file.pl" "${raw}" >"${out}"
done
