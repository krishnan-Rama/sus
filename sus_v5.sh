#!/usr/bin/env bash
set -euo pipefail

# —— CONFIGURATION ——
CTD_DIR="./ctd_data"
CTD_FILE="$CTD_DIR/CTD_chem_gene_ixns.csv"
CTD_URL="https://ctdbase.org/reports/CTD_chem_gene_ixns.csv.gz"
HTML_OUT="network.html"
GENES_DIR="genes"

# —— USER OPTIONS ——
CHEM_NAME=""; CHEM_CAS=""; SPECIES="all"
LIST_CHEMS=false; COUNT_CHEMS=false
LIST_SPECIES=false; COUNT_SPECIES=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--name)        CHEM_NAME="$2";       shift 2;;
    -c|--cas)         CHEM_CAS="$2";        shift 2;;
    -s|--species)     SPECIES="$2";         shift 2;;
    --list-chems)     LIST_CHEMS=true;      shift;;
    --count-chems)    COUNT_CHEMS=true;     shift;;
    --list-species)   LIST_SPECIES=true;    shift;;
    --count-species)  COUNT_SPECIES=true;   shift;;
    *) break;;
  esac
done

# —— FETCH CTD IF NECESSARY ——
mkdir -p "$CTD_DIR"
if [[ ! -f "$CTD_FILE" ]]; then
  curl -sL -o "${CTD_FILE}.gz" "$CTD_URL"
  gunzip -f "${CTD_FILE}.gz"
fi

# —— DETECT COLUMNS FROM HEADER ——
header=$(head -n1 "$CTD_FILE" | tr -d '"')
IFS=, read -ra cols <<< "$header"
# defaults
chem_col=1; org_col=7; gene_col=4
int_col=9; acts_col=10; pmid_col=11
for i in "${!cols[@]}"; do
  fld="${cols[i],,}"
  [[ "$fld" =~ chemicalname       ]] && chem_col=$((i+1))
  [[ "$fld" =~ organism|species   ]] && org_col=$((i+1))
  [[ "$fld" =~ genesymbol         ]] && gene_col=$((i+1))
  [[ "$fld" =~ interaction$       ]] && int_col=$((i+1))
  [[ "$fld" =~ interactionactions ]] && acts_col=$((i+1))
  [[ "$fld" =~ pubmedids          ]] && pmid_col=$((i+1))
done

# —— QUICK LIST/COUNT FLAGS ——
# (skip header + #comments, cut the detected column, uniq or count)
if $LIST_CHEMS; then
  tail -n +2 "$CTD_FILE" | grep -v '^#' \
    | cut -d, -f"$chem_col" | tr -d '"' | sort -u
  exit 0
fi
if $COUNT_CHEMS; then
  tail -n +2 "$CTD_FILE" | grep -v '^#' \
    | cut -d, -f"$chem_col" | tr -d '"' | sort -u | wc -l
  exit 0
fi
if $LIST_SPECIES; then
  tail -n +2 "$CTD_FILE" | grep -v '^#' \
    | cut -d, -f"$org_col" | tr -d '"' | sort -u
  exit 0
fi
if $COUNT_SPECIES; then
  tail -n +2 "$CTD_FILE" | grep -v '^#' \
    | cut -d, -f"$org_col" | tr -d '"' | sort -u | wc -l
  exit 0
fi

# —— LOOK UP PUBCHEM CID ——
query="${CHEM_CAS:-$CHEM_NAME}"
if [[ -n "$query" ]]; then
  cid=$(curl -sL "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/name/${query}/cids/TXT" \
        | head -n1)
else
  cid="(all)"
fi

# —— FILTER CTD ROWS INTO ARRAY ——
mapfile -t rows < <(
  tail -n +2 "$CTD_FILE" \
    | grep -v '^#' \
    | { [[ -n "$query" ]] && grep -i "$(echo "$query"|tr A-Z a-z)" || cat; } \
    | { [[ "$SPECIES" == "all" ]] && cat || grep -i ",$(echo "$SPECIES"|tr A-Z a-z),"; }
)

# —— COLLECT UNIQUE GENES ——
mapfile -t unique_genes < <(
  printf '%s\n' "${rows[@]}" \
    | cut -d, -f"$gene_col" | tr -d '"' | sort -u
)

# —— WRITE network.html ——
cat > "$HTML_OUT" <<EOF
<!doctype html>
<html><head><meta charset="utf-8">
  <title>SUS-Pecies: Susceptible Species & Gene Interactions</title>
  <link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css">
  <style>
    .badge{display:inline-block;padding:.25em .6em;font-size:75%;border-radius:.25rem;color:#fff;}
    .increase{background:#28a745;} .decrease{background:#dc3545;} .other{background:#6c757d;}
    #filters{margin-bottom:1em;} #filters select{margin-right:1em;}
    td.inter{max-width:300px;white-space:normal;}
  </style>
</head><body>
  <h1>${CHEM_NAME:-All Chemicals} Susceptibility (${SPECIES})</h1>
  <p>PubChem CID: ${cid}</p>
  <div id="filters">
    <label>Species:  <select id="spFilter"><option></option></select></label>
    <label>Chemical: <select id="chemFilter"><option></option></select></label>
  </div>
  <table id="susTable" class="display" style="width:100%">
    <thead><tr>
      <th>Chemical</th><th>Species</th><th>Gene</th>
      <th class="inter">Interaction</th><th>Actions</th><th>PubMed</th>
    </tr></thead>
    <tbody>
EOF

for row in "${rows[@]}"; do
  chem=$(cut -d, -f"$chem_col" <<<"$row"   | tr -d '"')
  species=$(cut -d, -f"$org_col" <<<"$row" | tr -d '"' || echo "")
  gene=$(cut -d, -f"$gene_col" <<<"$row"   | tr -d '"')
  inter=$(cut -d, -f"$int_col" <<<"$row"   | tr -d '"')
  acts=$(cut -d, -f"$acts_col" <<<"$row")
  pmids=$(cut -d, -f"$pmid_col" <<<"$row" | tr -d '"')

  # badges
  badges=""
  IFS='|' read -ra a <<< "$acts"
  for a0 in "${a[@]}"; do
    cls=other
    [[ "$a0" == increases* ]] && cls=increase
    [[ "$a0" == decreases* ]] && cls=decrease
    txt=${a0//^/ }
    badges+="<span class=\"badge ${cls}\">${txt}</span> "
  done

  # pmid links
  links=""
  IFS='|' read -ra p <<< "$pmids"
  for pid in "${p[@]}"; do
    [[ -n "$pid" ]] && links+="<a href=\"https://pubmed.ncbi.nlm.nih.gov/${pid}\" target=\"_blank\">${pid}</a> "
  done

  safe=$(echo "$gene" | tr ' ' '_' | sed 's/[^A-Za-z0-9_]/_/g')
  cat >> "$HTML_OUT" <<ROW
  <tr>
    <td>${chem}</td>
    <td>${species}</td>
    <td><a href="${GENES_DIR}/${safe}.html">${gene}</a></td>
    <td class="inter">${inter}</td>
    <td>${badges}</td>
    <td>${links}</td>
  </tr>
ROW
done

cat >> "$HTML_OUT" <<'EOF'
    </tbody>
  </table>
  <script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
  <script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
  <script>
    $(function(){
      let table = $('#susTable').DataTable({
        pageLength:10, lengthMenu:[5,10,20,50], columns:[null,null,null,null,{orderable:false},null]
      });
      table.column(0).data().unique().sort()
           .each(d=>$('#chemFilter').append($('<option>').val(d).text(d)));
      table.column(1).data().unique().sort()
           .each(d=>$('#spFilter').append($('<option>').val(d).text(d)));
      $('#chemFilter').on('change',()=>table.column(0).search($('#chemFilter').val()).draw());
      $('#spFilter').   on('change',()=>table.column(1).search($('#spFilter').val()).draw());
    });
  </script>
</body>
</html>
EOF

echo "✅ network.html created."

# —— ANCHOR SPECIES FOR GENE LOOKUP ——
if [[ "$SPECIES" != "all" ]]; then
  anchor=$(echo "$SPECIES" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
else
  anchor="homo_sapiens"
fi

# —— GENERATE per-gene pages ——
mkdir -p "$GENES_DIR"
for gene in "${unique_genes[@]}"; do
  safe=$(echo "$gene" | tr ' ' '_' | sed 's/[^A-Za-z0-9_]/_/g')
  cat > "${GENES_DIR}/${safe}.html" <<EOF
<!doctype html>
<html><head><meta charset="utf-8">
  <title>Gene Conservation: ${gene}</title>
  <script src="https://d3js.org/d3.v6.min.js"></script>
  <script src="https://unpkg.com/phylotree@0.9.4/build/phylotree.js"></script>
  <link rel="stylesheet" href="https://unpkg.com/phylotree@0.9.4/css/phylotree.css"/>
</head><body>
  <h1>Gene Conservation: ${gene}</h1>
  <p>Anchored on <strong>${anchor//_/ }</strong>.</p>
  <div id="tree"></div>
  <script>
    async function renderTree(){
      let sym="${gene}", sp="${anchor}";
      let x = await fetch(\`https://rest.ensembl.org/xrefs/symbol/\${sp}/\${sym}?content-type=application/json\`)
                .then(r=>r.json());
      let e = x.find(i=>i.dbname==="EnsemblGene");
      if(!e) return d3.select("#tree").text("No Ensembl ID for "+sym+" in "+sp);
      let f = await fetch(\`https://rest.ensembl.org/family/member/id/\${e.id}?content-type=application/json\`)
                .then(r=>r.json());
      let nw = f.family?.newick;
      if(!nw) return d3.select("#tree").text("No family tree for "+e.id);
      let svg = d3.select("#tree").append("svg");
      new phylotree.phylotree(nw).branch_length(true).svg(svg).layout();
    }
    document.addEventListener("DOMContentLoaded", renderTree);
  </script>
</body>
</html>
EOF
done

echo "✅ per-gene pages in $GENES_DIR/"
