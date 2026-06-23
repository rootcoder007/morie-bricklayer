# Data sources

`morie-bricklayer` currently has built-in support for **CKAN-hosted** open-data portals (the most common kind, used by Ontario, UK, US federal, Canada federal, etc.). This document describes how to extend the framework to support other sources.

## Currently supported

### CKAN

Used by:
- `data.ontario.ca` (the reference example)
- `data.gov.uk`
- `data.gov`
- `open.canada.ca`
- Most provincial and many municipal portals worldwide

API pattern:
```
https://{portal}/api/3/action/package_show?id={slug}
```

In `data_provenance.json`, set:
```json
"dataset": {
  "package_slug":      "your-dataset-slug",
  "ckan_api_endpoint": "https://your-portal/api/3/action/package_show?id=your-dataset-slug"
},
"resource": {
  "name_match_pattern": "regex matching the resource name"
}
```

`lib_data_loader.R::resolve_via_ckan()` handles the rest.

## Not yet supported (PRs welcome)

### Dataverse

The Dataverse Project uses a different API. To add support, write a new function in `lib_data_loader.R`:

```r
resolve_via_dataverse <- function(provenance) {
  api <- provenance$dataset$dataverse_api_endpoint
  # GET /api/datasets/:persistentId?persistentId=<DOI>
  # Match resource by name_match_pattern in result$data$latestVersion$files
  # Return the dataFile downloadUrl
}
```

Then add a call to it in `setup_and_run.R` before the CKAN fallback.

### Zenodo

Similar pattern. Zenodo records have a `/api/records/<id>` endpoint that returns a `files` array. Match by `name_match_pattern` against `key`.

### Plain HTTPS

If your data is at a stable URL with no API metadata layer:

```json
"resource": {
  "direct_url": "https://example.com/path/to/file.csv",
  "sha256":     "..."
}
```

Leave `ckan_api_endpoint` empty. `setup_and_run.R` will fall through to the direct URL automatically.

### Authenticated sources (FIPPA, RDC, etc.)

Out of scope for the framework — bundles cannot include credentials by definition. The right pattern is:

1. The framework ships the analysis pipeline and a `data_provenance.json` that describes the schema and `synthetic_recipe`.
2. The `direct_url` field is null.
3. The README and SECURITY documents tell the reviewer how to obtain the data through proper channels.
4. The synthetic-data option lets reviewers verify the pipeline works without ever needing the real data.

This is what to do for, e.g., Statistics Canada Research Data Centre extracts.

## Adding a new source

The contract:

1. A function `resolve_via_<source>(provenance)` that returns a download URL string or `NULL`.
2. Wire it into `setup_and_run.R`'s "auto-download" branch (currently calls `resolve_via_ckan()` then `resolve_via_ckan_search()` then falls back to `prov$resource$direct_url`).
3. Document the required `data_provenance.json` keys for that source in this file.

Keep the function pure: take provenance in, return URL out, no side effects. The downloader (`download_data()`) and SHA256 verifier (`verify_sha256()`) are shared across all sources.
