#!/bin/bash

# ============================================
# DLL Build Script for Hypergraph
# ============================================
# Compiles RGeoLib.dll (via xbuild/msbuild) and optional
# GeometryUtils.dll / DataNodeUtils.dll (via mcs).
# Copies built DLLs to dlls/main/ and dlls/reqs/ for
# Python (pythonnet) consumption.
#
# Usage:
#   ./build_dlls.sh            # incremental build
#   ./build_dlls.sh --clean    # wipe bin/obj first, then build
#   ./build_dlls.sh --help
# ============================================

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
HYPERGRAPH_DIR="$SCRIPT_DIR"

RGEOLIB_PROJECT="$HYPERGRAPH_DIR/ResearchGeometryLibrary/RGeoLib"
RGEOLIB_CSPROJ="$RGEOLIB_PROJECT/RGeoLib.csproj"
NUGET_PACKAGES_DIR="$HYPERGRAPH_DIR/RGeoTest/packages"
CONFIGURATION="Release"
BIN_DIR="$RGEOLIB_PROJECT/bin/$CONFIGURATION"
RGEOLIB_DLL="$BIN_DIR/RGeoLib.dll"

DLL_MAIN_DIR="$HYPERGRAPH_DIR/dlls/main"
DLL_REQS_DIR="$HYPERGRAPH_DIR/dlls/reqs"

GEOMETRYUTILS_CS="$RGEOLIB_PROJECT/GeometryUtils.cs"
DATANODEUTILS_CS="$RGEOLIB_PROJECT/DataNodeUtils.cs"

CLEAN=0
if [[ "$1" == "--clean" ]]; then
    CLEAN=1
elif [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 [--clean]"
    echo ""
    echo "  --clean   Remove bin/ and obj/ before building (full rebuild)"
    echo "  (default) Incremental build"
    exit 0
fi

echo "============================================"
echo " Hypergraph DLL Build"
echo "============================================"
echo "Project:       $RGEOLIB_PROJECT"
echo "Configuration: $CONFIGURATION"
echo "NuGet pkgs:    $NUGET_PACKAGES_DIR"
echo "Output:        $DLL_MAIN_DIR"
echo "               $DLL_REQS_DIR"
echo ""

# ------------------------------------------
# 1. Prerequisites
# ------------------------------------------
echo "[1/5] Checking prerequisites..."

BUILD_TOOL=""
if command -v xbuild &> /dev/null; then
    BUILD_TOOL="xbuild"
elif command -v msbuild &> /dev/null; then
    BUILD_TOOL="msbuild"
else
    echo "ERROR: Neither xbuild nor msbuild found."
    echo "  Install with: sudo apt-get install mono-xbuild"
    exit 1
fi
echo "  Build tool: $BUILD_TOOL"

if ! command -v mcs &> /dev/null; then
    echo "  WARNING: mcs not found — GeometryUtils/DataNodeUtils won't compile"
else
    echo "  mcs:        $(mcs --version 2>&1 | head -n1)"
fi

if ! command -v nuget &> /dev/null; then
    echo "  WARNING: nuget not found — package restore will be skipped"
    echo "           Install with: sudo apt-get install nuget"
fi

if [ ! -f "$RGEOLIB_CSPROJ" ]; then
    echo "ERROR: RGeoLib.csproj not found at $RGEOLIB_CSPROJ"
    exit 1
fi

echo ""

# ------------------------------------------
# 2. NuGet Restore
# ------------------------------------------
echo "[2/5] Restoring NuGet packages..."

if command -v nuget &> /dev/null; then
    nuget restore "$RGEOLIB_PROJECT/packages.config" \
        -PackagesDirectory "$NUGET_PACKAGES_DIR" \
        -NonInteractive 2>&1 | tail -3
    echo "  Done."
else
    echo "  Skipped (nuget not available)."
fi

echo ""

# ------------------------------------------
# 3. Build RGeoLib.dll
# ------------------------------------------
echo "[3/5] Building RGeoLib.dll ($CONFIGURATION)..."

if [[ "$CLEAN" -eq 1 ]]; then
    echo "  Cleaning bin/ and obj/..."
    rm -rf "$RGEOLIB_PROJECT/bin" "$RGEOLIB_PROJECT/obj"
fi

cd "$HYPERGRAPH_DIR/ResearchGeometryLibrary"
$BUILD_TOOL /p:Configuration=$CONFIGURATION RGeoLib/RGeoLib.csproj 2>&1 \
    | grep -E '(error CS|Build succeeded|Build FAILED|Warning\(s\)|Error\(s\)|Time Elapsed)'
cd "$SCRIPT_DIR"

if [ ! -f "$RGEOLIB_DLL" ]; then
    echo "ERROR: Build failed — $RGEOLIB_DLL not found"
    exit 1
fi

echo "  Built: $RGEOLIB_DLL ($(stat --printf='%s' "$RGEOLIB_DLL") bytes)"
echo ""

# ------------------------------------------
# 4. Deploy DLLs to runtime directories
# ------------------------------------------
echo "[4/5] Deploying DLLs..."

mkdir -p "$DLL_MAIN_DIR" "$DLL_REQS_DIR"

DLL_COUNT=0
for dll_file in "$BIN_DIR"/*.dll; do
    [ -f "$dll_file" ] || continue
    cp "$dll_file" "$DLL_REQS_DIR/"
    cp "$dll_file" "$DLL_MAIN_DIR/"
    DLL_COUNT=$((DLL_COUNT + 1))
done
echo "  Copied $DLL_COUNT DLLs to dlls/main/ and dlls/reqs/"

# ------------------------------------------
# 5. Compile optional custom DLLs (mcs)
# ------------------------------------------
echo ""
echo "[5/5] Compiling custom helper DLLs..."

if command -v mcs &> /dev/null; then
    if [ -f "$GEOMETRYUTILS_CS" ]; then
        mcs -t:library \
            -out:"$DLL_MAIN_DIR/GeometryUtils.dll" \
            -r:"$RGEOLIB_DLL" \
            "$GEOMETRYUTILS_CS" 2>&1
        echo "  GeometryUtils.dll  — OK"
    else
        echo "  GeometryUtils.cs not found, skipping"
    fi

    if [ -f "$DATANODEUTILS_CS" ]; then
        mcs -t:library \
            -out:"$DLL_MAIN_DIR/DataNodeUtils.dll" \
            -r:"$RGEOLIB_DLL" \
            -r:"$DLL_MAIN_DIR/GeometryUtils.dll" \
            "$DATANODEUTILS_CS" 2>&1
        echo "  DataNodeUtils.dll  — OK"
    else
        echo "  DataNodeUtils.cs not found, skipping"
    fi
else
    echo "  Skipped (mcs not available)"
fi

echo ""

# ------------------------------------------
# Summary
# ------------------------------------------
echo "============================================"
echo " Build Complete"
echo "============================================"

CHECKSUM=$(md5sum "$DLL_MAIN_DIR/RGeoLib.dll" | cut -d' ' -f1)
echo "  RGeoLib.dll    $(stat --printf='%s' "$DLL_MAIN_DIR/RGeoLib.dll") bytes  md5:${CHECKSUM:0:12}…"

[ -f "$DLL_MAIN_DIR/GeometryUtils.dll" ] && \
    echo "  GeometryUtils.dll  $(stat --printf='%s' "$DLL_MAIN_DIR/GeometryUtils.dll") bytes"
[ -f "$DLL_MAIN_DIR/DataNodeUtils.dll" ] && \
    echo "  DataNodeUtils.dll  $(stat --printf='%s' "$DLL_MAIN_DIR/DataNodeUtils.dll") bytes"

echo ""
echo "Verify in Python:"
echo "  python -c \"import sys; sys.path.insert(0,'$HYPERGRAPH_DIR'); from api.lib.tools import RGL; print('OK')\""
echo ""
