#!/usr/bin/env bash
set -euo pipefail

CHEM_NAME=""
CHEM_CAS=""
SPECIES="all"
CTD_DIR="./ctd_data"
CTD_FILE="${CTD_DIR}/CTD_chem_gene_ixns.csv"
CTD_URL="https://ctdbase.org/reports/CTD_chem_gene_ixns.csv.gz"
HTML_OUT="network.html"

while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--name)      CHEM_NAME="$2"; shift 2;;
    -c|--cas)       CHEM_CAS="$2";   shift 2;;
    -s|--species)   SPECIES="$2";    shift 2;;
    *) break;;
  esac
done

q="${CHEM_CAS:-$CHEM_NAME}"
cid=$(curl -sL "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/name/${q}/cids/TXT" | head -n1)

mkdir -p "$CTD_DIR"
if [[ ! -f "$CTD_FILE" ]]; then
  curl -sL -o "${CTD_FILE}.gz" "$CTD_URL"
  gunzip -f "${CTD_FILE}.gz"
fi

mapfile -t lines < <(
  grep -vi '^#' "$CTD_FILE" \
  | grep -i -- "$(echo "$q" | tr '[:upper:]' '[:lower:]')" \
  | ( [[ "$SPECIES" == all ]] && cat || grep -i ",$(echo "$SPECIES"|tr '[:upper:]' '[:lower:]')," )
)

cat > "$HTML_OUT" <<EOF
<!doctype html>
<html><head><meta charset="utf-8">
<link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css">
<style>
  .badge {display:inline-block;padding:0.25em 0.6em;font-size:75%;border-radius:0.25rem;color:#fff;}
  .increase {background-color:#28a745;}
  .decrease {background-color:#dc3545;}
  .other {background-color:#6c757d;}
</style>
</head><body>
<h1>${CHEM_NAME} Susceptibility (${SPECIES})</h1>
<p>PubChem CID: ${cid}</p>
<table id="susTable" class="display" style="width:100%">
  <thead><tr><th>Gene</th><th>Interaction</th><th>PMID</th></tr></thead>
  <tbody>
EOF

for line in "${lines[@]}"; do
  gene=$(awk -F, '{g=$4; gsub(/"/,"",g); print g}' <<< "$line")
  types=$(cut -d',' -f10 <<< "$line")
  pmid=$(cut -d',' -f11 <<< "$line")
  # build badges
  badges=""
  IFS='|' read -ra arr <<< "$types"
  for t in "${arr[@]}"; do
    cls=other
    [[ "$t" == increases* ]] && cls=increase
    [[ "$t" == decreases* ]] && cls=decrease
    txt=${t//^/ }
    badges+="<span class=\"badge ${cls}\">${txt}</span> "
  done
  echo "  <tr><td>${gene}</td><td>${badges}</td><td><a href=\"https://pubmed.ncbi.nlm.nih.gov/${pmid}\" target=\"_blank\">${pmid}</a></td></tr>" >> "$HTML_OUT"
done

cat >> "$HTML_OUT" <<'EOF'
  </tbody>
</table>
<script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
<script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
<script>
$(document).ready(function(){
  $('#susTable').DataTable({
    pageLength: 10,
    lengthMenu: [5,10,20,50],
    columns: [null, {orderable:false}, null]
  });
});
</script>
</body></html>
EOF

echo "Interactive HTML table saved to $HTML_OUT"

