# Contributing to morie-bricklayer

Thanks for considering a contribution. This kit lives or dies by being **boring and reliable** — academic reviewers should never wonder why something is the way it is.

## Scope

In scope:
- Cross-platform fixes (Linux/Windows quirks, OS-detection edge cases)
- New data-source resolvers (Dataverse, Zenodo, plain HTTPS) — see [docs/data_sources.md](docs/data_sources.md)
- New synthetic-column types in `lib_synthetic.R`
- Improved error messages, especially "first-run" failures
- Documentation, FAQs, examples

Out of scope (politely declined):
- Replacing R with another language
- Adding Docker / containerization as a required step
- Required cloud services or sign-ins
- Telemetry / analytics
- Anything that breaks the "R-only" floor

## Code style

- R: tidyverse style guide is fine, but prefer base R where it doesn't hurt readability — the framework should run on a fresh R install with minimal packages.
- bash: `set -euo pipefail`, double-quote variable expansions, prefer `[[ ]]` over `[ ]`.
- JSON: 2-space indent, trailing comma-free (JSON spec).
- All scripts: shebang, header comment explaining purpose, AGPL-3.0-or-later licence note.

## Tests before pull request

```bash
./tests/test_build_otis.sh
```

This must pass before opening a PR. If your change touches `lib_synthetic.R` or the synthesis recipe schema, also run:

```bash
./tests/test_build_otis.sh --with-data /path/to/a01_RC.csv
```

(End-to-end with real data, to confirm 28/36 PASS from the public CSV.)

## Submitting

1. Fork the repo.
2. Branch from `main` named `topic/<short-description>`.
3. Commit with `Conventional Commits` style: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`.
4. Open a PR; describe what changed and why, and include the test output.

## Security issues

Email `vansh.ruhela@mail.utoronto.ca` directly rather than opening a public issue. The framework runs other people's code on reviewers' machines — security bugs are taken seriously.

## Code of conduct

Be kind. This is academic infrastructure. The audience is grad students and reviewers, not seasoned ops engineers. If an error message is unclear, fix the error message.

## Licence

By contributing, you agree your contribution is licensed under AGPL-3.0-or-later, the same as the rest of the project.
