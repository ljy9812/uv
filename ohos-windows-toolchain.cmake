# CMake toolchain file for OHOS cross-compilation from Windows
# Used by aws-lc-rs and other cmake-based dependencies

# Use OHOS_SDK env var set by CI workflow
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

# Convert Windows path to forward slashes for cmake/clang compatibility
file(TO_CMAKE_PATH "$ENV{OHOS_SDK}" OHOS_SDK_CMAKE)

set(OHOS_NATIVE_BIN "${OHOS_SDK_CMAKE}/llvm/bin")
set(OHOS_SYSROOT "${OHOS_SDK_CMAKE}/sysroot")

set(CMAKE_C_COMPILER "${OHOS_NATIVE_BIN}/clang.exe")
set(CMAKE_CXX_COMPILER "${OHOS_NATIVE_BIN}/clang++.exe")
set(CMAKE_AR "${OHOS_NATIVE_BIN}/llvm-ar.exe" CACHE FILEPATH "ar" FORCE)
set(CMAKE_RANLIB "${OHOS_NATIVE_BIN}/llvm-ranlib.exe" CACHE FILEPATH "ranlib" FORCE)

set(CMAKE_C_COMPILER_TARGET "aarch64-linux-ohos")
set(CMAKE_CXX_COMPILER_TARGET "aarch64-linux-ohos")

set(CMAKE_SYSROOT "${OHOS_SYSROOT}")

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -D__MUSL__" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -D__MUSL__" CACHE STRING "" FORCE)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
