#!/bin/bash
#
# Makefile Generator for AutoHPL
# Generates platform-specific makefiles from template to avoid duplication
#

source $TOOLS_BIN/error_codes
usage() {
    echo "Usage: $0 --template TEMPLATE_FILE --arch ARCH --blas-lib BLAS_LIB --mpi-inc MPI_INC --output OUTPUT_FILE [--blas-dir BLAS_DIR]"
    echo ""
    echo "Parameters:"
    echo "  --template   : Base makefile template"
    echo "  --arch       : Architecture name (e.g., Linux_Intel_openblas_rhel10)"
    echo "  --blas-lib   : BLAS library name (e.g., libopenblas.so.0 or libblis-mt.a)"
    echo "  --mpi-inc    : MPI include path (e.g., /usr/include/openmpi-x86_64)"
    echo "  --output     : Output makefile path"
    echo "  --blas-dir   : Optional BLAS library directory (for BLIS custom builds)"
    exit 1
}

# Parse arguments
BLAS_DIR=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --template)
            TEMPLATE="$2"
            shift 2
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --blas-lib)
            BLAS_LIB="$2"
            shift 2
            ;;
        --mpi-inc)
            MPI_INC="$2"
            shift 2
            ;;
        --output)
            OUTPUT="$2"
            shift 2
            ;;
        --blas-dir)
            BLAS_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            usage
            ;;
    esac
done

# Validate required parameters
if [ -z "$TEMPLATE" ] || [ -z "$ARCH" ] || [ -z "$BLAS_LIB" ] || [ -z "$MPI_INC" ] || [ -z "$OUTPUT" ]; then
    echo "Error: Missing required parameters"
    usage
fi

if [ ! -f "$TEMPLATE" ]; then
    echo "Error: Template file '$TEMPLATE' not found"
    exit 1
fi

# Generate makefile from template
echo "Generating makefile: $OUTPUT"
echo "  Architecture: $ARCH"
echo "  BLAS Library: $BLAS_LIB"
echo "  MPI Include:  $MPI_INC"
if [ -n "$BLAS_DIR" ]; then
    echo "  BLAS Dir:     $BLAS_DIR"
fi

# Perform substitutions
# Handle both .so (shared) and .a (static) libraries
if [ -n "$BLAS_DIR" ]; then
    # For BLIS with custom directory
    # Check if Ubuntu for MPI path
    if [[ "$MPI_INC" == *"x86_64-linux-gnu"* ]]; then
        # Ubuntu x86_64
        sed -e "s|^ARCH.*=.*Linux_.*|ARCH         = $ARCH|" \
            -e "s|^MPdir.*=.*|MPdir        = /usr/lib/x86_64-linux-gnu/openmpi|" \
            -e "s|^MPinc.*=.*-I/usr/include/openmpi.*|MPinc        = -I$MPI_INC|" \
            -e "s|^LAdir.*=.*|LAdir        = $BLAS_DIR|" \
            -e "s|^LAlib.*=.*|LAlib        = \$(LAdir)/lib/$BLAS_LIB|" \
            "$TEMPLATE" > "$OUTPUT"
    elif [[ "$MPI_INC" == *"aarch64-linux-gnu"* ]]; then
        # Ubuntu aarch64
        sed -e "s|^ARCH.*=.*Linux_.*|ARCH         = $ARCH|" \
            -e "s|^MPdir.*=.*|MPdir        = /usr/lib/aarch64-linux-gnu/openmpi|" \
            -e "s|^MPinc.*=.*-I/usr/include/openmpi.*|MPinc        = -I$MPI_INC|" \
            -e "s|^LAdir.*=.*|LAdir        = $BLAS_DIR|" \
            -e "s|^LAlib.*=.*|LAlib        = \$(LAdir)/lib/$BLAS_LIB|" \
            "$TEMPLATE" > "$OUTPUT"
    elif [[ "$MPI_INC" == *"/mpi/gcc/openmpi"* ]]; then
        # SLES uses /usr/lib64/mpi/gcc/openmpi* path with lib64 subdirectory
        # Extract MPdir from MPI_INC by removing /include suffix
        SLES_MPI_DIR="${MPI_INC%/include}"
        sed -e "s|^ARCH.*=.*Linux_.*|ARCH         = $ARCH|" \
            -e "s|^MPdir.*=.*|MPdir        = $SLES_MPI_DIR|" \
            -e "s|^MPinc.*=.*-I/usr/include/openmpi.*|MPinc        = -I$MPI_INC|" \
            -e "s|^MPlib.*=.*\$(MPdir)/lib/.*|MPlib        = \$(MPdir)/lib64/libmpi.so|" \
            -e "s|^LAdir.*=.*|LAdir        = $BLAS_DIR|" \
            -e "s|^LAlib.*=.*|LAlib        = \$(LAdir)/lib/$BLAS_LIB|" \
            "$TEMPLATE" > "$OUTPUT"
    else
        # RHEL, Amazon Linux
        sed -e "s|^ARCH.*=.*Linux_.*|ARCH         = $ARCH|" \
            -e "s|^MPinc.*=.*-I/usr/include/openmpi.*|MPinc        = -I$MPI_INC|" \
            -e "s|^LAdir.*=.*|LAdir        = $BLAS_DIR|" \
            -e "s|^LAlib.*=.*|LAlib        = \$(LAdir)/lib/$BLAS_LIB|" \
            "$TEMPLATE" > "$OUTPUT"
    fi
else
    # For system libraries (OpenBLAS/FlexiBLAS)
    # Detect if Ubuntu - needs different library paths
    if [[ "$MPI_INC" == *"x86_64-linux-gnu"* ]]; then
        # Ubuntu x86_64 uses multiarch paths
        sed -e "s|^ARCH.*=.*Linux_.*|ARCH         = $ARCH|" \
            -e "s|^MPdir.*=.*|MPdir        = /usr/lib/x86_64-linux-gnu/openmpi|" \
            -e "s|^MPinc.*=.*-I/usr/include/openmpi.*|MPinc        = -I$MPI_INC|" \
            -e "s|^LAdir.*=.*|LAdir        = /usr/lib/x86_64-linux-gnu|" \
            -e "s|^LAlib.*=.*|LAlib        = \$(LAdir)/$BLAS_LIB|" \
            "$TEMPLATE" > "$OUTPUT"
    elif [[ "$MPI_INC" == *"aarch64-linux-gnu"* ]]; then
        # Ubuntu aarch64 uses multiarch paths
        sed -e "s|^ARCH.*=.*Linux_.*|ARCH         = $ARCH|" \
            -e "s|^MPdir.*=.*|MPdir        = /usr/lib/aarch64-linux-gnu/openmpi|" \
            -e "s|^MPinc.*=.*-I/usr/include/openmpi.*|MPinc        = -I$MPI_INC|" \
            -e "s|^LAdir.*=.*|LAdir        = /usr/lib/aarch64-linux-gnu|" \
            -e "s|^LAlib.*=.*|LAlib        = \$(LAdir)/$BLAS_LIB|" \
            "$TEMPLATE" > "$OUTPUT"
    elif [[ "$MPI_INC" == *"/mpi/gcc/openmpi"* ]]; then
        # SLES uses /usr/lib64/mpi/gcc/openmpi* path with lib64 subdirectory
        # Extract MPdir from MPI_INC by removing /include suffix
        SLES_MPI_DIR="${MPI_INC%/include}"
        sed -e "s|^ARCH.*=.*Linux_.*|ARCH         = $ARCH|" \
            -e "s|^MPdir.*=.*|MPdir        = $SLES_MPI_DIR|" \
            -e "s|^MPinc.*=.*-I/usr/include/openmpi.*|MPinc        = -I$MPI_INC|" \
            -e "s|^MPlib.*=.*\$(MPdir)/lib/.*|MPlib        = \$(MPdir)/lib64/libmpi.so|" \
            -e "s|^LAlib.*=.*|LAlib        = \$(LAdir)/$BLAS_LIB|" \
            "$TEMPLATE" > "$OUTPUT"
    else
        # RHEL, Amazon Linux use standard paths
        sed -e "s|^ARCH.*=.*Linux_.*|ARCH         = $ARCH|" \
            -e "s|^MPinc.*=.*-I/usr/include/openmpi.*|MPinc        = -I$MPI_INC|" \
            -e "s|^LAlib.*=.*|LAlib        = \$(LAdir)/$BLAS_LIB|" \
            "$TEMPLATE" > "$OUTPUT"
    fi
fi

if [ $? -eq 0 ]; then
    echo "Makefile generated successfully: $OUTPUT"
    exit 0
else
    echo "Error: Failed to generate makefile"
    exit 1
fi
