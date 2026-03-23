# CMake toolchain file for Cosmopolitan Libc (cosmocc)
# Produces Actually Portable Executables (APE) that run on
# Linux, macOS, Windows, FreeBSD, and OpenBSD from a single binary.
#
# Usage: cmake -DCMAKE_TOOLCHAIN_FILE=cosmocc-toolchain.cmake ..

set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# Find cosmocc in standard location
set(COSMOCC_ROOT "$ENV{HOME}/.cosmocc" CACHE PATH "Cosmopolitan toolchain root")
set(CMAKE_C_COMPILER "${COSMOCC_ROOT}/bin/cosmocc")
set(CMAKE_CXX_COMPILER "${COSMOCC_ROOT}/bin/cosmoc++")
set(CMAKE_AR "${COSMOCC_ROOT}/bin/cosmoar" CACHE FILEPATH "")
set(CMAKE_RANLIB "${COSMOCC_ROOT}/bin/cosmoranlib" CACHE FILEPATH "")

# Cosmocc handles cross-compilation internally — disable cmake's platform probes
set(CMAKE_C_COMPILER_WORKS TRUE)
set(CMAKE_CXX_COMPILER_WORKS TRUE)
set(CMAKE_C_ABI_COMPILED TRUE)
set(CMAKE_CXX_ABI_COMPILED TRUE)

# No shared libraries in Cosmopolitan
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(CMAKE_FIND_LIBRARY_SUFFIXES ".a")

# Threading: cosmocc provides pthreads
set(CMAKE_THREAD_LIBS_INIT "-lpthread")
set(CMAKE_HAVE_THREADS_LIBRARY 1)
set(CMAKE_USE_PTHREADS_INIT 1)
set(THREADS_PREFER_PTHREAD_FLAG ON)
