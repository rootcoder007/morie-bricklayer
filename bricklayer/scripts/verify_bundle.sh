#!/usr/bin/env bash
# verify_bundle.sh — Author-side bundle audit.
#
# Extracts the bundle zip to ~/Desktop/<project>_audit_<timestamp>/,
# runs setup_and_run.R --quick, parses manifest.json, exits non-zero
# on regression. Use before shipping a new version.
#
# USAGE:
#   ./verify_bundle.sh [bundle.zip] [--clean] [--data PATH]
#
#   bundle.zip  : path to the zip to audit (default: newest v*.zip in cwd)
#   --clean     : auto-delete the audit work folder on success
#   --data PATH : pass to setup_and_run.R as --data PATH
#
# Licence: AGPL-3.0-or-later.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AUTO_CLEAN=0
DATA_PATH=""
BUNDLE_ZIP=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean) AUTO_CLEAN=1; shift ;;
    --data) DATA_PATH="$2"; shift 2 ;;
    *) BUNDLE_ZIP="$1"; shift ;;
  esac
done

if [[ -z "${BUNDLE_ZIP}" ]]; then
  BUNDLE_ZIP="$(ls -1t "${SCRIPT_DIR}"/*_v*.zip 2>/dev/null | grep -v with_data | head -1 || true)"
fi
if [[ -z "${BUNDLE_ZIP}" || ! -f "${BUNDLE_ZIP}" ]]; then
  echo "ERROR: no bundle zip found." >&2
  exit 1
fi

BUNDLE_BASE="$(basename "${BUNDLE_ZIP}" .zip)"
TMP_ROOT="${HOME}/Desktop/${BUNDLE_BASE}_audit_$(date +%Y%m%d-%H%M%S)"
mkdir -p "${TMP_ROOT}"
[[ ${AUTO_CLEAN} -eq 1 ]] && trap 'rm -rf "${TMP_ROOT}"' EXIT

cat <<HDR
==========================================================
verify_bundle.sh — bundle smoke-test audit
==========================================================
Bundle:   ${BUNDLE_ZIP}  ($(wc -c < "${BUNDLE_ZIP}" | tr -d ' ') bytes)
Work dir: ${TMP_ROOT}
==========================================================

HDR

echo "[1/4] Extracting bundle..."
unzip -q "${BUNDLE_ZIP}" -d "${TMP_ROOT}"
EXTRACTED="$(ls -1d "${TMP_ROOT}"/*/ 2>/dev/null | head -1 | sed 's:/$::')"
echo "      Extracted to: ${EXTRACTED}"
echo

echo "[2/4] Verifying executable bits..."
for f in setup_and_run.R; do
  [[ -f "${EXTRACTED}/${f}" ]] && echo "      ✓ ${f} present"
done
for f in START_HERE.command start_here.sh; do
  if [[ -f "${EXTRACTED}/${f}" && ! -x "${EXTRACTED}/${f}" ]]; then
    echo "      ! ${f} is not executable in the zip"
  fi
done
echo

echo "[3/4] Running --quick analysis..."
cd "${EXTRACTED}"
set +e
if [[ -n "${DATA_PATH}" ]]; then
  Rscript setup_and_run.R --quick --data "${DATA_PATH}" > "${TMP_ROOT}/run.log" 2>&1
else
  Rscript setup_and_run.R --quick > "${TMP_ROOT}/run.log" 2>&1
fi
RUN_EXIT=$?
set -e
cd - >/dev/null

if [[ ${RUN_EXIT} -ne 0 ]]; then
  echo "      ERROR: setup_and_run.R exited with ${RUN_EXIT}"
  echo "      Last 30 lines of log:"
  tail -30 "${TMP_ROOT}/run.log" | sed 's/^/        /'
  exit 4
fi

LATEST="$(ls -1dt "${EXTRACTED}"/results_* 2>/dev/null | head -1)"
if [[ -z "${LATEST}" || ! -f "${LATEST}/manifest.json" ]]; then
  echo "      ERROR: no manifest.json produced"
  exit 5
fi
echo "      Results: ${LATEST}"
echo

echo "[4/4] Parsing manifest.json..."
SUMMARY="$(python3 - <<PYEOF
import json
m = json.load(open("${LATEST}/manifest.json"))
r = m["results"]
print(f'{len(r)} {sum(1 for v in r.values() if v["status"]=="PASS")} {sum(1 for v in r.values() if v["status"]=="DIFFER")} {sum(1 for v in r.values() if v["status"]=="INFO")}')
PYEOF
)"
read -r TOTAL PASS_N DIFF_N INFO_N <<< "${SUMMARY}"
echo "      Total:  ${TOTAL}"
echo "      PASS:   ${PASS_N}"
echo "      DIFFER: ${DIFF_N}"
echo "      INFO:   ${INFO_N}"
echo

if (( DIFF_N > 0 )); then
  echo "FAIL: ${DIFF_N} cross-check(s) differ."
  exit 6
fi

echo "=========================================================="
echo "  ✓ BUNDLE VERIFIED"
echo "=========================================================="
echo "  Bundle:      ${BUNDLE_ZIP}"
echo "  Result:      ${PASS_N}/${TOTAL} PASS"
echo "  Work folder: ${TMP_ROOT}"
echo "               (delete manually, or use --clean for auto-delete)"
echo "  This bundle is safe to ship."
