#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${script_dir}/.."

base_url="https://www.imgt.org/download/V-QUEST/IMGT_V-QUEST_reference_directory"

usage() {
    echo "usage: ${0} download --organism <name> --chain heavy|kappa|lambda|all" >&2
    echo "       ${0} process --organism <name>" >&2
    exit 2
}

cmd="${1:-}"
[[ -z "${cmd}" ]] && usage
shift

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

[[ -z "${organism}" ]] && usage

case "${cmd}" in
download)
    case "${chain}" in
    heavy) chains=(IGH) ;;
    kappa) chains=(IGK) ;;
    lambda) chains=(IGL) ;;
    all) chains=(IGH IGK IGL) ;;
    *)
        echo "error: --chain must be heavy|kappa|lambda|all" >&2
        exit 2
        ;;
    esac
    total=0
    for c in "${chains[@]}"; do
        outdir="data/raw/${organism}/${c}"
        for g in V D J; do
            file="${c}${g}.fasta"
            url="${base_url}/${organism}/IG/${file}"
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
    ;;
process)
    if ! command -v perl >/dev/null; then
        echo "error: perl is required but not found in PATH; make it available in your micromamba environment" >&2
        exit 1
    fi
    if [[ ! -d "data/raw/${organism}" ]]; then
        echo "error: no raw data for '${organism}'; run ${0} download first" >&2
        exit 1
    fi
    outdir="data/processed/${organism}"
    mkdir -p "${outdir}"
    shopt -s nullglob
    for region in V D J; do
        files=(data/raw/"${organism}"/*/*"${region}".fasta)
        [[ ${#files[@]} -eq 0 ]] && continue
        # NCBI IgBLAST workflow: combine all V, all D, all J into separate files,
        # then run edit_imgt_file.pl (rewrites IMGT deflines to germline gene names,
        # strips alignment dots)
        cat "${files[@]}" >"${outdir}/${region}.raw.tmp"
        perl "${script_dir}/edit_imgt_file.pl" "${outdir}/${region}.raw.tmp" >"${outdir}/${region}.fasta.tmp"
        mv "${outdir}/${region}.fasta.tmp" "${outdir}/${region}.fasta"
        rm "${outdir}/${region}.raw.tmp"
    done
    ;;
*)
    usage
    ;;
esac
