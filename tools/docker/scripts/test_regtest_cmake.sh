#!/bin/bash

# author: Ole Schuett

ulimit -c 0 # Disable core dumps as they can take a very long time to write.

# Check available shared memory - needed for MPI inter-process communication.
SHM_AVAIL=$(df --output=avail -m /dev/shm | tail -1)
if ((SHM_AVAIL < 1024)); then
  echo "ERROR: Not enough shared memory. If you're running docker use --shm-size=1g."
  exit 1
fi

# Activate Spack environment.
eval "$(spack env activate myenv --sh)"

# Using Ninja because of https://gitlab.kitware.com/cmake/cmake/issues/18188

# Run CMake.
mkdir build
cd build || exit 1
if ! cmake \
  -GNinja \
  -DCMAKE_C_FLAGS="-fno-lto" \
  -DCMAKE_Fortran_FLAGS="-fno-lto" \
  -DCMAKE_INSTALL_PREFIX=/opt/cp2k \
  -Werror=dev \
  -DCP2K_USE_VORI=OFF \
  -DCP2K_USE_COSMA=OFF \
  -DCP2K_USE_DLAF=ON \
  -DCP2K_BLAS_VENDOR=OpenBLAS \
  -DCP2K_USE_SPGLIB=ON \
  -DCP2K_USE_LIBINT2=OFF \
  -DCP2K_USE_LIBXC=ON \
  -DCP2K_USE_LIBTORCH=OFF \
  -DCP2K_USE_MPI=ON \
  -DCP2K_USE_MPI_F08=ON \
  -DCP2K_ENABLE_REGTESTS=ON \
  .. |& tee ./cmake.log; then
  echo -e "\nSummary: CMake failed."
  echo -e "Status: FAILED\n"
  exit 0
fi

# Check for CMake warnings.
if grep -A5 'CMake Warning' ./cmake.log; then
  echo -e "\nSummary: Found CMake warnings."
  echo -e "Status: FAILED\n"
  exit 0
fi

# Compile CP2K.
echo -en '\nCompiling cp2k...'
if ninja --verbose &> ninja.log; then
  echo "done."
else
  echo -e "failed.\n\n"
  tail -n 100 ninja.log
  mkdir -p /workspace/artifacts/
  cp ninja.log /workspace/artifacts/
  echo -e "\nSummary: Compilation failed."
  echo -e "Status: FAILED\n"
  exit 0
fi

# Fake installation of data files.
cd ..
mkdir -p ./share/cp2k
ln -s ../../data ./share/cp2k/data

# Increase stack size.
ulimit -s unlimited
export OMP_STACKSIZE=64m

# Improve code coverage on COSMA.
export COSMA_DIM_THRESHOLD=0

# Bind pika threads to first two cores. This is a hack. Do not use for production!
export PIKA_PROCESS_MASK="0x3"

# Run regtests.
echo -e "\n========== Running Regtests =========="
set -x
# shellcheck disable=SC2086
./tests/do_regtest.py local psmp ${TESTOPTS}

exit 0 # Prevent CI from overwriting do_regtest's summary message.

#EOF
