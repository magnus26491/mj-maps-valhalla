#!/bin/bash
##
## MJ Maps Valhalla routing service — entrypoint
##
## First run: downloads UK OSM data and builds Valhalla tiles (~40-60 min).
## Subsequent runs: detects .tiles_complete marker on volume and skips build.
##
## Environment variables:
##   VALHALLA_REGION — Geofabrik filename under /europe/
##                     Default: great-britain-latest  (England + Wales + Scotland, ≈1.4 GB)
##                     Note: Geofabrik has no united-kingdom-latest file.
##                     For Ireland + NI use: ireland-and-northern-ireland-latest
##
set -euo pipefail
DATA_DIR="/data"
REGION="${VALHALLA_REGION:-great-britain-latest}"
PBF_URL="https://download.geofabrik.de/europe/${REGION}.osm.pbf"
PBF_PATH="${DATA_DIR}/${REGION}.osm.pbf"
CONFIG_PATH="${DATA_DIR}/valhalla.json"
TILES_DIR="${DATA_DIR}/valhalla_tiles"
COMPLETE_MARKER="${DATA_DIR}/.tiles_complete"
echo "[valhalla] Region:   ${REGION}"
echo "[valhalla] Data dir: ${DATA_DIR}"
# ── Check for existing tile build (volume cache) ──────────────────────────────
if [ -f "${COMPLETE_MARKER}" ]; then
  echo "[valhalla] Tiles already built — skipping build."
else
  echo "[valhalla] No tiles found — downloading and building."
  mkdir -p "${TILES_DIR}"
  # ── 1. Download PBF ─────────────────────────────────────────────────────────
  if [ -f "${PBF_PATH}" ]; then
    echo "[valhalla] PBF already downloaded — skipping."
  else
    echo "[valhalla] Downloading ${PBF_URL} ..."
    wget --no-verbose --show-progress \
         --tries=3 --timeout=300 \
         -O "${PBF_PATH}" \
         "${PBF_URL}"
    echo "[valhalla] Download complete: $(du -sh "${PBF_PATH}" | cut -f1)"
  fi
  # ── 2. Generate Valhalla config ──────────────────────────────────────────────
  echo "[valhalla] Generating config ..."
  valhalla_build_config \
    --mjolnir-tile-dir "${TILES_DIR}" \
    --mjolnir-timezone "${DATA_DIR}/timezones.sqlite" \
    --mjolnir-admin    "${DATA_DIR}/admins.sqlite" \
    > "${CONFIG_PATH}"
  # ── 3. Build admin database (country / border polygons) ─────────────────────
  echo "[valhalla] Building admin database ..."
  valhalla_build_admins -c "${CONFIG_PATH}" "${PBF_PATH}"
  # ── 4. Build timezone database ───────────────────────────────────────────────
  echo "[valhalla] Building timezone database ..."
  valhalla_build_timezones -c "${CONFIG_PATH}"
  # ── 5. Build routing tiles (longest step — ~40-60 min for UK) ───────────────
  echo "[valhalla] Building routing tiles ..."
  valhalla_build_tiles -c "${CONFIG_PATH}" "${PBF_PATH}"
  # ── 6. Mark complete and free disk space ────────────────────────────────────
  touch "${COMPLETE_MARKER}"
  echo "[valhalla] Cleaning up PBF (${PBF_PATH}) ..."
  rm -f "${PBF_PATH}"
  echo "[valhalla] Build complete."
fi
# ── Ensure config exists (regenerate after clean container restart) ───────────
if [ ! -f "${CONFIG_PATH}" ]; then
  echo "[valhalla] Regenerating config ..."
  valhalla_build_config \
    --mjolnir-tile-dir "${TILES_DIR}" \
    --mjolnir-timezone "${DATA_DIR}/timezones.sqlite" \
    --mjolnir-admin    "${DATA_DIR}/admins.sqlite" \
    > "${CONFIG_PATH}"
fi
# ── Start server ──────────────────────────────────────────────────────────────
echo "[valhalla] Starting valhalla_service on port 8002 ..."
exec valhalla_service "${CONFIG_PATH}" 1
