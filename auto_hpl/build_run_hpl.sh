#!/bin/bash
#
#                         License
#
# Copyright (C) 2021  Pete Rival frival@redhat.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#

# Script to build and run HPL
# Uses AMD BLIS or OpenBLAS library for AMD depending on args
# Uses Intel MKL or OpenBLAS library for Intel depending on args
# Uses OpenBLAS for ARM
export LANG=C
arguments="$@"

HPL_LINK=http://www.netlib.org/benchmark/hpl/hpl-2.3.tar.gz
HPL_VER=2.3
NUM_ITER=1
typeset mem_size=0

chars=`echo $0 | awk -v RS='/' 'END{print NR-1}'`
run_dir=`echo $0 | cut -d'/' -f 1-${chars}`
AMD_BLIS_DIR=$run_dir/amd/blis
HPL_PATH=$run_dir/hpl
SCRIPT_DIR=$run_dir
tools_git=https://github.com/dvalinrh/test_tools

usage()
{
  echo Usage $1:
  echo "  --mem_size <value>:"
  echo "  --use_mkl"
  echo "  --use_blis"
  echo "  --regression"
  source test_tools/general_setup --usage
  exit
}

found=0
for arg in "$@"; do
  if [ $found -eq 1 ]; then
    tools_git=$arg
    break;
  fi
  if [[ $arg == "--tools_git" ]]; then
	found=1
  fi

  #
  # We do the usage check here, as we do not want to be calling
  # the common parsers then checking for usage here.  Doing so will
  # result in the script exiting with out giving the test options.
  #
  if [[ $arg == "--usage" ]]; then
    usage $0
  fi
done

#
# Check to see if the test tools directory exists.  If it does, we do not need to
# clone the repo.
#
if [ ! -d "test_tools" ]; then
  git clone $tools_git
  if [ $? -ne 0 ]; then
    echo pulling git $tools_git failed.
    exit
  fi
fi

# Variables set by general setup.
#
# TOOLS_BIN: points to the tool directory
# to_home_root: home directory
# to_configuration: configuration information
# to_times_to_run: number of times to run the test
# to_pbench: Run the test via pbench
# to_puser: User running pbench
# to_run_label: Label for the run
# to_user: User on the test system running the test
# to_sys_type: for results info, basically aws, azure or local
# to_sysname: name of the system
# to_tuned_setting: tuned setting
#

#
# wrapper specific code.
#

size_platform()
{
  LSCPU="$(mktemp /tmp/lscpu.XXXXXX)"
  /usr/bin/lscpu > $LSCPU
  arch=$(grep "Architecture:" $LSCPU | cut -d: -f 2|sed s/\ //g)
  vendor=$(grep "Vendor ID:" $LSCPU | cut -d: -f 2|tr -cd '[:alnum:]' | sed -e s/^[[:space:]]*//g -e s/[[:space:]]*$//g)
  if [[ "$arch" == "x86_64" ]]; then
    BLAS_MT=1 #Set 1 to use Multi-thread BLAS, 0 for single thread

    if [ $ubuntu -eq 0 ]; then
      MPI_PATH=/usr/lib64/openmpi
    elif [ $aws -eq 1 ]; then
        MPI_PATH=/usr/lib64/openmpi/bin/
    else
      MPI_PATH=/usr/
    fi
    family=$(grep "CPU family" $LSCPU | cut -d: -f 2)
    #
    # Strip off the weird marketing names
    # Due to AWS being stupid on the naming, we need to
    # search as part of a string.
    #
    if [[ "$vendor" == *"AuthenticAMD"* ]]; then
      vendor="AMD"
    elif [[ "$vendor" == *"GenuineIntel"* ]]; then
      vendor="Intel"
    else
      echo "Unrecognized CPU vendor ${vendor}, exiting"
      exit 1
    fi
    if [[ "$vendor" -ne "AMD" && "$use_blis" == 1 ]]; then
      echo "BLIS library support is only for AMD CPUs"
      exit 1
    fi
    if [[ "$vendor" -ne "Intel" && "use_mkl" == 1 ]]; then
      exit 1
    fi
  elif [[ "$arch" == "aarch64" ]]; then
    BLAS_MT=1
    if [ $ubuntu -eq 0 ]; then
      MPI_PATH=/usr/lib64/openmpi
    elif [ $aws -eq 1 ]; then
        MPI_PATH=/usr/lib64/openmpi/bin/
    else
      MPI_PATH=/usr/
    fi
  else
    echo "Architecture $arch is unsupported"
    exit 1
  fi
  model=$(grep "Model:" $LSCPU | cut -d: -f 2|sed -e s/^[[:space:]]*//g -e s/[[:space:]]*$//g)
  stepping=$(grep "Stepping:" $LSCPU | cut -d: -f 2)
  nodes=$(grep "NUMA node(s):" $LSCPU | cut -d: -f 2)
  nodes=`echo $nodes | sed 's/^[[:space:]]*//g'`
  echo nodes $nodes
  totcpus=$(grep "^CPU(s):" $LSCPU | cut -d: -f 2)
  thpcore=$(grep "^Thread(s)" $LSCPU | cut -d: -f 2)
  corespskt=$(grep "Core(s) per" $LSCPU | cut -d: -f 2|sed s/[[:space:]]//g)
  corespnode=$((totcpus / thpcore / nodes))
  # Intel and AMD systems have L3 cache entries, each with an ID which helps us
  # know how many L3 caches there are in the system (e.g. Rome as up to 4 L3
  # per socket, so it's not equal to the # of sockets).
  # Arm Neoverse-based systems don't have an L3, they have a SLC that's not in
  # PPTT.  ThunderX2 has a L3 but no id field.  Who needs consistency?
  if [[ -f /sys/devices/system/cpu/cpu0/cache/index3/id ]]; then
    numl3s=$(cat /sys/devices/system/cpu/cpu*/cache/index3/id | sort -n | uniq | wc -l)
  else
    numl3s=${nodes}
  fi
  echo numl3s $numl3s

  # Just assume all CPUs are the same because if not, shoot me
  if [ -d /sys/devices/system/cpu/cpu0/cache/index3 ]; then
    grep "," /sys/devices/system/cpu/cpu0/cache/index3/shared_cpu_list > /dev/null
    if [[ $? -eq 0 ]]; then
      # Comma-separated list
      threadspl3=$(cat /sys/devices/system/cpu/cpu0/cache/index3/shared_cpu_list |sed s/,/\ /g|wc -w)
      corespl3=$((threadspl3 / thpcore))
    else
      # Range
      end=$(cut -d- -f 2 /sys/devices/system/cpu/cpu0/cache/index3/shared_cpu_list)
      threadspl3=$((end + 1))
      corespl3=$((threadspl3 / thpcore))
    fi
  else
    # Ampere's eMag & Altra *have* an L3 cache but doesn't present it via ACPI
    # so there's no entry in sysfs. :sadface: Fortunately they don't have SMT
    # so we don't need to do a fancy dance like above.
    corespl3=$totcpus
    threadspl3=$totcpus
  fi
  if [ $nodes -ge $numl3s ]; then
    NUM_MPI_PROCESS_MT=$nodes # Default MPI rank for MT BLAS run. Hybrid of MPI+OMP
  else
    NUM_MPI_PROCESS_MT=$numl3s
  fi
  NUM_MPI_PROCESS_ST=$((corespnode * nodes)) #Default MPI rank for ST BLAS run
  NOMP=$corespnode # Default OMP_NUM_THREADS
  # Another special case: Ampere eMag performs significantly better as
  # MPI only without OMP - like over 3x better.
  if [[ "$vendor" == "APM" && $model -eq 2 ]]; then
    NUM_MPI_PROCESS_MT=$corespskt
    NUM_MPI_PROCESS_ST=$corespskt
    NOMP=1
  fi
  totmem=$(free -g|grep Mem|awk '{print $2}')
  echo $totmem
  if [[ $mem_size != 0 ]]; then
    NS=$mem_size
  else
    NS=$(echo "sqrt(($totmem * 1024 * 1024 * 1024) / 8) * 0.86 / 1" | bc)
  fi
  if [[ "$regression" == "1" ]]; then
    NS=$((NS / 4))
  fi
  if [[ "$arch" == "x86_64" ]]; then
    if [[ $family -eq 23 && $model -eq 1 ]]; then
      # AMD Naples
      NBS=232
    elif [[ $family -eq 23 && $model -eq  49 ]]; then
      # AMD Rome
      NBS=224
    elif [[ $family -eq 25 && $model -eq 1 ]]; then
      # AMD Milan
      NBS=224
    elif [[ $family -eq 6 ]]; then
      # Intel
      NBS=256
    fi
  elif [[ "$arch" == "aarch64" ]]; then
    # Honestly this is just a guess, sadly
    NBS=256
  else
    echo "Unsupported arch ${arch}, exiting"
    exit 1
  fi
  # Now we have to round N to a multiple of NBS to prevent a fragment at the end
  NS=$((NS / NBS))
  NS=$((NS * NBS))
  echo NS $NS

  # Okay now calculate P and Q.  I've tried doing this without successive
  # attempts but this was what worked first.  Someone please come up with
  # something better.
  # HPL requires P <= Q, and what we're looking for here is:
  # P * Q = NUM_MPI_PROCESS_MT.  A further recommendation is that P and Q
  # should be as close together as possible to create as square a matrix as we
  # can.  Start with sqrt which would be ideal and then work our way down from
  # there.  I'm convinced there's a better way to solve this, but until then...
  TGT=$NUM_MPI_PROCESS_MT
  calc_q=$(bc <<< "scale=0; sqrt(($TGT))")
  echo $TGT $calc_q
  calc_p=$((TGT / calc_q))
  calc_tgt=$((calc_p * calc_q))
  if [[ ! $calc_tgt == $TGT ]]; then
    calc_q=$((calc_q - 1))
    while :
    do
      calc_p=$((TGT / calc_q))
      calc_tgt=$((calc_q * calc_p))
      if [[ $calc_tgt == $TGT ]]; then
        break 1
      fi
      calc_q=$((calc_q - 1))
    done
  fi
  NP=$calc_p
  NQ=$calc_q
  # Finally, make sure P <= Q as that's a HPL requirement
  if [[ $NP -gt $NQ ]]; then
   TMPQ=$NQ
   NQ=$NP
   NP=$TMPQ
  fi
  sed s/NBNB/$NBS/ < $run_dir/HPL.dat.template | sed s/PPPP/$NP/ |\
  sed s/QQQQ/$NQ/ | sed s/NNNN/$NS/ > $SCRIPT_DIR/HPL.dat
  echo arch $arch
  echo vendor "|$vendor|"
  echo model "|$model|"
  echo stepping $stepping
  echo nodes $nodes
  echo totcpus $totcpus
  echo thpcore $thpcore
  echo corespskt $corespskt
  echo corespnode $corespnode
  echo threadspl3 $threadspl3
  echo corespl3 $corespl3
  echo NUM_MPI_PROCESS_MT $NUM_MPI_PROCESS_MT
  echo NUM_MPI_PROCESS_ST $NUM_MPI_PROCESS_ST
  echo NOMP $NOMP
  echo totmem $totmem
  echo NBS $NBS
  echo NP $NP
  echo NQ $NQ
}

install_mkl()
{
  # MKL is a binary install, make sure the repo file is in place and install
  # like any other library

  # Check if it's installed already so we don't waste time
  if [ $ubuntu -eq 0 ]; then
    yum list installed intel-mkl 2>&1 > /dev/null
    if [[ "$?" == "0" ]]; then
      return
    fi
    yum repolist | grep "Math Kernel Library" > /dev/null
    if [[ "$?" != "0" ]]; then
      cat > /etc/yum.repos.d/intel-mkl.repo << EOF
[intel-mkl-repo]
name=Intel(R) Math Kernel Library
baseurl=https://yum.repos.intel.com/mkl
enabled=1
gpgcheck=0
repo_gpgcheck=0
#gpgkey=https://yum.repos.intel.com/mkl/setup/PUBLIC_KEY.PUB
EOF
    fi
    yum -y install intel-mkl
  fi
  if [ $ubuntu -eq 1 ]; then
    apt list installed intel-mkl 2>&1 > /dev/null
    if [[ "$?" == "0" ]]; then
      return
    fi
    mkdir -p /root/intel-mkl
    pushd  /root/intel-mkl

    # keys taken from https://software.intel.com/en-us/articles/installing-intel-free-libs-and-python-apt-repo
    wget https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS-2019.PUB
    apt-key add GPG-PUB-KEY-INTEL-SW-PRODUCTS-2019.PUB

    sh -c 'echo deb https://apt.repos.intel.com/mkl all main > /etc/apt/sources.list.d/intel-mkl.list'
    apt-get update
    apt-get --yes install  intel-mkl
    popd
  fi
}

check_mpi()
{
  if [ $ubuntu -eq 0 ]; then
    yum list installed openmpi 2>&1 > /dev/null
    if [[ "$?" != "0" ]]; then
      yum -y install openmpi openmpi-devel
    fi
    which mpirun 2>&1 > /dev/null
    # MPI module isn't loaded, go ahead and load it
    if [[ $? != 0 ]]; then
      source /etc/profile.d/modules.sh
      module load mpi/openmpi-${arch}
      if [ $? != 0 ]; then
        echo "module load mpi/openmpi-${arch} failed, exiting"
        exit 1
      fi
      which mpirun 2>&1 > /dev/null
    fi
  fi
  if [ $ubuntu -eq 1 ]; then
    apt-get --yes install openmpi-bin openmpi-common
    #
    # Above loaded openmpi*
    which mpirun 2>&1 > /dev/null
    if [[ $? != 0 ]]; then
      echo could not find mpirun
      exit
    fi
  fi
}

build_blis()
{
  echo "BUILD AMD BLIS"
  cd $SCRIPT_DIR

  eval "mkdir -p blis"
  if [[ $? -ne 0 ]]; then
   log "\nUnable to create Directory blis. Try with sudo \n"
   exit
  fi
  cd blis

  blisdir=$AMD_BLIS_DIR
  # create directories
  eval "mkdir -p $blisdir"
  if [[ $? -ne 0 ]]; then
   log "\nUnable to create Directory $blisdir. Try with sudo \n"
   exit
  fi

  echo "Cloning AMD BLIS from https://github.com/amd/blis.git"
  git clone https://github.com/amd/blis.git

  cd blis
  enableblismt=
  if [[ $BLAS_MT -eq 1 ]]; then
   echo "Build Multi-threaded BLIS"
   enableblismt="--enable-threading=openmp"
  else
   echo "Build Single-threaded BLIS" 
  fi
  echo ./configure --enable-shared --enable-cblas $enableblismt --prefix=$blisdir zen
  ./configure --enable-shared --enable-cblas $enableblismt --prefix=$blisdir zen 2>&1 > ${RESULTSDIR}/blis_config.out
  make -j 50 2>&1 > ${RESULTSDIR}/blis_make.out
  make install 2>&1 > ${RESULTSDIR}/blis_make_install.out
}

build_hpl()
{
  echo "Get xHPL code. Change the HPL_LINK and HPL_VER variables suitably for required version"
  cd $SCRIPT_DIR
  
  # create directories
  eval "mkdir -p $HPL_PATH"
  if [[ $? -ne 0 ]]; then
   log "\nUnable to create Directory $HPL_PATH. Try with sudo \n"
   exit
  fi
  cd $HPL_PATH
  wget $HPL_LINK
  tar -xf hpl-$HPL_VER.tar.gz
  cd hpl-$HPL_VER

  makefile=Make.Linux_${blaslib}
  if [ $ubuntu -eq 1 ]; then
    makefile=Make.Linux_${blaslib}_ubuntu
  fi
  if [ $aws -eq 1 ]; then
    makefile=Make.Linux_${blaslib}_aws
  fi
  echo "sed s,TOPDIR,$run_dir, ${run_dir}/${makefile} > Make.Linux_${blaslib}"
  sed s,TOPDIR,$run_dir, ${run_dir}/${makefile} > Make.Linux_${blaslib}
  bindir=Linux_${blaslib}
  make arch=Linux_${blaslib} 2>&1 > ${RESULTSDIR}/hpl_make.out
}

clean_env()
{
  rm -rf $SCRIPT_DIR/blis
  rm -rf $HPL_PATH
  rm -rf $AMD_BLIS_DIR
}

run_hpl()
{
  cd $HPL_PATH/hpl-$HPL_VER/bin/${bindir}

  #ckup the existing HPL.dat file
  mv HPL.dat HPL.dat.bkup
  # Copy the HPL.dat file
  cp $SCRIPT_DIR/HPL.dat .
  
  num_mpi=$NUM_MPI_PROCESS_ST
  outfile=${RESULTSDIR}/hpl-${blaslib}-$(date "+%Y.%m.%d-%H.%M.%S").log
  if [[ $BLAS_MT -eq 1 ]]; then
    if [[ -d /sys/devices/system/cpu/cpu0/cache/index3 ]]; then
      bind_settings="--map-by l3cache"
    else
      bind_settings="--map-by socket"
    fi
    bind_settings="${bind_settings} -x OMP_NUM_THREADS=${NOMP}"
   num_mpi=$NUM_MPI_PROCESS_MT
  else
   bind_settings="--bind-to core"
  fi
  echo "bind_settings=$bind_settings"

  echo  "$MPI_PATH/bin/mpirun --allow-run-as-root -np $num_mpi --mca btl self,vader --report-bindings $bind_settings ./xhpl"

  echo "     T/V           N    NB     P     Q               Time                 Gflops"  > $outfile
  for i in $(seq "$NUM_ITER")
  do
    $MPI_PATH/bin/mpirun --allow-run-as-root -np $num_mpi --mca btl self,vader --report-bindings $bind_settings ./xhpl 2>&1 > hpl.out
    cat hpl.out | grep -E "WC|WR"  >> $outfile
  done
  cp $outfile $SCRIPT_DIR
  cd $SCRIPT_DIR
}

install_run_hpl()
{
  size_platform
  check_mpi
  clean_env
  if [[ "$arch" == "x86_64" ]]; then
    # Build AMD's special BLIS package
    if [[ "$use_blis" == "1" ]]; then
      echo "Using AMD BLIS"
      blaslib="AMD_BLIS"
      build_blis
    elif [[ "$use_mkl" == "1" ]]; then
      echo "Using Intel MKL"
      blaslib="Intel_MKL"
      install_mkl
    else
      echo "Using system OpenBLAS"
      blaslib="${vendor}_openblas"
    fi
  elif [[ "$arch" == "aarch64" ]]; then
    # Use OpenBLAS-openmp
    echo "Using system OpenBLAS-OpenMP"
    blaslib="aarch64_openblas"
  fi
  build_hpl 
  run_hpl
}

use_mkl=0
use_blis=0
regression=0

source test_tools/general_setup "$@"

ARGUMENT_LIST=(
	"mem_size"
)

NO_ARGUMENTS=(
	"usage"
	"use_mkl"
	"use_blis"
	"regression"
)

# read arguments
opts=$(getopt \
  --longoptions "$(printf "%s:," "${ARGUMENT_LIST[@]}")" \
  --longoptions "$(printf "%s," "${NO_ARGUMENTS[@]}")" \
  --name "$(basename "$0")" \
  --options "h" \
  -- "$@"
)

if [ $? -ne 0 ]; then
	echo need to provide arguments.
	exit
fi

eval set --$opts

while [[ $# -gt 0 ]]; do
  case "$1" in
    --use_mkl)
      use_mkl=1
      echo "set use_mkl to $use_mkl"
      shift 1
    ;;
    --use_blis)
      use_blis=1
      shift 1
    ;;
    --regression)
      regression=1
      shift 1
    ;;
    --mem_size)
      mem_size=${2}
      shift 2
    ;;
    --usage)
      usage $0
    ;;
    --)
      break
    ;;
    *)
      echo "option $1 not found"
      exit
    ;;
  esac
done

info=`uname -a | cut -d' ' -f3 | cut -d'.' -f5`
aws=0
if [ ${info} == "amzn2" ]; then
  aws=1
  mkdir src
  pushd src
  git clone https://github.com/xianyi/OpenBLAS
  cd OpenBLAS
  make FC=gfortran
  make PREFIX=/usr/lib64 install
  cp /usr/lib64/lib/libopenblas.so /usr/lib64/libopenblas.so
  cp /usr/lib64/lib/libopenblas.so /usr/lib64/libopenblas.so.0
fi
info=`uname -a | cut -d' ' -f 4 | cut -d'-' -f2`
ubuntu=0
if [ ${info} == "Ubuntu" ]; then
  ubuntu=1
fi

# --regression and --mem_size are mutually exclusive, bail if both are set
if [ ${mem_size} -ne 0 ] && [ ${regression} -ne 0 ]; then
  echo "You can't use both --regression and --mem_size, exiting."
  exit 1
fi

RESULTSDIR=/tmp/results_auto_hpl_${to_tuned_setting}_$(date "+%Y.%m.%d-%H.%M.%S")
rm /tmp/results_auto_hpl_${to_tuned_setting} 2> /dev/null
mkdir ${RESULTSDIR}
ln -s ${RESULTSDIR} /tmp/results_auto_hpl_${to_tuned_setting}

if [ $to_pbench -eq 1 ];then
  source ~/.bashrc

  $TOOLS_BIN/execute_pbench --cmd_executing "$0" $arguments --test auto_hpl --spacing 11
  cd /tmp
  cp results_auto_hpl_${to_tuned_setting}.tar results_pbench_auto_hpl_${to_tuned_setting}.tar
else
  install_run_hpl

  cd /tmp/results_auto_hpl_${to_tuned_setting}
  pwd
  for results in `ls -d *log`; do
	echo results $results
	  out_file=`echo $results | sed "s/\.log/\.csv/g"`
	  cat $results | tr -s ' ' | sed "s/^ //g" | sed "s/ /:/g" > $out_file
  done
  cd /tmp
  tar hcf results_auto_hpl_${to_tuned_setting}.tar results_auto_hpl_${to_tuned_setting}
fi
exit 0
