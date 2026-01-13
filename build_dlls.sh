#!/bin/bash

# ============================================
# DLL Compilation Script for Hypergraph
# ============================================
# This script compiles custom C# DLLs for the hypergraph project
# - RGeoLib.dll (if not already built)
# - GeometryUtils.dll (requires RGeoLib.dll)
# - DataNodeUtils.dll (if source exists)
# ============================================

set -e  # Exit on error

# Get the directory where this script is located (hypergraph folder)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
HYPERGRAPH_DIR="$SCRIPT_DIR"

# Project paths
RGEOLIB_PROJECT="$HYPERGRAPH_DIR/ResearchGeometryLibrary/RGeoLib"
RGEOLIB_DLL="$RGEOLIB_PROJECT/bin/Debug/RGeoLib.dll"

# Source files
GEOMETRYUTILS_CS="$RGEOLIB_PROJECT/GeometryUtils.cs"

# Output paths
DLL_OUTPUT_DIR="$HYPERGRAPH_DIR/dlls/main"
DLL_REQS_DIR="$HYPERGRAPH_DIR/dlls/reqs"
RGEOLIB_COPY_DIR="$HYPERGRAPH_DIR/dlls/main"

# Compiled DLL paths
GEOMETRYUTILS_DLL="$DLL_OUTPUT_DIR/GeometryUtils.dll"

echo "============================================"
echo "Hypergraph DLL Compilation"
echo "============================================"
echo "Hypergraph directory: $HYPERGRAPH_DIR"
echo "RGeoLib project: $RGEOLIB_PROJECT"
echo "Output directory: $DLL_OUTPUT_DIR"
echo ""

# ============================================
# Step 1: Check Prerequisites
# ============================================
echo "[1/5] Checking prerequisites..."

# Check for Mono C# compiler
if ! command -v mcs &> /dev/null; then
    echo "✗ Error: Mono C# compiler (mcs) not found"
    echo "  Install with: sudo apt-get install mono-mcs"
    exit 1
fi
echo "✓ Mono C# compiler found: $(mcs --version | head -n 1)"

# Check for xbuild (for building .csproj files)
if ! command -v xbuild &> /dev/null && ! command -v msbuild &> /dev/null; then
    echo "⚠ Warning: xbuild/msbuild not found (needed for .csproj builds)"
    echo "  Install with: sudo apt-get install mono-xbuild"
fi

echo ""

# ============================================
# Step 2: Restore NuGet Packages
# ============================================
echo "[2/5] Restoring NuGet packages..."

if [ -f "$RGEOLIB_PROJECT/RGeoLib.csproj" ]; then
    cd "$RGEOLIB_PROJECT"
    
    # Restore NuGet packages (downloads third-party DLLs)
    if command -v nuget &> /dev/null; then
        echo "Restoring NuGet dependencies..."
        nuget restore RGeoLib.csproj -PackagesDirectory ./packages
        echo "✓ NuGet packages restored"
    else
        echo "⚠ Warning: nuget command not found, attempting build without explicit restore"
        echo "  Install with: sudo apt-get install nuget"
    fi
    
    cd "$SCRIPT_DIR"
else
    echo "✗ Error: RGeoLib.csproj not found at $RGEOLIB_PROJECT"
    exit 1
fi

echo ""

# ============================================
# Step 3: Build RGeoLib.dll (if needed)
# ============================================
echo "[3/5] Building RGeoLib.dll..."

if [ ! -f "$RGEOLIB_DLL" ]; then
    echo "RGeoLib.dll not found, attempting to build..."
    
    if [ -f "$RGEOLIB_PROJECT/RGeoLib.csproj" ]; then
        cd "$RGEOLIB_PROJECT"
        
        # Try xbuild first (older Mono), then msbuild
        if command -v xbuild &> /dev/null; then
            xbuild /p:Configuration=Debug RGeoLib.csproj
        elif command -v msbuild &> /dev/null; then
            msbuild /p:Configuration=Debug RGeoLib.csproj
        else
            echo "✗ Error: Cannot build RGeoLib.csproj without xbuild or msbuild"
            exit 1
        fi
        
        cd "$SCRIPT_DIR"
        
        if [ -f "$RGEOLIB_DLL" ]; then
            echo "✓ RGeoLib.dll built successfully"
        else
            echo "✗ Error: RGeoLib.dll build failed"
            exit 1
        fi
    else
        echo "✗ Error: RGeoLib.csproj not found at $RGEOLIB_PROJECT"
        exit 1
    fi
else
    echo "✓ RGeoLib.dll already exists"
fi

# Copy RGeoLib.dll and all dependency DLLs to dlls/main and dlls/reqs
echo "  Copying DLLs to output directories..."
mkdir -p "$RGEOLIB_COPY_DIR"
mkdir -p "$DLL_REQS_DIR"

# Get the bin/Debug directory where all DLLs are
BIN_DEBUG_DIR="$(dirname "$RGEOLIB_DLL")"

# Copy all .dll files from bin/Debug to both dlls/main and dlls/reqs
# This includes RGeoLib.dll and all NuGet dependencies
DLL_COUNT=0
for dll_file in "$BIN_DEBUG_DIR"/*.dll; do
    if [ -f "$dll_file" ]; then
        cp "$dll_file" "$RGEOLIB_COPY_DIR/"
        cp "$dll_file" "$DLL_REQS_DIR/"
        DLL_COUNT=$((DLL_COUNT + 1))
    fi
done

echo "✓ Copied $DLL_COUNT DLLs to dlls/main/ and dlls/reqs/"
echo "  (includes RGeoLib and all NuGet dependencies)"

echo ""

# ============================================
# Step 4: Compile GeometryUtils.dll
# ============================================
echo "[4/5] Compiling GeometryUtils.dll..."

if [ ! -f "$GEOMETRYUTILS_CS" ]; then
    echo "⚠ Warning: GeometryUtils.cs not found at $GEOMETRYUTILS_CS"
    echo "  Skipping GeometryUtils.dll compilation"
else
    echo "Found GeometryUtils.cs, compiling..."
    
    # Create output directory if it doesn't exist
    mkdir -p "$DLL_OUTPUT_DIR"
    
    # Compile GeometryUtils.dll with reference to RGeoLib.dll
    mcs -t:library \
        -out:"$GEOMETRYUTILS_DLL" \
        -r:"$RGEOLIB_DLL" \
        "$GEOMETRYUTILS_CS"
    
    if [ -f "$GEOMETRYUTILS_DLL" ]; then
        echo "✓ GeometryUtils.dll compiled successfully"
        echo "  Location: $GEOMETRYUTILS_DLL"
    else
        echo "✗ Error: GeometryUtils.dll compilation failed"
        exit 1
    fi
fi

echo ""

# ============================================
# Step 5: Compile DataNodeUtils.dll (if source exists)
# ============================================
echo "[5/5] Checking for additional custom DLLs..."

DATANODEUTILS_CS="$RGEOLIB_PROJECT/DataNodeUtils.cs"
DATANODEUTILS_DLL="$DLL_OUTPUT_DIR/DataNodeUtils.dll"

if [ -f "$DATANODEUTILS_CS" ]; then
    echo "Found DataNodeUtils.cs, compiling..."
    
    # DataNodeUtils depends on both RGeoLib and GeometryUtils
    mcs -t:library \
        -out:"$DATANODEUTILS_DLL" \
        -r:"$RGEOLIB_DLL" \
        -r:"$GEOMETRYUTILS_DLL" \
        "$DATANODEUTILS_CS"
    
    if [ -f "$DATANODEUTILS_DLL" ]; then
        echo "✓ DataNodeUtils.dll compiled successfully"
    else
        echo "⚠ Warning: DataNodeUtils.dll compilation failed"
    fi
else
    echo "No additional custom C# source files found"
fi

echo ""

# ============================================
# Summary
# ============================================
echo "============================================"
echo "Compilation Complete!"
echo "============================================"
echo ""
echo "Compiled DLLs in: $DLL_OUTPUT_DIR"
echo ""
echo "Custom DLLs:"
[ -f "$RGEOLIB_DLL" ] && echo "  ✓ RGeoLib.dll"
[ -f "$GEOMETRYUTILS_DLL" ] && echo "  ✓ GeometryUtils.dll"
[ -f "$DATANODEUTILS_DLL" ] && echo "  ✓ DataNodeUtils.dll"
echo ""
echo "Note: Third-party DLLs (Accord, NPOI, Supabase, etc.) are"
echo "      dependencies managed by NuGet and already in dlls/main/"
echo ""
echo "To use in Python:"
echo "  1. Activate your environment: source /path/to/.venv/bin/activate"
echo "  2. Ensure pythonnet is installed: pip install pythonnet"
echo "  3. Import in Python:"
echo "     import sys, clr"
echo "     clr.AddReference('$DLL_OUTPUT_DIR/GeometryUtils')"
echo "     from RGeoLib import GeometryUtils"
echo ""
