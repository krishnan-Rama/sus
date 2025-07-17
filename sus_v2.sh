#!/usr/bin/env bash
# susceptibility.sh: Comprehensive CLI for species susceptibility screening
#
# Requirements:
#   • curl, jq, grep, head, mkdir, gunzip
#
# Usage:
#   ./susceptibility.sh [options]

set -eo pipefail

# Default parameters
CHEM_NAME=""
CHEM_CAS=""
SPECIES="all"
NETWORK=false
VISUALIZE=false
SOURCES="all"

# CTD local data configuration
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
  -N, --network    Build gene network (stub)
  -v, --visualize  Generate visual output (stub)
  --sources        Comma-separated data sources (default: all)
  -h, --help       Show this help message and exit
EOF
  exit 1
}

# Parse arguments
ARGS=$(getopt -o n:c:s:Nhv --long name:,cas:,species:,network,visualize,sources:,help -n 'susceptibility.sh' -- "$@") || usage
eval set -- "$ARGS"
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

# Require chemical input
if [[ -z "$CHEM_NAME" && -z "$CHEM_CAS" ]]; then
  echo "Error: must supply a chemical name (-n) or CAS (-c)" >&2
  usage
fi

# 1) Resolve to PubChem CID
resolve_cid() {
  local query cid
  query="${CHEM_CAS:-$CHEM_NAME}"
  echo "Resolving PubChem CID for '$query'..."
  cid=$(curl -L --fail "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/name/${query}/cids/TXT" \
        | head -n1)
  if [[ -z "$cid" ]]; then
    echo "Error: no CID found for '$query'" >&2
    exit 2
  fi
  echo "$cid"
}

# 2) Ensure CTD CSV is present
ensure_ctd_csv() {
  if [[ ! -f "$CTD_FILE" ]]; then
    echo "Downloading CTD chem–gene CSV (~350 MB)..."
    mkdir -p "$CTD_DIR"
    curl -L --fail -o "${CTD_FILE}.gz" "$CTD_URL"
    echo "Download complete; unpacking..."
    gunzip -f "${CTD_FILE}.gz"
    echo "CTD data ready at $CTD_FILE"
  fi
}

# 3) Fetch CTD interactions (first 20 matches)
fetch_ctd() {
  ensure_ctd_csv
  local query results
  query=$(echo "${CHEM_CAS:-$CHEM_NAME}" | tr '[:upper:]' '[:lower:]')
  echo "CTD: searching for '$query' (first 20 matches)..."
  results=$(grep -vi '^#' "$CTD_FILE" | grep -i "$query" | head -n20 || true)
  if [[ -n "$results" ]]; then
    echo "$results"
  else
    echo "[CTD: no results for '$query']"
  fi
}

# 4) Fetch PubChem properties
fetch_pubchem_props() {
  local cid="$1"
  echo "PubChem: fetching properties for CID $cid..."
  curl -sL "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/${cid}/property/MolecularFormula,MolecularWeight,CanonicalSMILES/JSON" \
    | jq -r '.PropertyTable.Properties[] | "Formula: \(.MolecularFormula), MW: \(.MolecularWeight), SMILES: \(.CanonicalSMILES)"'
}

# 5) Fetch ChemSpider details (stub)
fetch_chemspider() {
  if [[ -z "$CHEMSPIDER_API_KEY" ]]; then
    echo "ChemSpider: SKIPPED (set CHEMSPIDER_API_KEY in env)"
  else
    echo "ChemSpider integration not implemented"
  fi
}

# 6) Fetch AOP-Wiki entries
fetch_aopwiki() {
  echo "AOP-Wiki: fetching AOP entries for '${CHEM_NAME}'..."
  curl -sL "https://aopwiki.org/api/v1/search/aop?q=${CHEM_NAME}" \
    | jq -r '.results[] | "AOP [\(.id)]: \(.title) (https://aopwiki.org/aops/\(.id))"'
}

# 7) Fetch UniProt orthologs (stub)
fetch_uniprot() {
  echo "UniProt: integration not implemented"
}

# 8) Fetch DrugBank targets (stub)
fetch_drugbank() {
  if [[ -z "$DRUGBANK_API_KEY" ]]; then
    echo "DrugBank: SKIPPED (set DRUGBANK_API_KEY in env)"
  else
    echo "DrugBank integration not implemented"
  fi
}

# 9) Fetch ECOTOX endpoints (stub)
fetch_ecotox() {
  echo "ECOTOX: integration not implemented"
}

# 10) Filter CTD results by species
filter_species() {
  local species_lower
  species_lower=$(echo "$SPECIES" | tr '[:upper:]' '[:lower:]')
  echo "Filtering CTD results for species: '$SPECIES'..."
  echo "$1" | grep -i ",${species_lower}," || echo "[No CTD rows match species: $SPECIES]"
}

# 11) Build gene network (stub)
build_network() {
  echo "Network generation not implemented"
}

# 12) Visualization (stub)
visualize() {
  echo "Visualization not implemented"
}

# Main execution flow
main() {
  local cid ctd_output

  # 1) Resolve CID
  cid=$(resolve_cid)
  echo "CID: $cid"
  echo

  # 2) CTD data
  if [[ "$SOURCES" =~ (^|,)(all|ctd)(,|$) ]]; then
    ctd_output=$(fetch_ctd)
    echo "$ctd_output"
    echo
  fi

  # 3) PubChem properties
  if [[ "$SOURCES" =~ (^|,)(all|pubchem)(,|$) ]]; then
    fetch_pubchem_props "$cid"
    echo
  fi

  # 4) ChemSpider
  if [[ "$SOURCES" =~ (^|,)(all|chemspider)(,|$) ]]; then
    fetch_chemspider
    echo
  fi

  # 5) AOP-Wiki
  if [[ "$SOURCES" =~ (^|,)(all|aopwiki)(,|$) ]]; then
    fetch_aopwiki
    echo
  fi

  # 6) UniProt
  if [[ "$SOURCES" =~ (^|,)(all|uniprot)(,|$) ]]; then
    fetch_uniprot
    echo
  fi

  # 7) DrugBank
  if [[ "$SOURCES" =~ (^|,)(all|drugbank)(,|$) ]]; then
    fetch_drugbank
    echo
  fi

  # 8) ECOTOX
  if [[ "$SOURCES" =~ (^|,)(all|ecotox)(,|$) ]]; then
    fetch_ecotox
    echo
  fi

  # 9) Species filter
  if [[ -n "$SPECIES" && "$SPECIES" != "all" ]]; then
    filter_species "$ctd_output"
    echo
  fi

  # 10) Network & visualization
  $NETWORK && build_network && echo
  $VISUALIZE && visualize && echo
}

main
