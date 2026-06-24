#!/usr/bin/env bash
# make_bundle.sh — Build a shippable reproducibility bundle from a project config.
#
# Reads examples/<project>/config.json and emits dist/<project>_v<N>.zip with all
# scripts, R libraries, OS launchers, rendered templates, and (optionally) a
# vendored data file.
#
# USAGE:
#   ./make_bundle.sh <project>            # build small bundle
#   ./make_bundle.sh <project> --with-data PATH  # also include data file
#   ./make_bundle.sh <project> --version 2       # version suffix (default: 1)
#
# Licence: AGPL-3.0-or-later.

set -euo pipefail

BRICKLAYER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRICKLAYER_VERSION="0.1"

PROJECT=""
DATA_PATH=""
VERSION="1"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-data) DATA_PATH="$2"; shift 2 ;;
    --version)   VERSION="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) PROJECT="$1"; shift ;;
  esac
done

[[ -z "${PROJECT}" ]] && { echo "ERROR: project name required (e.g. ./make_bundle.sh otis-mrp)"; exit 1; }

PROJECT_DIR="${BRICKLAYER_ROOT}/examples/${PROJECT}"
[[ ! -d "${PROJECT_DIR}" ]] && { echo "ERROR: ${PROJECT_DIR} not found"; exit 2; }

CONFIG="${PROJECT_DIR}/config.json"
[[ ! -f "${CONFIG}" ]] && { echo "ERROR: ${CONFIG} not found"; exit 3; }

# --- Read JSON via python (jq optional) ---
read_json() {
  python3 -c "import json,sys; d=json.load(open('${CONFIG}'));
keys = '${1}'.split('.')
v=d
for k in keys:
    v = v.get(k) if isinstance(v, dict) else None
    if v is None: break
print(v if v is not None else '')"
}

PROJECT_TITLE="$(read_json project.title)"
PROJECT_NAME="$(read_json project.name)"
AUTHOR="$(read_json project.author)"
CONTACT="$(read_json project.contact)"
ORCID="$(read_json project.orcid)"
AFFILIATION="$(read_json project.affiliation)"
PAPER_TITLE="$(read_json project.paper_title)"
LICENCE="$(read_json project.licence)"

# --- Read provenance for data fields ---
PROV="${PROJECT_DIR}/data_provenance.json"
read_prov() {
  if [[ -f "${PROV}" ]]; then
    python3 -c "import json,sys; d=json.load(open('${PROV}'));
keys = '${1}'.split('.')
v=d
for k in keys:
    v = v.get(k) if isinstance(v, dict) else None
    if v is None: break
print(v if v is not None else '')"
  fi
}

RESOURCE_NAME="$(read_prov resource.name)"
CATALOGUE_URL="$(read_prov dataset.catalogue_page)"
DIRECT_URL="$(read_prov resource.direct_url)"
SHA256_PIN="$(read_prov resource.sha256)"
SIZE_BYTES="$(read_prov resource.size_bytes)"
FILENAME="$(read_prov resource.filename)"
PUBLISHER="$(read_prov dataset.publisher)"
LICENCE_NAME="$(read_prov dataset.licence_name)"
LICENCE_URL="$(read_prov dataset.licence_url)"
RETRIEVED_AT="$(read_prov captured_at_utc)"

# --- Staging area ---
BUILD_DATE="$(date -u +%Y-%m-%d)"
BASENAME="${PROJECT}_v${VERSION}"
[[ -n "${DATA_PATH}" ]] && BASENAME="${BASENAME}_with_data"
STAGE="$(mktemp -d)/${BASENAME}"
mkdir -p "${STAGE}"

echo "Building ${BASENAME}..."
echo "  Project:   ${PROJECT_NAME}"
echo "  Author:    ${AUTHOR}"
echo "  Stage:     ${STAGE}"
echo

# --- Copy R libs + setup_and_run.R ---
cp "${BRICKLAYER_ROOT}/bricklayer/R/lib_helpers.R"     "${STAGE}/"
cp "${BRICKLAYER_ROOT}/bricklayer/R/lib_data_loader.R" "${STAGE}/"
cp "${BRICKLAYER_ROOT}/bricklayer/R/lib_synthetic.R"   "${STAGE}/"
cp "${BRICKLAYER_ROOT}/bricklayer/R/lib_manifest.R"    "${STAGE}/"
cp "${BRICKLAYER_ROOT}/bricklayer/inst/scripts/setup_and_run.R"   "${STAGE}/"

# --- Copy OS launchers ---
cp "${BRICKLAYER_ROOT}/bricklayer/launchers/"START_HERE.command "${STAGE}/"
cp "${BRICKLAYER_ROOT}/bricklayer/launchers/"START_HERE.bat     "${STAGE}/"
cp "${BRICKLAYER_ROOT}/bricklayer/launchers/"start_here.sh      "${STAGE}/"

# --- Copy project-specific files ---
cp "${PROJECT_DIR}/config.json"            "${STAGE}/"
cp "${PROJECT_DIR}/data_provenance.json"   "${STAGE}/"
cp "${PROJECT_DIR}"/analysis.R             "${STAGE}/"
[[ -f "${PROJECT_DIR}/schema.json" ]] && cp "${PROJECT_DIR}/schema.json" "${STAGE}/" || true

# --- Render templates ---
render_template() {
  local tmpl="$1" out="$2"
  python3 <<PYEOF
import sys, re
tmpl = open("${tmpl}").read()
subs = {
  "project_title":  "${PROJECT_TITLE}",
  "project_name":   "${PROJECT_NAME}",
  "author":         "${AUTHOR}",
  "contact":        "${CONTACT}",
  "orcid":          "${ORCID}",
  "affiliation":    "${AFFILIATION}",
  "paper_title":    "${PAPER_TITLE}",
  "licence":        "${LICENCE}",
  "data_licence":   "${LICENCE_NAME}",
  "licence_name":   "${LICENCE_NAME}",
  "licence_url":    "${LICENCE_URL}",
  "resource_name":  "${RESOURCE_NAME}",
  "publisher":      "${PUBLISHER}",
  "catalogue_url":  "${CATALOGUE_URL}",
  "direct_url":     "${DIRECT_URL}",
  "sha256":         "${SHA256_PIN}",
  "size_bytes":     "${SIZE_BYTES}",
  "filename":       "${FILENAME}",
  "retrieved_at":   "${RETRIEVED_AT}",
  "build_date":     "${BUILD_DATE}",
  "bricklayer_version": "${BRICKLAYER_VERSION}",
  "bundle_filename": "${BASENAME}.zip",
  "bundle_sha256":  "(computed after build — see make_bundle.sh output)",
  "expected_pass_real": "see config.json",
  "expected_total":     "see config.json",
  "licence_attribution": "Refer to the OGL-Ontario terms",
  "network_endpoints_table": "See data_provenance.json for endpoints",
}
for k, v in subs.items():
    tmpl = tmpl.replace("{{" + k + "}}", str(v))
open("${out}", "w").write(tmpl)
PYEOF
}

render_template "${BRICKLAYER_ROOT}/bricklayer/templates/README.md.tmpl"       "${STAGE}/README.md"
render_template "${BRICKLAYER_ROOT}/bricklayer/templates/SECURITY.md.tmpl"     "${STAGE}/SECURITY.md"
render_template "${BRICKLAYER_ROOT}/bricklayer/templates/INSTRUCTIONS.txt.tmpl" "${STAGE}/INSTRUCTIONS.txt"

# --- Optionally vendor the data file ---
if [[ -n "${DATA_PATH}" ]]; then
  [[ ! -f "${DATA_PATH}" ]] && { echo "ERROR: --with-data file not found: ${DATA_PATH}"; exit 4; }
  TARGET_NAME="${FILENAME:-$(basename "${DATA_PATH}")}"
  cp "${DATA_PATH}" "${STAGE}/${TARGET_NAME}"
  render_template "${BRICKLAYER_ROOT}/bricklayer/templates/DATA_NOTICE.md.tmpl" "${STAGE}/DATA_NOTICE.md"
fi

# --- Make scripts executable ---
chmod +x "${STAGE}"/*.sh "${STAGE}"/*.command 2>/dev/null || true

# --- Zip up ---
DIST="${BRICKLAYER_ROOT}/dist"
mkdir -p "${DIST}"
ZIP_PATH="${DIST}/${BASENAME}.zip"
( cd "$(dirname "${STAGE}")" && zip -rq "${ZIP_PATH}" "$(basename "${STAGE}")" )
SHA="$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"

echo
echo "=========================================================="
echo "  ✓ BUILT  ${ZIP_PATH}  ($(wc -c < "${ZIP_PATH}" | tr -d ' ') bytes)"
echo "  SHA256:  ${SHA}"
echo "=========================================================="
echo "  Send this SHA256 to recipients out-of-band so they"
echo "  can verify the bundle wasn't tampered with in transit."

rm -rf "$(dirname "${STAGE}")"
