#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${script_dir}/.."

base_url="https://www.imgt.org/download/V-QUEST/IMGT_V-QUEST_reference_directory"

usage() {
    echo "usage: ${0} download --organism <name> --chain heavy|kappa|lambda|all" >&2
    echo "       ${0} process --organism <name>" >&2
    echo "       ${0} build --organism <name> [--makeblastdb <path>]" >&2
    exit 2
}

cmd="${1:-}"
[[ -z "${cmd}" ]] && usage
shift

case "${cmd}" in
download)
    organism=""
    chain=""
    while [[ ${#} -gt 0 ]]; do
        case "${1}" in
        --organism)
            organism="${2:?missing value for --organism}"
            shift 2
            ;;
        --chain)
            chain="${2:?missing value for --chain}"
            shift 2
            ;;
        *)
            echo "unknown argument: ${1}" >&2
            exit 2
            ;;
        esac
    done
    [[ -z "${organism}" ]] && usage
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
    organism=""
    while [[ ${#} -gt 0 ]]; do
        case "${1}" in
        --organism)
            organism="${2:?missing value for --organism}"
            shift 2
            ;;
        *)
            echo "unknown argument: ${1}" >&2
            exit 2
            ;;
        esac
    done
    [[ -z "${organism}" ]] && usage
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
build)
    organism=""
    makeblastdb_bin=""
    while [[ ${#} -gt 0 ]]; do
        case "${1}" in
        --organism)
            organism="${2:?missing value for --organism}"
            shift 2
            ;;
        --makeblastdb)
            makeblastdb_bin="${2:?missing value for --makeblastdb}"
            shift 2
            ;;
        *)
            echo "unknown argument: ${1}" >&2
            exit 2
            ;;
        esac
    done
    [[ -z "${organism}" ]] && usage
    if [[ -n "${makeblastdb_bin}" ]]; then
        if [[ ! -x "${makeblastdb_bin}" ]]; then
            echo "error: not executable: ${makeblastdb_bin}" >&2
            exit 1
        fi
    elif command -v makeblastdb >/dev/null; then
        makeblastdb_bin="makeblastdb"
    else
        echo "error: makeblastdb not found in PATH; activate your micromamba environment or pass --makeblastdb <path>" >&2
        exit 1
    fi
    indir="data/processed/${organism}"
    outdir="data/database/${organism}"
    built=0
    for region in V D J; do
        [[ -f "${indir}/${region}.fasta" ]] || continue
        # build into a temp dir so a failed run never leaves a half-written database
        tmpdir="${outdir}/.build.${region}"
        rm -rf "${tmpdir}"
        mkdir -p "${tmpdir}"
        "${makeblastdb_bin}" -parse_seqids -dbtype nucl -in "${indir}/${region}.fasta" -out "${tmpdir}/${region}" || {
            rm -rf "${tmpdir}"
            exit 1
        }
        mv "${tmpdir}"/* "${outdir}"/
        rmdir "${tmpdir}"
        # smoke-check the database when blastdbcmd is available (not required)
        blastdbcmd_bin="$(dirname "${makeblastdb_bin}")/blastdbcmd"
        if [[ ! -x "${blastdbcmd_bin}" ]]; then
            blastdbcmd_bin="$(command -v blastdbcmd || true)"
        fi
        if [[ -n "${blastdbcmd_bin}" ]]; then
            "${blastdbcmd_bin}" -db "${outdir}/${region}" -info >/dev/null
        fi
        built=$((built + 1))
    done
    if [[ ${built} -eq 0 ]]; then
        echo "error: no processed V/D/J files for '${organism}'; run ${0} process first" >&2
        exit 1
    fi
    ;;
*)
    usage
    ;;
esac
