#!/usr/bin/env bash
# START_HERE.command
#
# macOS launcher for any morie-bricklayer bundle.
# Double-click in Finder. If Gatekeeper blocks the first run:
#   Right-click → Open → Open (confirm dialog).
#
# Requirement: R from https://cran.r-project.org/bin/macosx/
#
# Licence: AGPL-3.0-or-later.

set -uo pipefail
cd "$(dirname "$0")" || exit 1

clear
cat <<'BANNER'
==========================================================
  morie-bricklayer Reproducibility Bundle — macOS Launcher
==========================================================

You don't need any terminal experience — this window will run
the analysis for you. Results appear in a folder named
results_YYYYMMDD-HHMMSS/ next to this file.

==========================================================
BANNER

RSCRIPT="$(command -v Rscript 2>/dev/null || true)"
if [[ -z "${RSCRIPT}" ]]; then
  for cand in \
      /opt/homebrew/bin/Rscript \
      /usr/local/bin/Rscript \
      /Library/Frameworks/R.framework/Resources/Rscript \
      /Library/Frameworks/R.framework/Resources/bin/Rscript \
      /usr/bin/Rscript; do
    [[ -x "${cand}" ]] && RSCRIPT="${cand}" && break
  done
fi

if [[ -z "${RSCRIPT}" ]]; then
  echo
  echo "R is NOT installed on this Mac."
  echo
  echo "To install R, do ONE of:"
  echo "  Option A (easiest): https://cran.r-project.org/bin/macosx/"
  echo "  Option B (Homebrew): brew install --cask r"
  echo
  echo "After installing, double-click START_HERE.command again."
  read -r -p "Press Enter to close this window..." _
  exit 1
fi

if [[ ! -f "./setup_and_run.R" ]]; then
  echo "ERROR: setup_and_run.R missing from this folder."
  echo "Make sure you extracted the entire .zip."
  read -r -p "Press Enter to close this window..." _
  exit 2
fi

chmod +x ./*.sh 2>/dev/null || true

echo "Found R at: ${RSCRIPT}"
echo "Starting analysis..."
echo

"${RSCRIPT}" setup_and_run.R
RC=$?

echo
echo "=========================================================="
if [[ ${RC} -eq 0 ]]; then
  echo "  Finished successfully (exit code 0)."
else
  echo "  Finished with exit code ${RC}."
  echo "  See run.log in the most recent results_* folder."
fi
echo "=========================================================="
read -r -p "Press Enter to close this window..." _
