#!/usr/bin/env bash

set -euo pipefail

BASE="https://www.imgt.org/download/V-QUEST/IMGT_V-QUEST_reference_directory"

organism=""
chain=""
while [[ ${#} -gt 0 ]]; do
    case "${1}" in
    --organism)
        organism="${2}"
        shift 2
        ;;
    --chain)
        chain="${2}"
        shift 2
        ;;
    *)
        echo "unknown argument: ${1}" >&2
        exit 2
        ;;
    esac
done

if [[ -z "${organism}" || -z "${chain}" ]]; then
    echo "usage: ${0} --organism <IMGT_organism> --chain heavy|kappa|lambda|all" >&2
    exit 2
fi

case "${chain}" in
heavy) chains=(IGH) ;;
kappa) chains=(IGK) ;;
lambda) chains=(IGL) ;;
all) chains=(IGH IGK IGL) ;;
*)
    echo "invalid chain: ${chain} (expected heavy|kappa|lambda|all)" >&2
    exit 2
    ;;
esac

total=0
for c in "${chains[@]}"; do
    outdir="data/raw/${organism}/${c}"
    for g in V D J; do
        file="${c}${g}.fasta"
        url="${BASE}/${organism}/IG/${file}"
        # not every organism has every chain/group (e.g. no IGK in Gallus_gallus)
        if [[ "$(curl -s -o /dev/null -w '%{http_code}' "${url}")" == "404" ]]; then
            echo "skipping ${file} (not available for ${organism})"
            continue
        fi
        mkdir -p "${outdir}"
        curl -fsSL "${url}" -o "${outdir}/${file}.tmp"

        if [[ ! -s "${outdir}/${file}.tmp" ]] || ! grep -q '^>' "${outdir}/${file}.tmp"; then
            rm -f "${outdir}/${file}.tmp"
            echo "error: download failed or not a FASTA: ${url}" >&2
            exit 1
        fi
        mv "${outdir}/${file}.tmp" "${outdir}/${file}"
        total=$((total + 1))
    done
done

if [[ ${total} -eq 0 ]]; then
    echo "error: no files found for organism '${organism}' chain '${chain}' (check the organism name against the IMGT reference directory)" >&2
    exit 1
fi
