#!/bin/bash
#
# Makefile Generator for AutoHPL
# Generates platform-specific makefiles from template to avoid duplication
#

usage() {
    echo "Usage: $0 --template TEMPLATE_FILE --arch ARCH --blas-lib BLAS_LIB --mpi-inc MPI_INC --output OUTPUT_FILE"
    echo ""
    echo "Parameters:"
    echo "  --template   : Base makefile template"
    echo "  --arch       : Architecture name (e.g., Linux_Intel_openblas_rhel10)"
    echo "  --blas-lib   : BLAS library name (e.g., libopenblas.so.0 or libopenblaso.so.0)"
    echo "  --mpi-inc    : MPI include path (e.g., /usr/include/openmpi-x86_64)"
    echo "  --output     : Output makefile path"
    exit 1
}

# Parse arguments
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

# Perform substitutions
sed -e "s|^ARCH.*=.*Linux_.*|ARCH         = $ARCH|" \
    -e "s|^MPinc.*=.*-I/usr/include/openmpi.*|MPinc        = -I$MPI_INC|" \
    -e "s|LAlib.*=.*\$(LAdir)/lib.*\.so.*|LAlib        = \$(LAdir)/$BLAS_LIB|" \
    "$TEMPLATE" > "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "Makefile generated successfully: $OUTPUT"
    exit 0
else
    echo "Error: Failed to generate makefile"
    exit 1
fi
