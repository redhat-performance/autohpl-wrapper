#!/bin/bash
#
# MPI Setup Library for AutoHPL
# Centralizes all MPI configuration logic to eliminate code duplication
#

# Cache for OS detection to avoid repeated calls
DETECTED_OS=""
DETECTED_OS_VERSION=""

# Get OS name (cached)
get_os() {
    if [ -z "$DETECTED_OS" ]; then
        DETECTED_OS=$($TOOLS_BIN/detect_os)
    fi
    echo "$DETECTED_OS"
}

# Get OS version (cached)
get_os_version() {
    if [ -z "$DETECTED_OS_VERSION" ]; then
        DETECTED_OS_VERSION=$($TOOLS_BIN/detect_os --os-version)
    fi
    echo "$DETECTED_OS_VERSION"
}

# Setup SLES MPI environment
# SLES stores MPI in /usr/lib64/mpi/gcc/openmpi* which is not in PATH by default
setup_sles_mpi() {
    local include_cpath=${1:-false}  # Optional: add CPATH for compilation

    which mpirun > /dev/null 2>&1 && return 0  # Already configured

    # Find openmpi directory (could be openmpi4, openmpi5, etc.)
    local sles_mpi_dir=$(ls -d /usr/lib64/mpi/gcc/openmpi* 2>/dev/null | sort -V | tail -1)

    if [ -z "$sles_mpi_dir" ]; then
        echo "Error: No OpenMPI installation found in /usr/lib64/mpi/gcc/" >&2
        return 1
    fi

    echo "Setting up SLES MPI from: $sles_mpi_dir"
    export PATH=$sles_mpi_dir/bin:$PATH
    export LD_LIBRARY_PATH=$sles_mpi_dir/lib64:$LD_LIBRARY_PATH

    if [ "$include_cpath" = "true" ]; then
        export CPATH=$sles_mpi_dir/include:$CPATH
    fi

    # Verify mpirun is now available
    which mpirun > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: mpirun not found in PATH after SLES MPI setup" >&2
        return 1
    fi

    return 0
}

# Setup RHEL/CentOS MPI using environment modules (RHEL 8/9)
setup_rhel_module_mpi() {
    local arch=$1

    which mpirun > /dev/null 2>&1 && return 0  # Already configured

    if [ ! -f /etc/profile.d/modules.sh ]; then
        echo "Error: Environment modules not available (/etc/profile.d/modules.sh missing)" >&2
        return 1
    fi

    source /etc/profile.d/modules.sh
    module load mpi/openmpi-${arch}

    if [ $? -ne 0 ]; then
        echo "Error: module load mpi/openmpi-${arch} failed" >&2
        return 1
    fi

    which mpirun > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: mpirun not in PATH after loading module" >&2
        return 1
    fi

    return 0
}

# Setup RHEL 10+ MPI using direct PATH (no environment modules)
setup_rhel10_direct_mpi() {
    which mpirun > /dev/null 2>&1 && return 0  # Already configured

    # Try lib64 first (x86_64, aarch64), then lib (other architectures)
    if [ -d /usr/lib64/openmpi/bin ]; then
        export PATH=/usr/lib64/openmpi/bin:$PATH
        export LD_LIBRARY_PATH=/usr/lib64/openmpi/lib:$LD_LIBRARY_PATH
    elif [ -d /usr/lib/openmpi/bin ]; then
        export PATH=/usr/lib/openmpi/bin:$PATH
        export LD_LIBRARY_PATH=/usr/lib/openmpi/lib:$LD_LIBRARY_PATH
    else
        echo "Error: OpenMPI not found in /usr/lib64/openmpi or /usr/lib/openmpi" >&2
        return 1
    fi

    which mpirun > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: mpirun not found in PATH after RHEL 10 MPI setup" >&2
        return 1
    fi

    return 0
}

# Setup Amazon Linux MPI using environment modules
setup_amzn_module_mpi() {
    local arch=$1

    which mpirun > /dev/null 2>&1 && return 0  # Already configured

    if [ ! -f /etc/profile.d/modules.sh ]; then
        echo "Warning: Environment modules not available, MPI may need manual configuration" >&2
        return 0  # Don't fail, might work without modules
    fi

    source /etc/profile.d/modules.sh
    module load mpi/openmpi-${arch}

    if [ $? -ne 0 ]; then
        echo "Warning: module load mpi/openmpi-${arch} failed" >&2
        return 0  # Don't fail, continue
    fi

    return 0
}

# Main MPI setup dispatcher
# Determines OS and version, then calls appropriate setup function
setup_mpi_environment() {
    local arch=$1
    local include_cpath=${2:-false}

    local os=$(get_os)
    local os_ver=$(get_os_version)

    echo "Configuring MPI for OS: $os $os_ver, Architecture: $arch"

    case "$os" in
        sles)
            setup_sles_mpi "$include_cpath"
            return $?
            ;;
        rhel)
            # RHEL version-specific logic
            if [[ "$os_ver" == "10"* ]]; then
                setup_rhel10_direct_mpi
            elif [[ "$os_ver" == "8"* || "$os_ver" == "9"* ]]; then
                setup_rhel_module_mpi "$arch"
            else
                # Older RHEL, try modules
                setup_rhel_module_mpi "$arch"
            fi
            return $?
            ;;
        amzn)
            # Amazon Linux version-specific logic
            if [[ "$os_ver" == "2023"* || "$os_ver" == "2" ]]; then
                setup_amzn_module_mpi "$arch"
            fi
            return $?
            ;;
        ubuntu)
            # Ubuntu uses system paths, no special setup needed
            which mpirun > /dev/null 2>&1
            return $?
            ;;
        *)
            echo "Warning: Unknown OS '$os', skipping MPI environment setup" >&2
            return 0
            ;;
    esac
}

# Get MPI path for size_platform() function
# Returns the base MPI directory path for the current OS
get_mpi_path() {
    local os=$(get_os)
    local os_ver=$(get_os_version)

    case "$os" in
        sles)
            # Dynamic discovery for SLES
            local sles_mpi_dir=$(ls -d /usr/lib64/mpi/gcc/openmpi* 2>/dev/null | sort -V | tail -1)
            echo "$sles_mpi_dir"
            ;;
        rhel)
            echo "/usr/lib64/openmpi"
            ;;
        amzn)
            echo "/usr/lib64/openmpi/bin/"
            ;;
        ubuntu)
            echo "/usr/"
            ;;
        *)
            echo "/usr/"
            ;;
    esac
}

# Set runtime LD_LIBRARY_PATH for MPI (needed for RHEL 10)
set_mpi_runtime_library_path() {
    local os=$(get_os)
    local os_ver=$(get_os_version)

    # RHEL 10 needs explicit LD_LIBRARY_PATH for runtime
    if [[ "$os" == "rhel" && "$os_ver" == "10"* ]]; then
        if [ -d /usr/lib64/openmpi/lib ]; then
            export LD_LIBRARY_PATH=/usr/lib64/openmpi/lib:$LD_LIBRARY_PATH
        fi
    fi
}

# Get makefile suffix for current OS/version
get_makefile_suffix() {
    local blaslib=$1
    local os=$(get_os)
    local os_ver=$(get_os_version)

    case "$os" in
        ubuntu)
            echo "_ubuntu"
            ;;
        sles)
            echo "_sles"
            ;;
        rhel)
            if [[ "$os_ver" == "9"* && "$blaslib" == "Intel_openblas" ]]; then
                echo "_rhel9"
            elif [[ "$os_ver" == "10"* ]]; then
                echo "_rhel10"
            else
                echo ""
            fi
            ;;
        amzn)
            # Check if aws variable is set (legacy detection)
            if [ "${aws:-0}" -eq 1 ]; then
                echo "_aws"
            else
                echo ""
            fi
            ;;
        *)
            echo ""
            ;;
    esac
}

# Check if OpenBLAS should be compiled from source
should_compile_openblas_from_source() {
    local os=$(get_os)
    local os_ver=$(get_os_version)

    # Only Amazon Linux 2 compiles from source
    if [[ "$os" == "amzn" && "$os_ver" == "2" ]]; then
        return 0  # true
    fi
    return 1  # false
}
