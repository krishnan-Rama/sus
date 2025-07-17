#!/usr/bin/env bash
# susceptibility.sh: Prototype CLI for species susceptibility screening
#
# Requirements:
#   • curl
#   • grep, head, mkdir, gunzip
#
# Usage:
#   ./susceptibility.sh -n atrazine

set -eo pipefail

# Default parameters
CHEM_NAME=""
CHEM_CAS=""
SPECIES="all"
NETWORK=false
VISUALIZE=false
SOURCES="all"

CTD_DIR="./ctd_data"
CTD_FILE="${CTD_DIR}/CTD_chem_gene_ixns.csv"
CTD_URL="http://ctdbase.org/reports/CTD_chem_gene_ixns.csv.gz"

# Print usage information
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -n, --name       Chemical name or synonym
  -c, --cas        CAS number
  -s, --species    Species name or taxon (default: all)
  -N, --network    Build gene network (placeholder)
  -v, --visualize  Generate visual output (placeholder)
  --sources        Comma-separated data sources (default: all)
  -h, --help       Show this help message and exit
EOF
  exit 1
}

# Parse arguments
tmp=$(getopt -o n:c:s:Nhv --long name:,cas:,species:,network,visualize,sources:,help -n 'susceptibility.sh' -- "$@")
[[ $? -ne 0 ]] && usage
eval set -- "$tmp"

while true; do
  case "$1" in
    -n|--name)      CHEM_NAME="$2"; shift 2;;
    -c|--cas)       CHEM_CAS="$2"; shift 2;;
    -s|--species)   SPECIES="$2"; shift 2;;
    -N|--network)   NETWORK=true; shift;;
    -v|--visualize) VISUALIZE=true; shift;;
    --sources)      SOURCES="$2"; shift 2;;
    -h|--help)      usage;;
    --)             shift; break;;
    *)              echo "Unexpected option: $1"; usage;;
  esac
done

# Require name or CAS
if [[ -z "$CHEM_NAME" && -z "$CHEM_CAS" ]]; then
  echo "Error: must supply a chemical name (-n) or CAS (-c)" >&2
  usage
fi

# 1) Resolve to PubChem CID
resolve_cid() {
  local query cid
  if [[ -n "$CHEM_CAS" ]]; then
    query="$CHEM_CAS"
    echo "Resolving PubChem CID for CAS $CHEM_CAS..."
  else
    query="$CHEM_NAME"
    echo "Resolving PubChem CID for name '$CHEM_NAME'..."
  fi

  cid=$(curl -L --fail "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/name/${query}/cids/TXT" \
        | head -n1)

  if [[ -z "$cid" ]]; then
    echo "Error: no CID found for '${query}'" >&2
    exit 2
  fi
  echo "$cid"
}

# 2) Ensure CTD CSV is present (downloads if missing)
ensure_ctd_csv() {
  if [[ ! -f "$CTD_FILE" ]]; then
    echo "Downloading CTD chem–gene CSV (~350 MB) from:"
    echo "  $CTD_URL"
    mkdir -p "$CTD_DIR"
    curl -L --fail -o "${CTD_FILE}.gz" "$CTD_URL"
    echo "Download complete; unpacking…"
    gunzip -f "${CTD_FILE}.gz"
    echo "CTD data ready at $CTD_FILE"
  fi
}

# 3) Fetch CTD interactions locally (first 20 matches), without spurious errors
fetch_ctd_local() {
  local query results
  query="$(echo "${CHEM_CAS:-$CHEM_NAME}" | tr '[:upper:]' '[:lower:]')"
  echo "Searching CTD CSV for '$query' (first 20 matches)…"

  # Capture up to 20 matching lines
  results=$(grep -vi '^#' "$CTD_FILE" \
            | grep -i "$query" \
            | head -n20 || true)

  if [[ -n "$results" ]]; then
    echo "$results"
  else
    echo "[No CTD rows found for '$query']"
  fi
}

# Main execution flow
main() {
  # Resolve CID
  CID=$(resolve_cid)
  echo "PubChem CID: $CID"
  echo

  # CTD (local CSV) integration
  if [[ "$SOURCES" =~ (^|,)(all|ctd)(,|$) ]]; then
    ensure_ctd_csv
    fetch_ctd_local
    echo
  fi

  # TODO: implement other fetch_* functions:
  #   • fetch_pubchem_properties "$CID"
  #   • fetch_chemspider "$CID"
  #   • fetch_aopwiki "$CID"
  #   • fetch_uniprot "$CID"
  #   • fetch_drugbank "$CID"
  #   • fetch_ecotox "$CID"
  #   • filter by species (e.g. grep species name)
  #   • network / visualization stubs

  if $NETWORK; then
    echo "[Network generation not yet implemented]"
  fi
  if $VISUALIZE; then
    echo "[Visualization not yet implemented]"
  fi
}

main

