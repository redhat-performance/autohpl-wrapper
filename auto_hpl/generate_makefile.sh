#!/bin/bash
#
# Makefile Generator for AutoHPL
# Generates platform-specific makefiles from template to avoid duplication
#

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
    sed -e "s|^ARCH.*=.*Linux_.*|ARCH         = $ARCH|" \
        -e "s|^MPinc.*=.*-I/usr/include/openmpi.*|MPinc        = -I$MPI_INC|" \
        -e "s|^LAdir.*=.*|LAdir        = $BLAS_DIR|" \
        -e "s|LAlib.*=.*\$(LAdir)/lib.*\.\(so\|a\).*|LAlib        = \$(LAdir)/lib/$BLAS_LIB|" \
        "$TEMPLATE" > "$OUTPUT"
else
    # For system libraries (OpenBLAS/FlexiBLAS)
    sed -e "s|^ARCH.*=.*Linux_.*|ARCH         = $ARCH|" \
        -e "s|^MPinc.*=.*-I/usr/include/openmpi.*|MPinc        = -I$MPI_INC|" \
        -e "s|LAlib.*=.*\$(LAdir)/.*\.\(so\|a\).*|LAlib        = \$(LAdir)/$BLAS_LIB|" \
        "$TEMPLATE" > "$OUTPUT"
fi

if [ $? -eq 0 ]; then
    echo "Makefile generated successfully: $OUTPUT"
    exit 0
else
    echo "Error: Failed to generate makefile"
    exit 1
fi
