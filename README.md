# HPL (High Performance LINPACK) Benchmark Wrapper

## Description

This wrapper automates running the HPL (High Performance LINPACK) benchmark, a widely used measure of a system's floating-point computing power. HPL solves a dense system of linear equations and reports performance in GFLOPS (billions of floating-point operations per second).

The wrapper provides:
- Automated HPL download, build, and execution
- Support for multiple BLAS libraries (AMD BLIS, Intel MKL, OpenBLAS)
- Automatic problem sizing based on system memory
- Support for x86_64 (AMD/Intel) and aarch64 (ARM) architectures
- Automatic MPI process grid calculation (P x Q)
- Result collection, processing, and verification
- CSV and JSON output formats
- System configuration metadata capture
- Integration with test_tools framework
- Optional Performance Co-Pilot (PCP) integration

## What the Script Does

The `build_run_hpl.sh` script performs the following workflow:

1. **Environment Setup**:
   - Clones the test_tools-wrappers repository if not present (default: ~/test_tools)
   - Sources error codes and general setup utilities
   - Sets up MPI environment using centralized configuration

2. **Package Installation**:
   - Installs required dependencies via package_tool (gcc, make, gfortran, wget, etc.)
   - Dependencies are defined in general_packages.json and openblas_packages.json for different OS variants (RHEL, Ubuntu, SLES, Amazon Linux)

3. **BLAS Library Selection**:
   - **AMD Systems**: Uses AMD BLIS (with `--use_blis`) or OpenBLAS (default)
   - **Intel Systems**: Uses Intel MKL (with `--use_mkl`) or OpenBLAS (default)
   - **ARM Systems**: Uses OpenBLAS with OpenMP

4. **Library Build/Installation**:
   - For AMD BLIS: Clones and builds from source with OpenMP support
   - For Intel MKL: Installs from Intel repositories
   - For OpenBLAS: Installs from system packages or builds from source (Amazon Linux 2)

5. **HPL Build**:
   - Downloads HPL 2.3 from netlib.org
   - Generates architecture-specific Makefile using generate_makefile.sh
   - Detects MPI include paths for different OS/architecture combinations
   - Compiles HPL binary (xhpl) with selected BLAS library

6. **Problem Sizing**:
   - Automatically detects system memory and CPU topology
   - Calculates problem size (N) to use ~86% of available memory
   - Determines optimal block size (NB) based on CPU family/model
   - Calculates MPI process grid (P x Q) for optimal performance
   - Determines OpenMP thread count based on cache topology

7. **Test Execution**:
   - Generates HPL.dat input file with calculated parameters
   - Runs HPL with optimized MPI process binding
   - Executes for specified number of iterations
   - Captures performance results (time and GFLOPS)

8. **Data Collection**:
   - Captures system configuration (CPU, memory, NUMA topology, kernel version)
   - Records HPL configuration parameters (N, NB, P, Q)
   - Logs timestamps for each test run
   - Optionally records PCP performance data

9. **Result Processing**:
   - Extracts performance metrics from HPL output
   - Generates CSV files with configuration and performance data
   - Creates JSON output for verification
   - Validates results against Pydantic schema

10. **Verification**:
    - Validates results against Pydantic schema (result_schema.py)
    - Ensures all required fields are present and valid
    - Uses csv_to_json and verify_results from test_tools

11. **Output**:
    - Creates timestamped results directory: `results_auto_hpl_<tuned_setting>_<YYYYMMDDHHMMSS>`
    - Saves all raw output files, processed CSV/JSON, and system metadata
    - Optionally saves PCP performance data
    - Archives results to configured storage location

## Dependencies

Location of underlying workload: Downloaded from http://www.netlib.org/benchmark/hpl/hpl-2.3.tar.gz

**General packages required**: gcc, make, gcc-gfortran, wget, bc, perf, git, zip, unzip, numactl, dmidecode

**Additional packages for OpenBLAS builds**:
- RHEL: flexiblas, flexiblas-devel, flexiblas-openblas-openmp, openmpi, openmpi-devel
- Ubuntu: libopenblas-dev, libopenblas-openmp-dev, openmpi-bin, openmpi-common, libopenmpi-dev
- SLES: openblas-devel, openmpi, openmpi-devel
- Amazon Linux: openblas-devel (or built from source), openmpi, openmpi-devel

**BLAS Library Options**:
- **AMD BLIS**: Built from source (https://github.com/amd/blis.git)
- **Intel MKL**: Installed from Intel repositories
- **OpenBLAS**: Installed from system packages or built from source

To run:
```bash
git clone https://github.com/redhat-performance/autohpl-wrapper
cd autohpl-wrapper/auto_hpl
./build_run_hpl.sh
```

The script will automatically detect your CPU architecture and select appropriate defaults.

## The HPL Benchmark

HPL (High Performance LINPACK) is a benchmark that solves a dense system of linear equations:

**Ax = b**

Where:
- **A** is an N×N matrix of double-precision floating-point numbers
- **x** and **b** are vectors of length N
- The benchmark measures the time to solve for x using LU factorization with partial pivoting

### Key HPL Parameters

1. **N (Problem Size)**: The dimension of the matrix. Larger N uses more memory and takes longer to solve, but can achieve higher performance. This wrapper sets N to use approximately 86% of available memory.

2. **NB (Block Size)**: The size of blocks used in the LU factorization. Optimal values depend on CPU cache architecture:
   - AMD Naples: 232
   - AMD Rome/Milan/Genoa: 224
   - AMD Bergamo: 384
   - Intel (all models): 256
   - ARM (default): 256

3. **P and Q (Process Grid)**: The number of MPI processes in the row and column dimensions. P × Q = total MPI processes. The wrapper calculates P and Q to be as close as possible (creating a square grid) while satisfying P ≤ Q.

4. **Performance Metric**: HPL reports performance in **GFLOPS** (billions of floating-point operations per second). Higher values indicate better performance.

The actual computation is: `(2/3 × N³ + 2 × N²) / time` floating-point operations per second.

## Results Schema

The wrapper validates results using a Pydantic schema that requires:
- **TV**: String describing test variant/status
- **N**: Integer problem size > 0
- **NB**: Integer block size > 0
- **P**: Integer row process count > 0
- **Q**: Integer column process count > 0
- **Time**: Float execution time > 0 (seconds)
- **Gflops**: Float performance > 0 (billions of FLOPS)
- **Start_Date**: Datetime timestamp
- **End_Date**: Datetime timestamp

## Output Files

The results directory contains:

- **results_auto_hpl.csv**: CSV file with HPL configuration and performance metrics
- **hpl-\<blaslib\>-\*.log**: Raw output files from HPL runs showing detailed results
- **hpl_make.out**: HPL compilation output
- **blis_*.out** (if using BLIS): BLIS library build output
- **HPL.dat**: Generated HPL input configuration file
- **meta_data*.yml**: System metadata (CPU info, memory, NUMA topology, kernel version)
- **PCP data** (if --use_pcp option used): Performance Co-Pilot monitoring data

## Command-Line Options

```
Auto HPL Options:
  --mem_size <value>: Designate the size of memory to work with (in GiB).
      Overrides automatic memory detection. Useful for testing with reduced memory.
  --sleep_between_runs <value>: Sleep this number of seconds before starting the next run.
      Useful for allowing system to stabilize between iterations.
  --use_mkl: Use Intel MKL library (Intel CPUs only).
  --use_blis: Use AMD BLIS library (AMD CPUs only).
  --regression: Limit the amount of memory for regression testing (uses N/4).

General test_tools options:
  --home_parent <value>: Parent home directory. If not set, defaults to current working directory.
  --host_config <value>: Host configuration name, defaults to current hostname.
  --iterations <value>: Number of times to run the test, defaults to 1.
  --run_user: User that is actually running the test on the test system. Defaults to current user.
  --sys_type: Type of system working with (aws, azure, hostname). Defaults to hostname.
  --sysname: Name of the system running, used in determining config files. Defaults to hostname.
  --tuned_setting: Used in naming the results directory. For RHEL, defaults to current active tuned profile.
      For non-RHEL systems, defaults to 'none'.
  --use_pcp: Enable Performance Co-Pilot monitoring during test execution.
  --tools_git <value>: Git repo to retrieve the required tools from.
      Default: https://github.com/redhat-performance/test_tools-wrappers
  --usage: Display this usage message.
```

## Examples

### Basic run with defaults (OpenBLAS)
```bash
./build_run_hpl.sh
```
This runs with:
- Automatic BLAS library selection (OpenBLAS for most systems)
- Automatic memory sizing (86% of total RAM)
- 1 iteration
- Automatic problem sizing and MPI grid calculation

### Run with AMD BLIS library
```bash
./build_run_hpl.sh --use_blis
```
Uses AMD-optimized BLIS library instead of OpenBLAS (AMD CPUs only).

### Run with Intel MKL library
```bash
./build_run_hpl.sh --use_mkl
```
Uses Intel Math Kernel Library instead of OpenBLAS (Intel CPUs only).

### Run with specific memory size
```bash
./build_run_hpl.sh --mem_size 128
```
Tests with 128 GiB of memory instead of using all available RAM.

### Run multiple iterations
```bash
./build_run_hpl.sh --iterations 3
```
Runs the benchmark 3 times to check consistency.

### Run with sleep between iterations
```bash
./build_run_hpl.sh --iterations 5 --sleep_between_runs 60
```
Runs 5 iterations with 60 seconds between each run.

### Run regression test
```bash
./build_run_hpl.sh --regression
```
Runs with reduced memory (N/4) for faster regression testing.

### Run with PCP monitoring
```bash
./build_run_hpl.sh --use_pcp
```
Collects Performance Co-Pilot data during the run.

### Combination example
```bash
./build_run_hpl.sh --use_blis --iterations 3 --mem_size 256 --use_pcp
```
Uses AMD BLIS, runs 3 iterations with 256 GiB memory, and collects PCP data.

## How Problem Sizing Works

The script automatically calculates optimal HPL parameters based on system hardware:

### Problem Size (N)
1. Detects total system memory (or uses `--mem_size` value)
2. Calculates N to use approximately 86% of memory:
   ```
   N = sqrt((memory_in_bytes) / 8) × 0.86
   ```
   The factor of 8 accounts for double-precision floating-point (8 bytes)
3. Rounds N down to nearest multiple of NB to avoid fragmentation
4. If `--regression` is used, divides N by 4 for faster testing

### Block Size (NB)
Selected based on CPU family/model for optimal cache utilization:
- AMD Naples (Family 23, Model 1): 232
- AMD Rome (Family 23, Model 49): 224
- AMD Milan (Family 25, Model 1): 224
- AMD Genoa (Family 25, Model 17): 224
- AMD Bergamo (Family 25, Model 160): 384
- Intel (Family 6): 256
- ARM/other: 256 (default)

### MPI Process Grid (P × Q)
1. Determines number of MPI processes based on BLAS library:
   - **Multi-threaded BLAS** (BLIS-MT, OpenBLAS with OpenMP): Uses number of NUMA nodes or L3 caches
   - **Single-threaded BLAS**: Uses total number of cores
2. Calculates P and Q to be as close as possible (square grid)
3. Ensures P ≤ Q (HPL requirement)
4. Algorithm: Start with sqrt(num_processes), then iterate down to find factors

### OpenMP Threads
- For multi-threaded BLAS: Sets OMP_NUM_THREADS to cores per L3 cache
- For single-threaded BLAS: OMP_NUM_THREADS=1

## How MPI Configuration Works

The wrapper uses a centralized MPI setup library (`mpi_setup_lib.sh`) that handles MPI environment configuration across different operating systems:

### RHEL/CentOS
- **RHEL 8/9**: Uses environment modules (`module load mpi/openmpi-<arch>`)
- **RHEL 10+**: Direct PATH setup (`/usr/lib64/openmpi/bin`)

### Ubuntu
- MPI binaries in `/usr/bin` (automatically in PATH)
- Architecture-specific include paths: `/usr/lib/<arch>-linux-gnu/openmpi/include`

### SLES
- MPI installed in `/usr/lib64/mpi/gcc/openmpi*`
- Requires explicit PATH and LD_LIBRARY_PATH setup

### Process Binding
The wrapper optimizes MPI process binding based on cache topology:
- **Systems with L3 cache**: `--map-by l3cache`
- **Systems without L3 cache info**: `--map-by numa`
- **Single-threaded BLAS**: `--bind-to core`

## Integration with test_tools

The wrapper integrates with the test_tools-wrappers framework:

- **csv_to_json**: Converts results to JSON format
- **detect_numa**: Detects NUMA node configuration
- **detect_os**: Identifies operating system and version
- **gather_data**: Collects system information
- **general_setup**: Parses common options, handles tuned profile detection
- **move_data**: Organizes output files
- **package_tool**: Installs required packages based on JSON configuration
- **pcp/pcp_commands.inc**: Performance Co-Pilot integration
- **save_results**: Archives results to configured storage
- **test_header_info**: Generates CSV headers with system metadata
- **verify_results**: Validates against Pydantic schema

## Return Codes

The script uses standardized error codes from test_tools error_codes:
- **0**: Success
- **101**: Git clone failure
- **E_GENERAL**: General execution errors (build failures, library installation failures, test execution failures, validation failures)
- **E_NO_ARGS**: Missing required arguments
- **E_USAGE**: Invalid usage/arguments

Exit codes indicate specific failure points for automated testing workflows.

## Notes

### Architecture Support
- **x86_64**: Full support for AMD and Intel CPUs with BLIS, MKL, or OpenBLAS
- **aarch64**: Full support for ARM CPUs with OpenBLAS-OpenMP
- **Other architectures**: Not currently supported

### BLAS Library Performance
- AMD CPUs typically achieve best performance with AMD BLIS
- Intel CPUs typically achieve best performance with Intel MKL
- OpenBLAS is a good general-purpose option and works across all architectures
- Multi-threaded BLAS libraries generally outperform single-threaded versions

### Memory Considerations
- HPL requires memory proportional to N². A problem size of N=100,000 requires ~75 GiB
- The wrapper uses 86% of memory by default, leaving headroom for OS and other processes
- For systems with very large memory, consider using `--mem_size` to limit problem size
- Memory bandwidth is often the limiting factor for HPL performance

### Special Cases
- **Amazon Linux 2**: OpenBLAS is compiled from source for better compatibility
- **RHEL 9/10**: Uses FlexiBLAS wrapper with OpenBLAS backend (libopenblaso.so.0)
- **Ampere eMag**: Uses MPI-only configuration (OMP_NUM_THREADS=1) for better performance
- **Rosetta 2 on macOS ARM**: Currently not a target platform

### Performance Tips
- Run multiple iterations to verify consistency
- Ensure system is idle (no other workloads) for best results
- Disable CPU frequency scaling (use performance governor) for reproducible results
- Consider the active tuned profile on RHEL systems
- For production benchmarking, allow system to warm up with a test run first

### Troubleshooting
- If HPL fails to build, check that all dependencies are installed
- If mpirun is not found, verify MPI packages are installed for your OS
- If performance is unexpectedly low, check CPU frequency and system load
- Use `--use_pcp` to collect detailed performance counters for analysis
- Check generated HPL.dat file to verify problem sizing is appropriate
