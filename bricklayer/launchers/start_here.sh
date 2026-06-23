#!/usr/bin/env bash
# start_here.sh — Linux launcher for any morie-bricklayer bundle.
# Run from a terminal in the bundle folder: ./start_here.sh
#
# Requirements:
#   Fedora/RHEL:   sudo dnf install R
#   Ubuntu/Debian: sudo apt install r-base
#   Arch:          sudo pacman -S r
#
# Licence: AGPL-3.0-or-later.

set -euo pipefail
cd "$(dirname "$0")"

cat <<'BANNER'
==========================================================
  morie-bricklayer Reproducibility Bundle — Linux Launcher
==========================================================
BANNER

RSCRIPT="$(command -v Rscript 2>/dev/null || true)"
if [[ -z "${RSCRIPT}" ]]; then
  for cand in /usr/bin/Rscript /usr/local/bin/Rscript /opt/R/*/bin/Rscript; do
    [[ -x "${cand}" ]] && RSCRIPT="${cand}" && break
  done
fi

if [[ -z "${RSCRIPT}" ]]; then
  echo
  echo "R is NOT installed on this computer."
  echo
  echo "To install R:"
  if command -v dnf >/dev/null 2>&1; then
    echo "    sudo dnf install R"
  elif command -v apt >/dev/null 2>&1; then
    echo "    sudo apt install r-base"
  elif command -v pacman >/dev/null 2>&1; then
    echo "    sudo pacman -S r"
  else
    echo "    https://cran.r-project.org/"
  fi
  echo
  read -r -p "Press Enter to close..." _
  exit 1
fi

if [[ ! -f "./setup_and_run.R" ]]; then
  echo "ERROR: setup_and_run.R missing from this folder."
  read -r -p "Press Enter to close..." _
  exit 2
fi

echo "Found R at: ${RSCRIPT}"
echo
"${RSCRIPT}" setup_and_run.R "$@"
RC=$?

echo
echo "=========================================================="
if [[ ${RC} -eq 0 ]]; then
  echo "  Finished successfully."
else
  echo "  Finished with exit code ${RC}."
fi
echo "=========================================================="
exit ${RC}
