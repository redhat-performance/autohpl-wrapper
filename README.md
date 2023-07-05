Automation wrapper for HPL

Description: HPL is a software package that solves a (random) dense linear system
             in double precision (64 bits) arithmetic on distributed-memory computers.
             It can thus be regarded as a portable as well as freely available
             implementation of the High Performance Computing Linpack Benchmark.
             For more information see: https://netlib.org/benchmark/hpl/
  
Location of underlying workload: https://www.netlib.org/benchmark/hpl/

Packages required: gcc make gcc-gfortran openblas-openmp openmpi openmpi-devel wget bc perf

To run:
[root@hawkeye ~]# git clone https://github.com/redhat-performance/autohpl-wrapper
[root@hawkeye ~]# autohpl-wrapper/auto_hpl/build_run_hpl.sh

The script will set the sizings based on the hardware it is being run.

```
Options
  --mem_size <value>: desiginate the size of memory to work with (in gig).
  --sleep_between_runs <value>: sleep this number of seconds before stating to the next run.
  --use_mkl: use the mkl lib.
  --use_blis: use the blis lib.
  --regression: limit the amount of memory for regression.
General options
  --home_parent <value>: Our parent home directory.  If not set, defaults to current working directory.
  --host_config <value>: default is the current host name.
  --iterations <value>: Number of times to run the test, defaults to 1.
  --pbench: use pbench-user-benchmark and place information into pbench, defaults to do not use.
  --pbench_user <value>: user who started everything. Defaults to the current user.
  --pbench_copy: Copy the pbench data, not move it.
  --pbench_stats: What stats to gather. Defaults to all stats.
  --run_label: the label to associate with the pbench run. No default setting.
  --run_user: user that is actually running the test on the test system. Defaults to user running wrapper.
  --sys_type: Type of system working with, aws, azure, hostname.  Defaults to hostname.
  --sysname: name of the system running, used in determing config files.  Defaults to hostname.
  --tuned_setting: used in naming the tar file, default for RHEL is the current active tuned.  For non
    RHEL systems, default is none.
  --usage: this usage message.
```

Note: The script does not install pbench for you.  You need to do that manually.
