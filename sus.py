#!/usr/bin/env python3
import os
import pandas as pd
from jinja2 import Template

# ——— CONFIGURATION ———
CTD_FILE   = "ctd_data/CTD_chem_gene_ixns.csv"
OUTPUT_DIR = "network_outputs"
OUTPUT_HTML = os.path.join(OUTPUT_DIR, "index.html")

# CTD fields (no header in file)
FIELD_NAMES = [
    "ChemicalName", "ChemicalID", "CasRN", "GeneSymbol", "GeneID",
    "GeneForms", "Organism", "OrganismID", "Interaction",
    "InteractionActions", "PubMedIDs"
]

# HTML template with Bootstrap styling and server-side dropdowns
TEMPLATE = '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>SUS-PECIES Database</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
  <link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/dataTables.bootstrap5.min.css">
</head>
<body>
  <nav class="navbar navbar-expand-lg navbar-dark bg-dark mb-4">
    <div class="container-fluid">
      <a class="navbar-brand" href="#">SUS-PECIES</a>
      <span class="navbar-text text-light">A database for exploring chemical–species susceptibility interactions</span>
    </div>
  </nav>
  <div class="container">
    <div class="row mb-3">
      <div class="col-md-4">
        <select id="chemFilter" class="form-select">
          <option value="">All Chemicals</option>
          {% for chem in chems %}
          <option value="{{ chem }}">{{ chem }}</option>
          {% endfor %}
        </select>
      </div>
      <div class="col-md-4">
        <select id="spFilter" class="form-select">
          <option value="">All Species</option>
          {% for sp in species_list %}
          <option value="{{ sp }}">{{ sp }}</option>
          {% endfor %}
        </select>
      </div>
    </div>
    <table id="susTable" class="table table-striped table-bordered" style="width:100%">
      <thead class="table-dark"><tr>
        <th>Chemical</th><th>Species</th><th>Gene</th>
        <th>Interaction</th><th>Actions</th><th>PubMed</th>
      </tr></thead>
      <tbody>
      {% for row in rows %}
      <tr>
        <td>{{ row.Chemical }}</td>
        <td>{{ row.Species }}</td>
        <td>{{ row.GeneSymbol }}</td>
        <td>{{ row.Interaction }}</td>
        <td>
          {% for badge in row.Badges %}
          <span class="badge {{ badge.cls }} me-1">{{ badge.txt }}</span>
          {% endfor %}
        </td>
        <td>
          {% for pid in row.PubMedIDs %}
          <a href="https://pubmed.ncbi.nlm.nih.gov/{{pid}}" target="_blank">{{pid}}</a>{% if not loop.last %}, {% endif %}
          {% endfor %}
        </td>
      </tr>
      {% endfor %}
      </tbody>
    </table>
  </div>
  <script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
  <script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
  <script src="https://cdn.datatables.net/1.13.6/js/dataTables.bootstrap5.min.js"></script>
  <script>
    $(document).ready(function() {
      var table = $('#susTable').DataTable({
        pageLength: 10,
        lengthMenu: [5, 10, 20, 50]
      });
      $('#chemFilter').on('change', function() {
        table.column(0).search(this.value).draw();
      });
      $('#spFilter').on('change', function() {
        table.column(1).search(this.value).draw();
      });
    });
  </script>
</body>
</html>
'''

def make_safe(name: str) -> str:
    name = name.strip().lower().replace(" ", "_")
    return "".join(ch if (ch.isalnum() or ch == "_") else "_" for ch in name)

def parse_actions(cell: str):
    badges = []
    for act in cell.split("|"):
        if not act: continue
        la = act.lower()
        # Bootstrap badge classes
        cls = 'bg-success' if la.startswith('increases') else 'bg-danger' if la.startswith('decreases') else 'bg-secondary'
        badges.append({'cls': cls, 'txt': act.replace('^', ' ')})
    return badges

# ——— LOAD DATA ———
df = pd.read_csv(
    CTD_FILE,
    comment="#",
    header=None,
    names=FIELD_NAMES,
    dtype=str,
    sep=",",
    quotechar='"',
    engine='python'
).fillna("")

# rename columns for template
rename_map = {
    'ChemicalName': 'Chemical',
    'Organism':     'Species',
    'GeneSymbol':   'GeneSymbol',
    'Interaction':  'Interaction',
    'InteractionActions': 'Actions',
    'PubMedIDs':    'PubMedIDs'
}
df.rename(columns=rename_map, inplace=True)

# parse badges & PubMed lists
df['Badges']    = df['Actions'].map(parse_actions)
df['PubMedIDs'] = df['PubMedIDs'].str.split('|').apply(lambda lst: [pid for pid in lst if pid])

# compute dropdown values
chems        = sorted(df['Chemical'].unique())
species_list = sorted(df['Species'].unique())

# render template
tmpl = Template(TEMPLATE)
rows = df.to_dict(orient='records')
html = tmpl.render(rows=rows, chems=chems, species_list=species_list)

# write out
os.makedirs(OUTPUT_DIR, exist_ok=True)
with open(OUTPUT_HTML, 'w', encoding='utf-8') as f:
    f.write(html)
print(f"✅ Created {OUTPUT_HTML}")
