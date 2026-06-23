# morie-bricklayer

**Brick-proof reproducibility bundles for academic data analysis.**

Turn an R analysis script + a public dataset into a polished, cross-platform reproducibility bundle that anyone — your supervisor, a reviewer, a stranger on the internet — can run with one double-click. No bash, no Python, no terminal experience needed beyond installing R itself.

---

## Why this exists

Academic reproducibility usually fails at one of three places: (a) the data is gone or behind a paywall; (b) the code assumes a specific OS or shell; (c) the reviewer can't be bothered to fight a 12-step setup. `morie-bricklayer` addresses all three with **defense in depth**:

- **Cross-platform launchers** — `START_HERE.command` (macOS), `START_HERE.bat` (Windows), `start_here.sh` (Linux), all routing to a single pure-R orchestrator
- **Future-proof data fetching** — CKAN API resolution by package slug + name pattern, with pinned URL + SHA256 fallback and Wayback Machine hooks
- **Schema validation** — every CSV load is validated against a pinned `schema.json`; structural drift produces clear errors not silent failures
- **Synthetic fallback** — if the reviewer has no internet and no data, the pipeline runs on schema-compliant random data with `SYNTHETIC` watermarks everywhere
- **Author-side audit** — `verify_bundle.sh` extracts the zip, runs the analysis, parses the manifest, exits non-zero on regression
- **Trust transparency** — every bundle ships with a `SECURITY.md` explaining what it does, what it touches, what it never touches, and how to verify its integrity

---

## Status

**v0.1 — early development.** Production-quality reference implementation (Vansh Singh Ruhela's OTIS MRP) lives in `examples/otis-mrp/` and runs to **36/36 PASS** in audit on macOS. Cross-platform code paths are written but only macOS has been end-to-end tested. Linux + Windows runs welcome as test reports.

## What you get

```
your_bundle/
├── START_HERE.command          ← macOS double-click
├── START_HERE.bat              ← Windows double-click
├── start_here.sh               ← Linux double-click
├── setup_and_run.R             ← pure-R cross-platform orchestrator
├── analysis.R                  ← YOUR analysis script
├── config.json                 ← project metadata
├── data_provenance.json        ← pinned URL + SHA256 + schema
├── README.md                   ← user-facing instructions
├── SECURITY.md                 ← trust + integrity verification
├── INSTRUCTIONS.txt            ← plain-text for non-Markdown readers
└── (optional vendored data CSV under OGL or equivalent open licence)
```

When the reviewer runs it, they get:

```
results_YYYYMMDD-HHMMSS/
├── 01_*.csv, 02_*.csv, ...    ← your analysis outputs, numbered
├── manifest.json               ← every cross-check, expected vs observed
├── SUMMARY.txt                 ← plain-language run summary
└── run.log                     ← full R session log
```

## Quickstart for a new project

```bash
git clone https://github.com/<you>/morie-bricklayer.git
cd morie-bricklayer
cp -r examples/otis-mrp examples/my-project
# Edit examples/my-project/config.json (data URL, schema, author, etc.)
# Replace examples/my-project/analysis.R with your own R script
./make_bundle.sh my-project
# → produces dist/my-project_v1.zip ready to ship
```

See `docs/quickstart.md` for a 5-minute walkthrough.

## Documentation

| Doc | What it covers |
|---|---|
| [docs/quickstart.md](docs/quickstart.md) | Bootstrap a new project in 5 minutes |
| [docs/customization.md](docs/customization.md) | Every configuration point in `config.json` |
| [docs/data_sources.md](docs/data_sources.md) | CKAN, Dataverse, Zenodo, manual sources |
| [docs/faq.md](docs/faq.md) | Common questions and edge cases |

## Reference example

`examples/otis-mrp/` is a complete, ship-quality bundle for the paper "Alert Complexity and Placement Volatility in Ontario Restrictive Confinement Data" by Vansh Singh Ruhela (U of T MA, Centre for Criminology and Sociolegal Studies, Aug 2026 submission). It uses Ontario's open OTIS A01RCDD dataset (CC OGL-Ontario) and reproduces all 36 numerical claims in the paper from the public CSV alone.

## Author & licence

`morie-bricklayer` is part of the [morie](https://github.com/) open-source toolkit ecosystem.

- **Author:** Vansh Singh Ruhela — vansh.ruhela@mail.utoronto.ca
- **ORCID:** 0009-0004-1750-3592
- **Licence:** AGPL-3.0-or-later (scripts, framework, templates)
- **Contributions:** see [CONTRIBUTING.md](CONTRIBUTING.md)

## Acknowledgements

Built up from the OTIS MRP reproducibility bundle developed for the August 2026 MA submission; data from the Ontario Ministry of the Solicitor General under the Open Government Licence – Ontario.
