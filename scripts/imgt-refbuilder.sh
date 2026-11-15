#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${script_dir}/.."

base_url="https://www.imgt.org/download/V-QUEST/IMGT_V-QUEST_reference_directory"

stage_dir=""
active_rollback=""
cleanup_stage() {
    local rc=$?
    local dir="${stage_dir}"
    local rb="${active_rollback}"
    if [[ -n "${rb}" ]]; then
        active_rollback=""
        if ! "${rb}"; then
            echo "error: rollback failed; backup files preserved in ${dir}/backup" >&2
            stage_dir=""
            return 1
        fi
    fi
    stage_dir=""
    if [[ -n "${dir}" && -d "${dir}" ]]; then
        rm -rf "${dir}"
    fi
    return "${rc}"
}
trap cleanup_stage EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

validate_organism() {
    local org="${1}"
    if [[ ! "${org}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ || "${org}" == *..* ]]; then
        echo "error: --organism must be an IMGT directory name, not a path" >&2
        exit 2
    fi
}

check_safe_dir() {
    local path="${1}"
    local cur=""
    local part
    local -a parts
    IFS='/' read -ra parts <<<"${path}"
    for part in "${parts[@]}"; do
        [[ -z "${part}" ]] && continue
        cur="${cur:+${cur}/}${part}"
        if [[ -L "${cur}" ]]; then
            echo "error: refusing symlinked output path: ${cur}" >&2
            exit 1
        fi
        if [[ -e "${cur}" && ! -d "${cur}" ]]; then
            echo "error: expected directory at ${cur}" >&2
            exit 1
        fi
    done
}

check_safe_file() {
    local path="${1}"
    if [[ -L "${path}" ]]; then
        echo "error: refusing symlinked output file: ${path}" >&2
        exit 1
    fi
    if [[ -e "${path}" && ! -f "${path}" ]]; then
        echo "error: expected regular file at ${path}" >&2
        exit 1
    fi
}

validate_fasta() {
    local fasta="${1}"
    [[ -s "${fasta}" ]] || return 1
    awk '
        BEGIN { headers = 0; has_seq = 0; bad = 0 }
        /^[[:space:]]*$/ { next }
        /^>/ {
            if (headers > 0 && !has_seq) { bad = 1; exit 1 }
            if ($0 ~ /^>[[:space:]]*$/) { bad = 1; exit 1 }
            headers++
            has_seq = 0
            next
        }
        {
            if (headers == 0 || $0 ~ /^[[:space:]]*</) { bad = 1; exit 1 }
            has_seq = 1
        }
        END {
            if (bad || headers == 0 || !has_seq) exit 1
        }
    ' "${fasta}"
}

usage() {
    echo "usage: ${0} download --organism <name> --chain heavy|kappa|lambda|all [--curl <path>]" >&2
    echo "       ${0} process --organism <name> [--edit-imgt-file <path>] [--perl <path>]" >&2
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
    validate_organism "${organism}"
    check_safe_dir "data/raw/${organism}"
    # IMGT names files <group><region>.fasta, e.g. IGHV.fasta, IGIJ.fasta
    case "${chain}" in
    heavy) groups='IGH' ;;
    kappa) groups='IGK' ;;
    lambda) groups='IGL' ;;
    all) groups='IG[A-Z]+' ;;
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
    ig_url="${base_url}/${organism}/IG"
    # the status code is appended to the page so a 404 can be told apart from a network failure
    listing="$("${curl_bin}" -sSL -w '%{http_code}' "${ig_url}/")" || {
        echo "error: could not fetch ${ig_url}/" >&2
        exit 1
    }
    status="${listing: -3}"
    if [[ "${status}" == "404" ]]; then
        echo "error: IMGT has no IG reference data for '${organism}' (TR-only entries are not supported; check the name against the IMGT reference directory)" >&2
        exit 1
    elif [[ "${status}" != "200" || "${listing}" != *"Index of "* ]]; then
        echo "error: unexpected response (HTTP ${status}) from ${ig_url}/" >&2
        exit 1
    fi
    # files from an earlier download are re-requested too, so anything IMGT has dropped gets a 404 below
    shopt -s nullglob
    old_files=(data/raw/"${organism}"/IG*/*.fasta)
    mapfile -t files < <(
        {
            grep -oE 'href="[^"/]+"' <<<"${listing}" | cut -d'"' -f2
            printf '%s\n' "${old_files[@]##*/}"
        } | grep -E "^${groups}[VDJ]\.fasta$" | sort -u
    )
    mkdir -p data/raw
    stage_dir="$(mktemp -d "data/raw/.download.${organism}.XXXXXX")"
    to_remove=()
    total=0
    for file in "${files[@]}"; do
        group="${file%?.fasta}"
        tmp="${stage_dir}/${file}"
        status="$("${curl_bin}" -sSL -o "${tmp}" -w '%{http_code}' "${ig_url}/${file}")" || {
            echo "error: could not fetch ${ig_url}/${file}" >&2
            exit 1
        }
        if [[ "${status}" == "404" ]]; then
            rm -f "${tmp}"
            if [[ -f "data/raw/${organism}/${group}/${file}" ]]; then
                to_remove+=("data/raw/${organism}/${group}/${file}")
            fi
            continue
        fi
        if [[ "${status}" != "200" ]] || ! validate_fasta "${tmp}"; then
            echo "error: HTTP ${status} or not a FASTA: ${ig_url}/${file}" >&2
            exit 1
        fi
        mkdir -p "${stage_dir}/${group}"
        mv "${tmp}" "${stage_dir}/${group}/${file}"
        total=$((total + 1))
    done
    if [[ ${total} -eq 0 && ${#to_remove[@]} -eq 0 ]]; then
        echo "error: no IG reference FASTA at IMGT for '${organism}' with --chain ${chain}" >&2
        exit 1
    fi
    # preflight every stale-file and staged-output path before mutating anything
    for old in "${to_remove[@]}"; do
        check_safe_dir "${old%/*}"
        check_safe_file "${old}"
    done
    staged_files=("${stage_dir}"/*/*.fasta)
    for staged in "${staged_files[@]}"; do
        group="${staged%/*}"
        group="${group##*/}"
        file="${staged##*/}"
        outdir="data/raw/${organism}/${group}"
        check_safe_dir "${outdir}"
        check_safe_file "${outdir}/${file}"
    done
    # publish with backup-and-rollback after all downloads and preflight checks pass
    backup_dir="${stage_dir}/backup"
    mkdir -p "${backup_dir}"
    moved_new=()
    rollback_download() {
        local f grp rc=0
        for f in "${moved_new[@]}"; do
            rm -f "${f}" || rc=1
        done
        for f in "${backup_dir}"/*/*.fasta; do
            grp="${f%/*}"
            grp="${grp##*/}"
            mkdir -p "data/raw/${organism}/${grp}" || {
                rc=1
                continue
            }
            mv -f "${f}" "data/raw/${organism}/${grp}/${f##*/}" || rc=1
        done
        return "${rc}"
    }
    active_rollback="rollback_download"
    for old in "${to_remove[@]}"; do
        group="${old%/*}"
        group="${group##*/}"
        mkdir -p "${backup_dir}/${group}"
        mv "${old}" "${backup_dir}/${group}/${old##*/}"
    done
    if [[ ${#staged_files[@]} -gt 0 ]]; then
        mkdir -p "data/raw/${organism}"
    fi
    for staged in "${staged_files[@]}"; do
        group="${staged%/*}"
        group="${group##*/}"
        file="${staged##*/}"
        outdir="data/raw/${organism}/${group}"
        mkdir -p "${outdir}"
        if [[ -f "${outdir}/${file}" ]]; then
            mkdir -p "${backup_dir}/${group}"
            mv "${outdir}/${file}" "${backup_dir}/${group}/${file}"
        fi
        mv "${staged}" "${outdir}/${file}"
        moved_new+=("${outdir}/${file}")
    done
    for old in "${to_remove[@]}"; do
        echo "removed ${old} (no longer at IMGT)"
        rmdir "${old%/*}" 2>/dev/null || true
    done
    rmdir "data/raw/${organism}" 2>/dev/null || true
    active_rollback=""
    cleanup_stage
    if [[ ${total} -eq 0 ]]; then
        echo "error: no IG reference FASTA currently at IMGT for '${organism}' with --chain ${chain}" >&2
        exit 1
    fi
    ;;
process)
    organism=""
    edit_imgt_file=""
    perl_bin=""
    while [[ ${#} -gt 0 ]]; do
        case "${1}" in
        --organism)
            organism="${2:?missing value for --organism}"
            shift 2
            ;;
        --edit-imgt-file)
            edit_imgt_file="${2:?missing value for --edit-imgt-file}"
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
    validate_organism "${organism}"
    check_safe_dir "data/processed/${organism}"
    if [[ -z "${edit_imgt_file}" ]] && ! edit_imgt_file="$(command -v edit_imgt_file.pl)"; then
        echo "error: edit_imgt_file.pl not found in PATH; pass --edit-imgt-file <path> (it ships with the NCBI IgBLAST release)" >&2
        exit 1
    fi
    if [[ ! -f "${edit_imgt_file}" || ! -r "${edit_imgt_file}" ]]; then
        echo "error: cannot read edit_imgt_file.pl: ${edit_imgt_file}" >&2
        exit 1
    fi
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
    shopt -s nullglob
    raw=()
    for f in data/raw/"${organism}"/IG*/IG*[VDJ].fasta; do
        group="${f%/*}"
        group="${group##*/}"
        [[ "${group}" =~ ^IG[A-Z]+$ && "${f##*/}" =~ ^${group}[VDJ]\.fasta$ ]] && raw+=("${f}")
    done
    if [[ ${#raw[@]} -eq 0 ]]; then
        echo "error: no raw IG FASTA for '${organism}'; run ${0} download first" >&2
        exit 1
    fi
    mkdir -p data/processed
    stage_dir="$(mktemp -d "data/processed/.process.${organism}.XXXXXX")"
    for region in V D J; do
        files=()
        for f in data/raw/"${organism}"/IG*/IG*"${region}".fasta; do
            group="${f%/*}"
            group="${group##*/}"
            [[ "${group}" =~ ^IG[A-Z]+$ && "${f##*/}" == "${group}${region}.fasta" ]] && files+=("${f}")
        done
        [[ ${#files[@]} -eq 0 ]] && continue
        # NCBI workflow: combine each region, then edit_imgt_file.pl fixes the IMGT deflines
        cat "${files[@]}" >"${stage_dir}/${region}.raw"
        "${perl_bin}" "${edit_imgt_file}" "${stage_dir}/${region}.raw" >"${stage_dir}/${region}.fasta"
        rm -f "${stage_dir}/${region}.raw"
        if ! validate_fasta "${stage_dir}/${region}.fasta"; then
            echo "error: processed ${region} FASTA is empty or invalid for '${organism}'" >&2
            exit 1
        fi
    done
    outdir="data/processed/${organism}"
    check_safe_dir "${outdir}"
    for region in V D J; do
        check_safe_file "${outdir}/${region}.fasta"
    done
    mkdir -p "${outdir}"
    backup_dir="${stage_dir}/backup"
    mkdir -p "${backup_dir}"
    moved_new=()
    rollback_process() {
        local f rc=0
        for f in "${moved_new[@]}"; do
            rm -f "${f}" || rc=1
        done
        for f in "${backup_dir}"/*.fasta; do
            mv -f "${f}" "${outdir}/${f##*/}" || rc=1
        done
        return "${rc}"
    }
    active_rollback="rollback_process"
    for region in V D J; do
        if [[ -f "${outdir}/${region}.fasta" ]]; then
            mv "${outdir}/${region}.fasta" "${backup_dir}/${region}.fasta"
        fi
        if [[ -f "${stage_dir}/${region}.fasta" ]]; then
            mv "${stage_dir}/${region}.fasta" "${outdir}/${region}.fasta"
            moved_new+=("${outdir}/${region}.fasta")
        fi
    done
    active_rollback=""
    cleanup_stage
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
    validate_organism "${organism}"
    if [[ -n "${makeblastdb_bin}" ]]; then
        if [[ ! -x "${makeblastdb_bin}" ]]; then
            echo "error: not executable: ${makeblastdb_bin}" >&2
            exit 1
        fi
    # Bioconda's igblast package installs makeblastdb under the name makeigblastdb
    elif makeblastdb_bin="$(command -v makeblastdb || command -v makeigblastdb)"; then
        :
    else
        echo "error: neither makeblastdb nor makeigblastdb found in PATH; pass --makeblastdb <path> (either works)" >&2
        exit 1
    fi
    indir="data/processed/${organism}"
    outdir="data/database/${organism}"
    check_safe_dir "${outdir}"
    shopt -s nullglob
    processed=("${indir}"/[VDJ].fasta)
    if [[ ${#processed[@]} -eq 0 ]]; then
        echo "error: no processed V/D/J files for '${organism}'; run ${0} process first" >&2
        exit 1
    fi
    mkdir -p data/database
    stage_dir="$(mktemp -d "data/database/.build.${organism}.XXXXXX")"
    for region in V D J; do
        [[ -f "${indir}/${region}.fasta" ]] || continue
        "${makeblastdb_bin}" -parse_seqids -dbtype nucl -in "${indir}/${region}.fasta" -out "${stage_dir}/${region}"
        if [[ ! -s "${stage_dir}/${region}.nsq" || ! -s "${stage_dir}/${region}.nhr" || ! -s "${stage_dir}/${region}.nin" ]]; then
            echo "error: ${makeblastdb_bin} did not produce expected database files for ${organism} ${region}" >&2
            exit 1
        fi
    done
    # preflight destination directory and all existing/target database files before mutating anything
    check_safe_dir "${outdir}"
    for region in V D J; do
        for f in "${outdir}/${region}".n??; do
            check_safe_file "${f}"
        done
        for f in "${stage_dir}/${region}".n??; do
            check_safe_file "${outdir}/${f##*/}"
        done
    done
    # publish with backup-and-rollback only after every available region database builds and validates
    mkdir -p "${outdir}"
    backup_dir="${stage_dir}/backup"
    mkdir -p "${backup_dir}"
    moved_new=()
    rollback_build() {
        local f rc=0
        for f in "${moved_new[@]}"; do
            rm -f "${f}" || rc=1
        done
        for f in "${backup_dir}"/*; do
            mv -f "${f}" "${outdir}/${f##*/}" || rc=1
        done
        return "${rc}"
    }
    active_rollback="rollback_build"
    for region in V D J; do
        # <region>.n?? covers the files of a BLAST nucleotide database
        for f in "${outdir}/${region}".n??; do
            mv "${f}" "${backup_dir}/${f##*/}"
        done
        for f in "${stage_dir}/${region}".n??; do
            mv "${f}" "${outdir}/${f##*/}"
            moved_new+=("${outdir}/${f##*/}")
        done
    done
    active_rollback=""
    cleanup_stage
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
    check_safe_dir "${outdir}"
    if [[ -L "${outdir}/igblast.out" ]]; then
        echo "error: refusing symlinked output file: ${outdir}/igblast.out" >&2
        exit 1
    fi
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
