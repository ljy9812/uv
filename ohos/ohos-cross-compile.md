# Skill: Cross-compile uv for OHOS (OpenHarmony) aarch64

## Description
Cross-compile the `uv` project for OHOS (OpenHarmony) aarch64 target on Windows.

## When to Use
When the user wants to build `uv` for OHOS / OpenHarmony / HarmonyOS devices.

## Prerequisites
1. **DevEco Studio** installed (contains OHOS SDK + LLVM toolchain + CMake + Ninja)
2. **Rust stable** toolchain installed via `rustup`
3. **Network access** to crates.io (via proxy if configured)

## Step-by-step Procedure

### Step 1: Locate OHOS SDK

Find the OHOS native SDK directory inside DevEco Studio. Common paths:
- `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native`

Verify it contains: `llvm/bin/clang.exe`, `build-tools/cmake/bin/cmake.exe`, `build-tools/cmake/bin/ninja.exe`, `sysroot/`

### Step 2: Create Junction to Avoid Spaces in Path

OHOS SDK path contains spaces ("Program Files"), which breaks many build tools (configure scripts, cc-rs, etc.). Create a junction without spaces:

```powershell
powershell -Command "New-Item -ItemType Junction -Path 'C:\ohos\sdk' -Target 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native' -Force"
```

Verify: `ls /c/ohos/sdk/llvm/bin/clang.exe` should show the file.

### Step 3: Ensure Rust Target is Installed

```bash
rustup target add aarch64-unknown-linux-ohos --toolchain stable
```

**Note (China):** If downloading the Rust toolchain is slow, use the TUNA mirror:
```bash
export RUSTUP_DIST_SERVER="https://mirrors.tuna.tsinghua.edu.cn/rustup"
rustup toolchain install stable --force
rustup target add aarch64-unknown-linux-ohos --toolchain stable
```

Verify: `rustup target list --toolchain stable --installed` should include `aarch64-unknown-linux-ohos`.

### Step 4: Modify rust-toolchain.toml

If the project's `rust-toolchain.toml` pins a specific version (e.g. `1.95.0`) that has manifest issues, change it to `stable`:

```toml
[toolchain]
channel = "stable"
```

**Note:** Restore this file after building if you don't want to commit this change.

### Step 5: Create/Update .cargo/config.toml

Add the OHOS cross-compilation section. Use the **junction path** (`C:/ohos/sdk`) to avoid spaces:

```toml
# Use Chinese mirror for crates.io (optional, speeds up downloads in China)
[source.crates-io]
replace-with = 'ustc'

[source.ustc]
registry = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"

# OHOS (OpenHarmony) cross-compilation
[target.aarch64-unknown-linux-ohos]
linker = "C:/ohos/sdk/llvm/bin/clang.exe"
ar = "C:/ohos/sdk/llvm/bin/llvm-ar.exe"
rustflags = ["-C", "link-arg=--target=aarch64-linux-ohos", "-C", "link-arg=--sysroot=C:/ohos/sdk/sysroot"]

[env]
OHOS_SYSROOT = "C:/ohos/sdk/sysroot"
CC_aarch64_unknown_linux_ohos = "C:/ohos/sdk/llvm/bin/clang.exe"
CFLAGS_aarch64_unknown_linux_ohos = "--target=aarch64-linux-ohos --sysroot=C:/ohos/sdk/sysroot -D__MUSL__"
CXX_aarch64_unknown_linux_ohos = "C:/ohos/sdk/llvm/bin/clang++.exe"
CXXFLAGS_aarch64_unknown_linux_ohos = "--target=aarch64-linux-ohos --sysroot=C:/ohos/sdk/sysroot -D__MUSL__"
AR_aarch64_unknown_linux_ohos = "C:/ohos/sdk/llvm/bin/llvm-ar.exe"
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER = "C:/ohos/sdk/llvm/bin/clang.exe"
CMAKE_aarch64_unknown_linux_ohos = { value = "cmake-wrapper.bat", relative = true }
CMAKE_GENERATOR_aarch64_unknown_linux_ohos = "Ninja"
CMAKE_MAKE_PROGRAM_aarch64_unknown_linux_ohos = "C:/ohos/sdk/build-tools/cmake/bin/ninja.exe"
CMAKE_TOOLCHAIN_FILE_aarch64_unknown_linux_ohos = { value = "ohos-toolchain.cmake", relative = true }
PATH = { value = "C:/ohos/sdk/build-tools/cmake/bin", prepend = true }
```

### Step 6: Create ohos-toolchain.cmake

Create `ohos-toolchain.cmake` in the project root:

```cmake
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(OHOS_SDK "C:/ohos/sdk")

set(CMAKE_C_COMPILER "${OHOS_SDK}/llvm/bin/clang.exe")
set(CMAKE_CXX_COMPILER "${OHOS_SDK}/llvm/bin/clang++.exe")
set(CMAKE_AR "${OHOS_SDK}/llvm/bin/llvm-ar.exe" CACHE FILEPATH "ar" FORCE)
set(CMAKE_RANLIB "${OHOS_SDK}/llvm/bin/llvm-ranlib.exe" CACHE FILEPATH "ranlib" FORCE)

set(CMAKE_C_COMPILER_TARGET "aarch64-linux-ohos")
set(CMAKE_CXX_COMPILER_TARGET "aarch64-linux-ohos")

set(CMAKE_SYSROOT "${OHOS_SDK}/sysroot")

set(CMAKE_MAKE_PROGRAM "${OHOS_SDK}/build-tools/cmake/bin/ninja.exe" CACHE FILEPATH "ninja" FORCE)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -D__MUSL__" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -D__MUSL__" CACHE STRING "" FORCE)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
```

### Step 7: Create cmake-wrapper.bat

Create `cmake-wrapper.bat` in the project root. This wrapper injects `CMAKE_MAKE_PROGRAM` during configure phase but passes through during build phase (to avoid `--parallel` argument conflicts):

```batch
@echo off
setlocal
if "%~1"=="--build" (
    "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native\build-tools\cmake\bin\cmake.exe" %*
) else (
    "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native\build-tools\cmake\bin\cmake.exe" -DCMAKE_MAKE_PROGRAM=C:/ohos/sdk/build-tools/cmake/bin/ninja.exe %*
)
```

### Step 8: Set CARGO_TARGET_DIR to Space-free Path

The project directory path may contain spaces, which breaks `tikv-jemalloc-sys`'s configure script. Set `CARGO_TARGET_DIR` to a path without spaces:

```bash
mkdir -p /c/uv-target
export CARGO_TARGET_DIR="C:/uv-target"
```

### Step 9: Build

```bash
cd <project-root>
export PATH="/c/ohos/sdk/build-tools/cmake/bin:$PATH"
export CARGO_TARGET_DIR="C:/uv-target"

# Debug build
cargo build --target aarch64-unknown-linux-ohos -p uv \
  --no-default-features --features "uv-distribution/static,test-defaults"

# Release build (recommended, ~48MB vs ~688MB debug)
cargo build --release --target aarch64-unknown-linux-ohos -p uv \
  --no-default-features --features "uv-distribution/static,test-defaults"
```

### Step 10: Strip the Binary (Release Only)

```bash
"C:/ohos/sdk/llvm/bin/llvm-strip.exe" "$CARGO_TARGET_DIR/aarch64-unknown-linux-ohos/release/uv"
```

## Output

Binary location: `C:\uv-target\aarch64-unknown-linux-ohos\release\uv` (or `debug\uv` for debug build)

```
Format: ELF 64-bit LSB pie executable
Arch:   ARM aarch64
Link:   dynamically linked musl libc (/lib/ld-musl-aarch64.so.1)
Size:   ~48MB (release, stripped)
```

## Deploy to OHOS Device

**Note:** If using Git Bash (MSYS2), set `MSYS_NO_PATHCONV=1` to prevent path mangling, or run `hdc` from the binary's directory:

```bash
cd /c/uv-target/aarch64-unknown-linux-ohos/release
MSYS_NO_PATHCONV=1 hdc file send uv /data/local/tmp/uv
MSYS_NO_PATHCONV=1 hdc shell chmod +x /data/local/tmp/uv
MSYS_NO_PATHCONV=1 hdc shell /data/local/tmp/uv --version
```

## Known Issues & Workarounds

| Issue | Cause | Workaround |
|-------|-------|------------|
| `Missing manifest in toolchain '1.95.0-...'` | Pinned toolchain version manifest corrupted/missing | Change `rust-toolchain.toml` to `channel = "stable"` |
| `failed to find tool "cc": program not found` | cc-rs can't find C compiler | Set `CC_aarch64_unknown_linux_ohos` env var |
| `%1 is not a valid Win32 application (os error 193)` | `aarch64-unknown-linux-ohos-clang` is a shell script | Use `clang.exe` directly with `--target` and `--sysroot` flags |
| `Missing dependency: cmake` | cmake not in PATH | Set `CMAKE_aarch64_unknown_linux_ohos` env var |
| `CMake was unable to find a build program for "Ninja"` | CMake can't find ninja.exe | Create `cmake-wrapper.bat` to inject `CMAKE_MAKE_PROGRAM` |
| `invalid numeric argument '/Wno-unused-...'` | CMake defaulted to MSVC generator instead of Ninja | Force `-G Ninja` via `CMAKE_GENERATOR` env var |
| `--sysroot=C:/Program` path split by spaces | Space in SDK path breaks cc-rs argument splitting | Create junction `C:\ohos\sdk` pointing to the real SDK path |
| `Prefix should not contain spaces` (jemalloc configure) | `tikv-jemalloc-sys` configure rejects spaces in prefix | Set `CARGO_TARGET_DIR` to a space-free path |
| `Invalid configuration x86_64-pc-win32` (jemalloc configure) | jemalloc configure doesn't recognize Windows build host | Disable jemalloc via `--no-default-features` (removes `performance` feature) |
| Network timeout connecting to crates.io | Local proxy (127.0.0.1:17891) not running | Start proxy software (Clash/V2Ray/etc.) or add `[source.crates-io]` with USTC mirror in `.cargo/config.toml` |
| Slow Rust toolchain download/install | `RUSTUP_DIST_SERVER` not set | Set `RUSTUP_DIST_SERVER=https://mirrors.tuna.tsinghua.edu.cn/rustup` |
| `hdc file send` fails with wrong path in Git Bash | MSYS2 converts Windows paths (e.g. `C:/` → `C:/Program Files/Git/`) | Set `MSYS_NO_PATHCONV=1` or run `hdc` from the binary's directory |

## Files Created/Modified

| File | Action | Purpose |
|------|--------|---------|
| `.cargo/config.toml` | Modified | OHOS linker, CC, CMake env vars |
| `ohos-toolchain.cmake` | Created | CMake cross-compilation toolchain |
| `cmake-wrapper.bat` | Created | Injects CMAKE_MAKE_PROGRAM for Ninja |
| `rust-toolchain.toml` | Modified | Changed from pinned version to `stable` |

## Environment Variables Summary

| Variable | Value | Purpose |
|----------|-------|---------|
| `OHOS_SYSROOT` | `C:/ohos/sdk/sysroot` | OHOS sysroot for C compilation |
| `CC_aarch64_unknown_linux_ohos` | `C:/ohos/sdk/llvm/bin/clang.exe` | C compiler for OHOS |
| `CFLAGS_aarch64_unknown_linux_ohos` | `--target=aarch64-linux-ohos --sysroot=C:/ohos/sdk/sysroot -D__MUSL__` | C compiler flags |
| `CXX_aarch64_unknown_linux_ohos` | `C:/ohos/sdk/llvm/bin/clang++.exe` | C++ compiler for OHOS |
| `CXXFLAGS_aarch64_unknown_linux_ohos` | `--target=aarch64-linux-ohos --sysroot=C:/ohos/sdk/sysroot -D__MUSL__` | C++ compiler flags |
| `AR_aarch64_unknown_linux_ohos` | `C:/ohos/sdk/llvm/bin/llvm-ar.exe` | Archiver for OHOS |
| `CARGO_TARGET_DIR` | `C:/uv-target` | Build output directory (no spaces) |
| `PATH` | prepend `C:/ohos/sdk/build-tools/cmake/bin` | Make ninja/cmake available |
| `RUSTUP_DIST_SERVER` | `https://mirrors.tuna.tsinghua.edu.cn/rustup` | (Optional) Chinese mirror for Rust toolchain downloads |
