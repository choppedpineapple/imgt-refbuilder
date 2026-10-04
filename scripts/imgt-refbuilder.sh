#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${script_dir}/.."

base_url="https://www.imgt.org/download/V-QUEST/IMGT_V-QUEST_reference_directory"

usage() {
    echo "usage: ${0} download --organism <name> --chain heavy|kappa|lambda|all [--curl <path>]" >&2
    echo "       ${0} process --organism <name> [--perl <path>]" >&2
    echo "       ${0} build --organism <name> [--makeblastdb <path>]" >&2
    echo "       ${0} test --organism <name> --query <fasta> [--igblastn <path>] [--igdata <path>]" >&2
    exit 2
}

cmd="${1:-}"
[[ -z "${cmd}" ]] && usage
shift

case "${cmd}" in
download)
    organism=""
    chain=""
    curl_bin=""
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
        --curl)
            curl_bin="${2:?missing value for --curl}"
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
    if [[ -n "${curl_bin}" ]]; then
        if [[ ! -x "${curl_bin}" ]]; then
            echo "error: not executable: ${curl_bin}" >&2
            exit 1
        fi
    elif curl_bin="$(command -v curl)"; then
        :
    else
        echo "error: curl not found in PATH; pass --curl <path>" >&2
        exit 1
    fi
    total=0
    for c in "${chains[@]}"; do
        outdir="data/raw/${organism}/${c}"
        for g in V D J; do
            file="${c}${g}.fasta"
            url="${base_url}/${organism}/IG/${file}"
            # not every organism has every chain/group (e.g. no IGK in Gallus_gallus)
            if [[ "$("${curl_bin}" -s -o /dev/null -w '%{http_code}' "${url}")" == "404" ]]; then
                echo "skipping ${file} (not available for ${organism})"
                continue
            fi
            mkdir -p "${outdir}"
            "${curl_bin}" -fsSL "${url}" -o "${outdir}/${file}.tmp"
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
    perl_bin=""
    while [[ ${#} -gt 0 ]]; do
        case "${1}" in
        --organism)
            organism="${2:?missing value for --organism}"
            shift 2
            ;;
        --perl)
            perl_bin="${2:?missing value for --perl}"
            shift 2
            ;;
        *)
            echo "unknown argument: ${1}" >&2
            exit 2
            ;;
        esac
    done
    [[ -z "${organism}" ]] && usage
    if [[ -n "${perl_bin}" ]]; then
        if [[ ! -x "${perl_bin}" ]]; then
            echo "error: not executable: ${perl_bin}" >&2
            exit 1
        fi
    elif perl_bin="$(command -v perl)"; then
        :
    else
        echo "error: perl not found in PATH; pass --perl <path>" >&2
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
        "${perl_bin}" "${script_dir}/edit_imgt_file.pl" "${outdir}/${region}.raw.tmp" >"${outdir}/${region}.fasta.tmp"
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
    elif makeblastdb_bin="$(command -v makeblastdb)"; then
        :
    else
        echo "error: makeblastdb not found in PATH; pass --makeblastdb <path>" >&2
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
        built=$((built + 1))
    done
    if [[ ${built} -eq 0 ]]; then
        echo "error: no processed V/D/J files for '${organism}'; run ${0} process first" >&2
        exit 1
    fi
    ;;
test)
    organism=""
    query=""
    igblastn_bin=""
    igdata=""
    while [[ ${#} -gt 0 ]]; do
        case "${1}" in
        --organism)
            organism="${2:?missing value for --organism}"
            shift 2
            ;;
        --query)
            query="${2:?missing value for --query}"
            shift 2
            ;;
        --igblastn)
            igblastn_bin="${2:?missing value for --igblastn}"
            shift 2
            ;;
        --igdata)
            igdata="${2:?missing value for --igdata}"
            shift 2
            ;;
        *)
            echo "unknown argument: ${1}" >&2
            exit 2
            ;;
        esac
    done
    [[ -z "${organism}" || -z "${query}" ]] && usage
    if [[ -n "${igblastn_bin}" ]]; then
        if [[ ! -x "${igblastn_bin}" ]]; then
            echo "error: not executable: ${igblastn_bin}" >&2
            exit 1
        fi
    elif igblastn_bin="$(command -v igblastn)"; then
        :
    else
        echo "error: igblastn not found in PATH; pass --igblastn <path>" >&2
        exit 1
    fi
    # IgBLAST has its own built-in organism set, independent of what IMGT provides
    case "${organism}" in
    Homo_sapiens) igblast_organism="human" ;;
    Mus_musculus) igblast_organism="mouse" ;;
    Rattus_norvegicus) igblast_organism="rat" ;;
    Oryctolagus_cuniculus) igblast_organism="rabbit" ;;
    Macaca_mulatta) igblast_organism="rhesus_monkey" ;;
    *)
        echo "error: '${organism}' is not a built-in IgBLAST organism; custom-organism annotation is not set up by this tool" >&2
        exit 1
        ;;
    esac
    igdata="${igdata:-${IGDATA:-}}"
    if [[ -z "${igdata}" ]]; then
        echo "error: IgBLAST data directory not found; pass --igdata <path> or set IGDATA" >&2
        exit 1
    fi
    if [[ ! -r "${query}" ]]; then
        echo "error: query not readable: ${query}" >&2
        exit 1
    fi
    aux="${igdata}/optional_file/${igblast_organism}_gl.aux"
    if [[ ! -f "${aux}" ]]; then
        echo "error: auxiliary data not found: ${aux}" >&2
        exit 1
    fi
    # D genes do not exist for every locus; V and J always do
    db_args=()
    for region in V J D; do
        if [[ -f "data/database/${organism}/${region}.nsq" ]]; then
            db_args+=("-germline_db_${region}" "data/database/${organism}/${region}")
        elif [[ "${region}" != "D" ]]; then
            echo "error: missing database data/database/${organism}/${region}; run ${0} build first" >&2
            exit 1
        fi
    done
    outdir="data/test/${organism}"
    mkdir -p "${outdir}"
    IGDATA="${igdata}" "${igblastn_bin}" "${db_args[@]}" -organism "${igblast_organism}" \
        -query "${query}" -auxiliary_data "${aux}" -out "${outdir}/igblast.out"
    if [[ ! -s "${outdir}/igblast.out" ]]; then
        echo "error: igblastn produced no output" >&2
        exit 1
    fi
    ;;
*)
    usage
    ;;
esac
