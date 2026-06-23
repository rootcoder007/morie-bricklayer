# Quickstart — your first morie-bricklayer bundle in 5 minutes

This walks you through creating a shippable reproducibility bundle for **your own** analysis script and dataset.

## Prerequisites

- R 4.0+ installed
- bash, Python 3 (for `make_bundle.sh`), zip
- A public dataset URL (CKAN-hosted is easiest — e.g. data.ontario.ca, data.gov.uk, data.gov)
- An R analysis script that reads a CSV (or `.RData`), produces some numbers, and writes them to a folder

## 1. Clone the kit

```bash
git clone https://github.com/morie-oss/morie-bricklayer.git
cd morie-bricklayer
```

## 2. Copy the OTIS MRP example to your own project

```bash
cp -r examples/otis-mrp examples/my-project
```

## 3. Edit `examples/my-project/config.json`

Fill in your metadata:

```json
{
  "project": {
    "name":        "my-project",
    "title":       "My Analysis Project",
    "paper_title": "...",
    "author":      "Your Name",
    "contact":     "you@example.com",
    "orcid":       "0000-0000-0000-0000",
    "affiliation": "Your University",
    "licence":     "AGPL-3.0-or-later"
  },
  "analysis":   { "r_script": "analysis.R" },
  "r_packages": ["tidyverse", "lme4", ...],
  "network":    { "endpoints": ["https://data.example.org/..."] },
  "expected":   { "total_checks": 10, "pass_real": 10, "pass_csv": 8 }
}
```

## 4. Edit `examples/my-project/data_provenance.json`

This is the source-of-truth for your dataset. Fill in:

- `dataset.package_slug` — the CKAN slug for your dataset (e.g. `data-on-inmates-in-ontario`)
- `dataset.ckan_api_endpoint` — usually `https://{portal}/api/3/action/package_show?id={slug}`
- `dataset.catalogue_page` — the human-facing page URL
- `dataset.licence_name` / `licence_url` — e.g. `Open Government Licence – Ontario`
- `resource.name_match_pattern` — regex that matches the resource name in the CKAN response (e.g. `Restrictive.?Confinement.*Detailed.?Dataset`)
- `resource.filename` — what to save the downloaded file as
- `resource.direct_url` — the pinned direct URL (fallback if CKAN API fails)
- `resource.sha256` — SHA256 of the file as you retrieved it (run `shasum -a 256` on it once)
- `resource.size_bytes` — file size in bytes
- `schema.expected_columns` — list of column names your script needs
- `schema.expected_value_sets` — categorical value sets per column
- `schema.structural_invariants` — row count bounds, etc.
- `schema.synthetic_recipe` — per-column synthesis specs (see [customization.md](customization.md))

## 5. Replace `examples/my-project/analysis.R` with your script

Your analysis script will be invoked as:

```bash
Rscript analysis.R <input_path> <output_dir>
```

It must:

- Accept the input data file path as argument 1
- Accept the output folder path as argument 2
- Write a `manifest.json` to the output folder containing `{ "meta": {...}, "results": { "<check_name>": { "observed": X, "expected": Y, "status": "PASS|DIFFER|INFO", ... } } }`
- Optionally check `Sys.getenv("BRICKLAYER_SYNTHETIC")` — if `"1"`, mark all cross-checks as `INFO`

See `examples/otis-mrp/analysis.R` for a complete working reference.

## 6. Build the bundle

```bash
./make_bundle.sh my-project
```

Produces `dist/my-project_v1.zip`. To include the dataset CSV:

```bash
./make_bundle.sh my-project --with-data /path/to/your_dataset.csv
```

Produces `dist/my-project_v1_with_data.zip`.

The output prints the bundle's SHA256 — send that out-of-band to recipients.

## 7. Verify before shipping

```bash
./bricklayer/scripts/verify_bundle.sh dist/my-project_v1.zip
```

Extracts to `~/Desktop/my-project_v1_audit_<timestamp>/`, runs `--quick`, exits non-zero on regression.

## 8. Ship

Send `dist/my-project_v1.zip` by email/Drive/Signal/whatever. Send the SHA256 separately. Done.

---

## Next reading

- [customization.md](customization.md) — what's configurable, what's hard-coded
- [data_sources.md](data_sources.md) — supporting non-CKAN sources (Dataverse, Zenodo, plain HTTPS)
- [faq.md](faq.md) — common questions
