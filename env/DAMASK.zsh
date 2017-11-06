# sets up an environment for DAMASK on zsh
# usage:  source DAMASK.zsh

function canonicalPath {
  python -c "import os,sys; print(os.path.realpath(os.path.expanduser(sys.argv[1])))" $1
}

# transition compatibility (renamed $DAMASK_ROOT/DAMASK_env.zsh to $DAMASK_ROOT/env/DAMASK.zsh)
if [ ${0:t:r} = 'DAMASK' ]; then
  DAMASK_ROOT=${0:a:h}'/..'
else
  DAMASK_ROOT=${0:a:h}
fi

# shorthand command to change to DAMASK_ROOT directory
eval "function DAMASK_root() { cd $DAMASK_ROOT; }"

# defining set() allows to source the same file for tcsh and zsh, with and without space around =
set() {
    export $1$2$3
 }
source $DAMASK_ROOT/CONFIG
unset -f set

# add DAMASK_BIN if present
[ "x$DAMASK_BIN != x" ] && PATH=$DAMASK_BIN:$PATH

SOLVER=$(type -p DAMASK_spectral || true 2>/dev/null)
[ "x$SOLVER == x" ] && SOLVER='Not found!'

PROCESSING=$(type -p postResults || true 2>/dev/null)
[ "x$PROCESSING == x" ] && PROCESSING='Not found!'

[ "x$DAMASK_NUM_THREADS == x" ] && DAMASK_NUM_THREADS=1

# currently, there is no information that unlimited causes problems
# still,  http://software.intel.com/en-us/forums/topic/501500 suggest to fix it
# http://superuser.com/questions/220059/what-parameters-has-ulimit
ulimit -d unlimited 2>/dev/null # maximum  heap size (kB)
ulimit -s unlimited 2>/dev/null # maximum stack size (kB)
ulimit -v unlimited 2>/dev/null # maximum virtual memory size
ulimit -m unlimited 2>/dev/null # maximum physical memory size

# disable output in case of scp
if [ ! -z "$PS1" ]; then
  echo
  echo Düsseldorf Advanced Materials Simulation Kit --- DAMASK
  echo Max-Planck-Institut für Eisenforschung GmbH, Düsseldorf
  echo https://damask.mpie.de
  echo
  echo "Using environment with ..."
  echo "DAMASK             $DAMASK_ROOT"
  echo "Spectral Solver    $SOLVER" 
  echo "Post Processing    $PROCESSING"
  echo "Multithreading     DAMASK_NUM_THREADS=$DAMASK_NUM_THREADS"
  if [ "x$PETSC_DIR"   != "x" ]; then
    echo "PETSc location     $PETSC_DIR"
    [[ $(canonicalPath "$PETSC_DIR") == $PETSC_DIR ]] \
    || echo "               ~~> "$(canonicalPath "$PETSC_DIR")
  fi
  [[ "x$PETSC_ARCH"  == "x" ]] \
  || echo "PETSc architecture $PETSC_ARCH"
  echo "MSC.Marc/Mentat    $MSC_ROOT"
  echo
  echo -n "heap  size         "
   [[ "$(ulimit -d)" == "unlimited" ]] \
   && echo "unlimited" \
   || echo $(python -c \
          "import math; \
           size=$(( 1024*$(ulimit -d) )); \
           print('{:.4g} {}'.format(size / (1 << ((int(math.log(size,2) / 10) if size else 0) * 10)), \
           ['bytes','KiB','MiB','GiB','TiB','EiB','ZiB'][int(math.log(size,2) / 10) if size else 0]))")
  echo -n "stack size         "
   [[ "$(ulimit -s)" == "unlimited" ]] \
   && echo "unlimited" \
   || echo $(python -c \
          "import math; \
           size=$(( 1024*$(ulimit -s) )); \
           print('{:.4g} {}'.format(size / (1 << ((int(math.log(size,2) / 10) if size else 0) * 10)), \
           ['bytes','KiB','MiB','GiB','TiB','EiB','ZiB'][int(math.log(size,2) / 10) if size else 0]))")
fi

export DAMASK_NUM_THREADS
export PYTHONPATH=$DAMASK_ROOT/lib:$PYTHONPATH

for var in BASE STAT SOLVER PROCESSING FREE DAMASK_BIN; do
  unset "${var}"
done
for var in DAMASK MSC; do
  unset "${var}_ROOT"
done
for var in ABAQUS MARC; do
  unset "${var}_VERSION"
done