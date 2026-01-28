# Platform Configuration Reference

This document describes platform-specific configurations for AutoHPL builds.

## RHEL (Red Hat Enterprise Linux)

### RHEL 8
- **MPI Setup Method:** Environment modules (`mpi/openmpi-${arch}`)
- **BLAS Library:** `libopenblas.so.0`
- **Makefile Suffix:** _(none)_

### RHEL 9
- **MPI Setup Method:** Environment modules (`mpi/openmpi-${arch}`)
- **BLAS Library:** `libopenblaso.so.0` (FlexiBLAS)
- **Makefile Suffix:** `_rhel9`

### RHEL 10
- **MPI Setup Method:** Direct PATH setup
- **MPI Paths:** `/usr/lib64/openmpi`, `/usr/lib/openmpi`
- **BLAS Library:** `libopenblaso.so.0` (FlexiBLAS)
- **Makefile Suffix:** `_rhel10`

## Amazon Linux

### Amazon Linux 2
- **MPI Setup Method:** Environment modules (`mpi/openmpi-${arch}`)
- **BLAS Library:** `libopenblas.so.0`
- **Makefile Suffix:** `_aws`
- **Special:** Compiles OpenBLAS from source (no package installation)

### Amazon Linux 2023
- **MPI Setup Method:** Environment modules (`mpi/openmpi-${arch}`)
- **BLAS Library:** `libopenblas.so.0`
- **Makefile Suffix:** _(none)_

## SLES (SUSE Linux Enterprise Server)

### SLES 15 (all versions)
- **MPI Setup Method:** Dynamic discovery
- **MPI Search Pattern:** `/usr/lib64/mpi/gcc/openmpi*`
- **BLAS Library:** `libopenblas.so.0`
- **Makefile Suffix:** `_sles`
- **Notes:** MPI not in PATH by default, must be configured

## Ubuntu

### Ubuntu 20.04, 22.04
- **MPI Setup Method:** System paths (MPI in default PATH)
- **BLAS Library:** `libopenblas.so.0`
- **Makefile Suffix:** `_ubuntu`

---

## MPI Include Paths by Architecture

| Architecture | Include Path |
|--------------|-------------|
| x86_64 | `/usr/include/openmpi-x86_64` |
| aarch64 (ARM) | `/usr/include/openmpi-aarch64` |
| Other | `/usr/include/openmpi` |

---

## Implementation Details

The platform-specific logic is implemented in:
- **`mpi_setup_lib.sh`** - MPI setup methods, makefile suffixes, compile checks
- **`build_run_hpl.sh`** - BLAS library detection, MPI include paths

See these files for the actual implementation of the configurations described above.

---

## Adding New Platform Support

To add a new OS or version:

1. Determine the platform characteristics:
   - How is MPI configured? (modules, direct PATH, dynamic discovery)
   - What BLAS library name? (`libopenblas.so.0` vs `libopenblaso.so.0`)
   - Does it need a special makefile suffix?
   - Any special cases? (compile from source, etc.)

2. Update `mpi_setup_lib.sh`:
   - Add OS/version case in `setup_mpi_environment()`
   - Add makefile suffix in `get_makefile_suffix()`
   - Add special cases if needed

3. Update `build_run_hpl.sh` if needed:
   - BLAS library name detection (lines 520-529)
   - MPI include path if non-standard

4. Update this documentation file

---

## Platform Support Matrix

| OS | Version | Architecture | MPI Method | BLAS Library | Status |
|----|---------|--------------|------------|--------------|--------|
| RHEL | 8 | x86_64, aarch64 | Modules | libopenblas.so.0 | ✅ Supported |
| RHEL | 9 | x86_64, aarch64 | Modules | libopenblaso.so.0 | ✅ Supported |
| RHEL | 10 | x86_64, aarch64 | Direct PATH | libopenblaso.so.0 | ✅ Supported |
| Amazon Linux | 2 | x86_64, aarch64 | Modules | libopenblas.so.0 | ✅ Supported |
| Amazon Linux | 2023 | x86_64, aarch64 | Modules | libopenblas.so.0 | ✅ Supported |
| SLES | 15 | x86_64, aarch64 | Dynamic | libopenblas.so.0 | ✅ Supported |
| Ubuntu | 20.04, 22.04 | x86_64, aarch64 | System | libopenblas.so.0 | ✅ Supported |
