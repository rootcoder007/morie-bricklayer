#!/usr/bin/env bash
# tests/test_build_otis.sh
#
# Smoke test: build the otis-mrp example bundle and verify it.
# Used as the canonical "does the framework actually work?" check.
#
# USAGE:
#   ./tests/test_build_otis.sh
#   ./tests/test_build_otis.sh --with-data /path/to/a01_RC.csv
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_PATH=""
if [[ "${1:-}" == "--with-data" ]]; then
  DATA_PATH="$2"
fi

cd "${REPO_ROOT}"

echo "[1/3] Building otis-mrp bundle..."
if [[ -n "${DATA_PATH}" ]]; then
  ./make_bundle.sh otis-mrp --with-data "${DATA_PATH}" --version test
else
  ./make_bundle.sh otis-mrp --version test
fi

echo
echo "[2/3] Locating built bundle..."
BUNDLE="$(ls -1t dist/otis-mrp_vtest*.zip 2>/dev/null | head -1)"
if [[ -z "${BUNDLE}" ]]; then
  echo "FAIL: no bundle built"
  exit 1
fi
echo "  Found: ${BUNDLE}"

echo
echo "[3/3] Auditing via verify_bundle.sh..."
./bricklayer/scripts/verify_bundle.sh "${BUNDLE}" --clean
RC=$?

if [[ ${RC} -eq 0 ]]; then
  echo
  echo "=========================================================="
  echo "  ✓ test_build_otis PASSED"
  echo "=========================================================="
  exit 0
else
  echo "FAIL: verify_bundle exited ${RC}"
  exit ${RC}
fi
