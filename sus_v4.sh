#!/usr/bin/env bash
set -euo pipefail

# —— Config & defaults ——
CHEM_NAME=""
CHEM_CAS=""
SPECIES="all"
CTD_DIR="./ctd_data"
CTD_FILE="${CTD_DIR}/CTD_chem_gene_ixns.csv"
CTD_URL="https://ctdbase.org/reports/CTD_chem_gene_ixns.csv.gz"
HTML_OUT="network.html"

# —— Flags: allow pre-filter by name, CAS, and species ——
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--name)    CHEM_NAME="$2"; shift 2;;
    -c|--cas)     CHEM_CAS="$2";  shift 2;;
    -s|--species) SPECIES="$2";   shift 2;;
    *) break;;
  esac
done

# build query
q="${CHEM_CAS:-$CHEM_NAME}"

# —— PubChem CID lookup ——
if [[ -n "$q" ]]; then
  cid=$(curl -sL "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/name/${q}/cids/TXT" | head -n1)
else
  cid="(all)"
fi

# —— Download CTD data once ——
mkdir -p "$CTD_DIR"
if [[ ! -f "$CTD_FILE" ]]; then
  curl -sL -o "${CTD_FILE}.gz" "$CTD_URL"
  gunzip -f "${CTD_FILE}.gz"
fi

# —— Filter lines by chemical + species ——
mapfile -t lines < <(
  grep -vi '^#' "$CTD_FILE" |
  ( [[ -n "$q" ]] && grep -i -- "$(echo "$q" | tr '[:upper:]' '[:lower:]')" || cat ) |
  ( [[ "$SPECIES" == "all" ]] && cat || grep -i -- ",$(echo "$SPECIES" | tr '[:upper:]' '[:lower:]')," )
)

# —— Emit HTML header ——
cat > "$HTML_OUT" <<EOF
<!doctype html>
<html><head><meta charset="utf-8">
  <title>SUS-Pecies: Susceptible Species & Gene Interactions</title>
  <link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css">
  <style>
    .badge {display:inline-block;padding:0.25em 0.6em;font-size:75%;border-radius:0.25rem;color:#fff;}
    .increase {background-color:#28a745;}
    .decrease {background-color:#dc3545;}
    .other    {background-color:#6c757d;}
    #filters {margin-bottom:1em;}
    #filters select {margin-right:1em;}
  </style>
</head><body>
  <h1>${CHEM_NAME:-All Chemicals} Susceptibility (${SPECIES})</h1>
  <p>PubChem CID: ${cid}</p>
  <div id="filters">
    <label>Species:
      <select id="spFilter"><option value="">(all)</option></select>
    </label>
    <label>Chemical:
      <select id="chemFilter"><option value="">(all)</option></select>
    </label>
  </div>
  <table id="susTable" class="display" style="width:100%">
    <thead><tr>
      <th>Chemical</th><th>Species</th><th>Gene</th><th>Interaction</th><th>PMID</th>
    </tr></thead>
    <tbody>
EOF

# —— Populate rows: gene from col4, species from col7 ——
for line in "${lines[@]}"; do
  chem=$(awk -F, '{c=$1; gsub(/"/,"",c); print c}' <<<"$line")
  gene=$(awk -F, '{g=$4; gsub(/"/,"",g); print g}' <<<"$line")
  species=$(awk -F, '{s=$7; gsub(/"/,"",s); print s}' <<<"$line")
  types=$(cut -d, -f10 <<<"$line")
  pmid=$(cut -d, -f11 <<<"$line" | tr -d '"')

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

  # emit row
  cat >> "$HTML_OUT" <<ROW
    <tr>
      <td>${chem}</td>
      <td>${species}</td>
      <td>${gene}</td>
      <td>${badges}</td>
      <td><a href="https://pubmed.ncbi.nlm.nih.gov/${pmid}" target="_blank">${pmid}</a></td>
    </tr>
ROW
done

# —— Finish HTML & DataTables scripting ——
cat >> "$HTML_OUT" <<'EOF'
    </tbody>
  </table>
  <script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
  <script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
  <script>
    $(function(){
      var table = $('#susTable').DataTable({
        pageLength:10,
        lengthMenu:[5,10,20,50],
        columns:[null,null,null,{orderable:false},null]
      });
      table.column(0).data().unique().sort().each(function(d){
        $('#chemFilter').append($('<option>').val(d).text(d));
      });
      table.column(1).data().unique().sort().each(function(d){
        $('#spFilter').append($('<option>').val(d).text(d));
      });
      $('#chemFilter').on('change', function(){ table.column(0).search(this.value).draw(); });
      $('#spFilter').on('change',  function(){ table.column(1).search(this.value).draw(); });
    });
  </script>
</body>
</html>
EOF

# done
echo "Interactive HTML table saved to $HTML_OUT"
