# Customization

Every configurable point in `morie-bricklayer`, organized by which file controls it.

---

## `config.json` — project metadata + behavior

```json
{
  "project": {
    "name":         "...",   // short slug, used in folder names + R_user_dir
    "title":        "...",   // human-readable, shown in banners
    "paper_title":  "...",   // referenced in README/SECURITY/INSTRUCTIONS
    "author":       "...",
    "contact":      "...",   // email
    "orcid":        "...",
    "affiliation":  "...",
    "supervisor":   "...",   // optional
    "submission":   "...",   // optional, free-form date
    "licence":      "AGPL-3.0-or-later"
  },
  "analysis": {
    "r_script": "analysis.R"  // path to your R script, relative to bundle
  },
  "r_packages": [
    "data.table", "MatchIt", ...  // auto-installed on first run
  ],
  "data": {
    "default_candidates": [
      "/Volumes/X/Y/data.csv",     // optional — extra paths to probe
      "/mnt/data/myfile.RData"
    ]
  },
  "network": {
    "endpoints": [
      "https://...",   // URLs shown in WHERE EVERYTHING WILL GO panel
      "https://..."
    ]
  },
  "summary": {
    "what_was_done": [
      "1. ...",   // bullet points written into SUMMARY.txt at the end of every run
      "2. ..."
    ]
  },
  "expected": {
    "total_checks": 36,
    "pass_real":    36,
    "pass_csv":     28  // expected PASS count when running from public CSV (DML INFO)
  }
}
```

---

## `data_provenance.json` — data source + schema + synthesis recipe

### dataset block (the source)

```json
"dataset": {
  "package_slug":        "data-on-inmates-in-ontario",
  "ckan_api_endpoint":   "https://data.ontario.ca/api/3/action/package_show?id=data-on-inmates-in-ontario",
  "catalogue_page":      "https://...",
  "publisher":           "Ontario Ministry of the Solicitor General",
  "licence_name":        "Open Government Licence – Ontario",
  "licence_url":         "https://...",
  "licence_short":       "OGL-Ontario"
}
```

### resource block (the specific file)

```json
"resource": {
  "name":               "Restrictive Confinement – Detailed Dataset",
  "name_match_pattern": "Restrictive.?Confinement.*Detailed.?Dataset",  // regex
  "format":             "CSV",
  "resource_uuid":      "...",
  "filename":           "a01_RC.csv",
  "direct_url":         "https://.../a01_RC.csv",
  "size_bytes":         4762368,
  "sha256":             "d0fdae..."
}
```

The script tries `name_match_pattern` against every resource in the CKAN response; the first match wins. This is what survives Ontario reslugging the dataset.

### schema block (validation + synthesis)

```json
"schema": {
  "expected_columns":   ["col_a", "col_b", ...],
  "expected_value_sets": {
    "col_a": ["X", "Y", "Z"]   // categorical allowed values
  },
  "structural_invariants": {
    "min_data_rows": 70000,
    "max_data_rows": 90000
  },
  "synthetic_recipe": { ... }   // see below
}
```

### synthetic_recipe — schema-driven synthesis

```json
"synthetic_recipe": {
  "n_rows": 65000,
  "seed":   91735246,
  "row_replication": {           // optional — multi-row "persons"
    "values":  [1, 2, 3, 4],
    "weights": [0.82, 0.12, 0.04, 0.02]
  },
  "columns": {
    "EndFiscalYear": {
      "type":    "sample",
      "values":  [2023, 2024, 2025],
      "weights": [0.33, 0.33, 0.34]
    },
    "MentalHealth_Alert": {
      "type":            "bernoulli",
      "p":               0.10,
      "p_with_baserate": 0.15,    // adds row-level latent correlation
      "labels":          ["Yes", "No"]
    },
    "Number_Of_Placements": {
      "type":   "poisson",
      "lambda": 25,
      "min":    1
    },
    "UniqueIndividual_ID": {
      "type":     "id_pattern",
      "pattern":  "{year}-{seq:05d}-RC",
      "year_col": "EndFiscalYear"
    }
  }
}
```

Supported `type` values:
- `sample` — uniform or weighted categorical
- `bernoulli` — Yes/No with optional per-row baseline correlation
- `poisson` — count column with `lambda` and `min`
- `id_pattern` — string templating using `{year}` and `{seq:05d}`
- `sequence` — integer sequence from `from`

To add new types, edit `bricklayer/R/lib_synthetic.R`.

---

## Your `analysis.R`

The framework invokes it as:

```bash
Rscript analysis.R <input_data_path> <output_dir>
```

Your script is responsible for:

1. Reading `commandArgs(trailingOnly = TRUE)` for input + output paths
2. Producing CSV files in `<output_dir>` (named `01_...csv`, `02_...csv`, etc.)
3. Writing `<output_dir>/manifest.json` with structure:

```json
{
  "meta": {
    "script":     "analysis.R",
    "version":    "...",
    "seed":       12345,
    "input_path": "...",
    "synthetic":  false
  },
  "results": {
    "check_name_1": {
      "group":    "descriptive",
      "observed": 0.123,
      "expected": 0.123,
      "diff":     0.000,
      "status":   "PASS",
      "tol":      0.001
    },
    "check_name_2": { ... }
  }
}
```

Status values: `PASS`, `DIFFER`, `INFO`.

The libraries `lib_manifest.R::record()` and `lib_manifest.R::write_manifest_json()` exist exactly to make this easy. Source them from your analysis.R if you want.

If `Sys.getenv("BRICKLAYER_SYNTHETIC")` is `"1"`, your script should mark all cross-checks as `INFO` rather than `PASS/DIFFER` — the comparison isn't meaningful on random data.

---

## Templates (`bricklayer/templates/`)

All four templates use `{{variable}}` substitution at bundle build time. Variables available:

| Variable | Source |
|---|---|
| `{{project_title}}`, `{{author}}`, `{{contact}}`, `{{orcid}}`, `{{affiliation}}`, `{{paper_title}}`, `{{licence}}` | `config.json` → `project.*` |
| `{{resource_name}}`, `{{publisher}}`, `{{catalogue_url}}`, `{{direct_url}}`, `{{sha256}}`, `{{size_bytes}}`, `{{filename}}` | `data_provenance.json` → `dataset.*` / `resource.*` |
| `{{licence_name}}`, `{{licence_url}}`, `{{data_licence}}` | `data_provenance.json` → `dataset.*` |
| `{{retrieved_at}}` | `data_provenance.json` → `captured_at_utc` |
| `{{build_date}}` | Today (`date -u +%Y-%m-%d`) |
| `{{bricklayer_version}}` | Set in `make_bundle.sh` |
| `{{bundle_filename}}`, `{{bundle_sha256}}` | Computed at build time |

To add new placeholders, edit the substitution map in `make_bundle.sh`.

---

## What's intentionally not configurable

| Thing | Why |
|---|---|
| Save-location menu (bundle / Downloads / Documents / R-canonical / custom) | Allow-list. Adding more options would let projects write outside user-owned space. |
| The `record()` PASS/DIFFER/INFO contract | Stable across projects so reviewers learn one format. |
| `manifest.json` structure | Same — stable contract. |
| `START_HERE.*` banner text | Project name comes from `config.json` and is printed by `setup_and_run.R`. Launchers stay project-agnostic so they're easier to audit. |
| SHA256 verification on download | Always on. |
