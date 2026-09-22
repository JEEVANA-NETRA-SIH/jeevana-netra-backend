#!/usr/bin/env bash
# =============================================================================
# Jeevana Netra — build the LINUX-compiled MATLAB service for Docker/Render.
#
# WHY LINUX? MATLAB Compiler (mcc) does NOT cross-compile: it only produces a
# binary for the OS it runs on. The Render container is Linux, so this script
# MUST run on a Linux x86_64 host with MATLAB R2026a installed and LICENSED
# (MATLAB Compiler + Deep Learning Toolbox + Image Processing Toolbox).
#
# License 40849457 is a named-user ONLINE license. On a fresh Linux machine a
# ONE-TIME activation with the MathWorks account is required (matlab -activate
# or the MATLAB GUI); after that `mcc` runs headless. In a MathWorks container
# (mathworks/matlab:r2026a) online licensing needs an interactive sign-in;
# alternatives there are a Network License Manager (`MLM_LICENSE_FILE=27000@h`)
# or a MATLAB Batch licensing token (`MLM_LICENSE_TOKEN`).
#
# OUTPUT: this copies the compiled artifact into ./matlab_service/ at the repo
# root (git-ignored, consumed by the Dockerfile). The Windows
# `jeevana_netra_service.exe` is NEVER used here — do not copy it into
# `matlab_service/`.
#
# USAGE:
#   sudo bash tools/build_linux_matlab_service.sh   # MATLAB on PATH
#   OR_MLMLICENSE_FILE=27000@host bash tools/build_linux_matlab_service.sh
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MB="$REPO_ROOT/matlab_backend"
BUILD_DIR="${TMPDIR:-/tmp}/jin-mcc-build"
OUT="$REPO_ROOT/matlab_service"

command -v matlab >/dev/null 2>&1 || {
    echo "ERROR: 'matlab' not on PATH — this must run on a Linux MATLAB host." >&2
    exit 1
}

echo "==> MATLAB release check (license/activation sanity)"
matlab -batch "v=ver('matlab'); fprintf('%s %s\n', v.Name, v.Release); exit(~fopen(which('mcc')))" \
    || { echo "ERROR: MATLAB or mcc not usable — check license/activation." >&2; exit 1; }

echo "==> Cleaning build dir: $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Compiling Linux MATLAB service (mcc -m)..."
cd "$MB"
mcc -m run_jeevana_service.m \
    jeevana_netra_api.m jeevana_netra_predict.m \
    preprocess_retinal_image.m prepare_jeevana_model_input.m \
    extract_lesion_evidence.m summarize_lesion_evidence.m \
    jeevana_report_api.m jeevana_report_json_api.m jeevana_netra_json_api.m \
    -a ResNet101_APTOS_Final_Trained.mat \
    -a IDRiD_Lesion_Evidence_ResNet101.mat \
    -a IDRiD_Lesion_Evidence_Thresholds.mat \
    -o jeevana_netra_service \
    -d "$BUILD_DIR"

echo "==> Installing into $OUT"
rm -rf "$OUT"
mkdir -p "$OUT"
if [ -d "$BUILD_DIR/jeevana_netra_service" ]; then
    cp -a "$BUILD_DIR/jeevana_netra_service/." "$OUT/"
else
    cp -a "$BUILD_DIR/." "$OUT/"
fi

echo "==> Artifact verification"
file "$OUT/jeevana_netra_service"
test -f "$OUT/jeevana_netra_service" || { echo "ERROR: binary missing" >&2; exit 1; }
if [ -f "$OUT/buildresult.json" ]; then
    echo "  buildresult.json present (can feed compiler.runtime.createDockerImage for a custom runtime image if desired)."
fi
ls -la "$OUT"

echo
echo "DONE. matlab_service/ now holds the Linux binary. Next steps (see DEPLOYMENT.md):"
echo "  1. docker build --build-arg MATLAB_RUNTIME_IMAGE=containers.mathworks.com/matlab-runtime:r2026a -t jeevana-netra-backend ."
echo "  2. Local Docker acceptance test (real /api/screen, /api/screenings, /api/report PDF)."
echo "  3. Only then: Render deployment."