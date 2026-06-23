# FAQ

### Why R-only? Why not Python, Julia, Stata?

R was chosen because:

1. Most academic statistical workflows in criminology, public health, and the social sciences are already in R.
2. R is free, cross-platform, and has a single canonical installer per OS.
3. R 4.0+ has `tools::R_user_dir()` for policy-compliant app-data locations — no platform-specific tweaks needed.
4. R's `download.file()`, `jsonlite`, `digest`, `utils::install.packages()` cover every dependency the framework needs in standard library + minimal CRAN packages.

If you want Python equivalents of the analysis, ship them as `analysis.py` alongside `analysis.R` — the framework doesn't object. But the orchestrator stays in R.

### Why not just use Docker?

Docker requires Docker, which most academic reviewers don't have and won't install. R is a 200 MB friendly installer they'll already have (or will install in 5 minutes from cran.r-project.org). The brick-proof floor is one R install — nothing else.

### Why does the bundle ship a vendored copy of the data sometimes?

Three reasons:

1. **Offline review** — reviewers without internet (committee members in flight, secure labs, etc.) need to be able to run the bundle as shipped.
2. **Replication permanence** — when Ontario eventually replaces the dataset (new fiscal year, schema change), the bundled copy preserves *exactly* what produced the published numbers.
3. **Licence permits it** — most open-government licences (OGL-Ontario, OGL-UK, CC-BY) explicitly allow redistribution with attribution. The framework auto-generates a `DATA_NOTICE.md` with the required attribution.

If your dataset's licence does NOT permit redistribution, build the small bundle (`./make_bundle.sh project` without `--with-data`) and rely on the CKAN/manual download paths.

### What about non-CKAN data sources?

See `docs/data_sources.md`. Short version: `lib_data_loader.R` currently has CKAN resolvers; adding Dataverse, Zenodo, or plain-HTTPS resolvers is straightforward (new functions following the same `resolve_via_*` signature).

### My analysis takes 20 minutes. Will the script time out?

No. `setup_and_run.R` invokes your analysis via `system2()` with no timeout; it just waits. The audit script (`verify_bundle.sh`) also has no timeout. There's no maximum runtime.

### Why is the work folder on the Desktop, not /tmp?

Because `/tmp` on macOS resolves to `/private/var/folders/<opaque-hash>/T/` which is full of system-cache files like `BlobRegistryFiles-*` and is impossible for a non-technical user to navigate to. The Desktop is universal, visible, and obvious. Pass `--clean` to `verify_bundle.sh` if you want auto-delete.

### The download is failing with `429` or `SSL handshake` errors — what's going on?

Almost always a VPN. Three specific patterns:

- **`HTTP 429 Too Many Requests`** — VPNs share a single exit IP across many users. If even a few people on your VPN's IP have been hitting `data.ontario.ca` (or archive.org for fallback), you all get rate-limited together. Fix: disable the VPN, or wait 5 minutes for the rate-limit window to roll over.
- **`SSL_ERROR_SYSCALL` / `UNEXPECTED_EOF_WHILE_READING` / `TLS handshake failed`** — Many corporate VPNs (Cisco AnyConnect, Palo Alto GlobalProtect, Zscaler, NetSkope, Cloudflare Warp with Zero Trust) perform TLS inspection, which R's HTTPS stack can't always negotiate. Fix: disable the VPN.
- **`HTTP 403 Forbidden`** — Some open-data portals geo-restrict. Fix: try a different VPN region, or no VPN.

`setup_and_run.R` already translates these errors into plain-English suggestions when they occur. The Wayback Machine fallback is automatic if the live download fails, but archive.org itself is sometimes blocked by aggressive VPNs — in that case, disable VPN entirely or download the file manually from the catalogue page and pass its path to `--data`.

### How do I bulk-archive a new dataset to the Wayback Machine?

Use the included helper:

```bash
./bricklayer/scripts/wayback_batch_archive.sh --from-ckan your-dataset-slug
```

It enumerates every resource on the CKAN package, submits each to Wayback with a 22-second delay (anonymous Wayback allows ~4 saves/minute), retries any 429s, and writes a JSON inventory you can drop into `data_provenance.json`. Designed for the once-per-year "new fiscal year release" rhythm.

### Will Gatekeeper / SmartScreen block my bundle?

On macOS, yes (on first run) — the user right-clicks → Open → Open once and it's whitelisted forever after. On Windows, SmartScreen may warn — *More info → Run anyway*. Properly signing the launchers requires Apple Developer ID ($99/yr) or Authenticode cert ($200+/yr); not worth it for academic distros. The SECURITY.md template addresses this directly.

### Why is `START_HERE.bat` blocked by Gmail / Outlook / corporate email?

Some email systems strip `.bat` and `.command` files from attachments even inside `.zip`. Workarounds in order of effort:

1. Email the bundle as `bundle.zip` directly and tell the recipient to unzip — most filters allow `.zip` whole.
2. Upload the bundle to Google Drive / OneDrive / GitHub Release and send a link.
3. Rename `START_HERE.bat` → `START_HERE.bat.txt`, instruct user to rename before running (least good).

### How do I add a new "save location" option to the menu?

Edit `ask_save_location()` in `bricklayer/R/lib_helpers.R`. Add an entry to the `locs` list with a `label` and `path`. Keep the allow-list short and explicitly safe — the point of the menu is to prevent the script from writing to surprising places.

### Can I publish a bundle without making it open-source?

The framework is AGPL-3.0-or-later; bundles built with it can be distributed under any AGPL-3.0-compatible licence. But the AGPL's "derived work" rules apply — read the licence text and consult someone (your university's IP office for academic work, a lawyer otherwise) if you're not sure.

### Where do I report bugs / suggest features?

Issues on the GitHub repo. Include:

- The output of `Rscript -e 'sessionInfo()'`
- Your OS and version
- The bundle's SHA256 if it's a build issue
- The full `run.log` from the most recent results folder if it's a runtime issue
