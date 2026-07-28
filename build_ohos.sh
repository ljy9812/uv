#!/bin/sh
# OHOS native build script for uv
# Run this on the OHOS device

set -e

PROJECT_DIR="/storage/Users/currentUser/uv/uv"
CARGO_CONFIG_BAK="$PROJECT_DIR/.cargo/config.toml.bak"
CARGO_CONFIG="$PROJECT_DIR/.cargo/config.toml"
CARGO_CONFIG_NATIVE="$PROJECT_DIR/.cargo/config.native.toml"

echo "=== OHOS Native Build for uv ==="
echo ""

# Backup original config and use native config
if [ ! -f "$CARGO_CONFIG_BAK" ]; then
    echo "Backing up original .cargo/config.toml..."
    cp "$CARGO_CONFIG" "$CARGO_CONFIG_BAK"
fi
cp "$CARGO_CONFIG_NATIVE" "$CARGO_CONFIG"
echo "Using native OHOS cargo config."

# Source rust environment
export PATH="/storage/Users/currentUser/usr/rust-1.95.0-aarch64-unknown-linux-ohos/bin:$PATH"
export PATH="/data/service/hnp/bin:$PATH"
export TMPDIR="/storage/Users/currentUser"

# Verify tools
echo ""
echo "Checking tools..."
echo "  rustc: $(rustc --version 2>&1)"
echo "  cargo: $(cargo --version 2>&1)"
echo "  clang: $(clang --version 2>&1 | head -1)"
echo "  cmake: $(cmake --version 2>&1 | head -1)"
echo "  ninja: $(ninja --version 2>&1)"
echo ""

# Check target
echo "Checking Rust target..."
if rustc --print target-list | grep -q "aarch64-unknown-linux-ohos"; then
    echo "  aarch64-unknown-linux-ohos: supported"
else
    echo "  ERROR: aarch64-unknown-linux-ohos target not supported by this rustc"
    exit 1
fi
echo ""

# Build
cd "$PROJECT_DIR"
echo "Starting release build..."
echo ""

cargo build --release --target aarch64-unknown-linux-ohos -p uv \
    --no-default-features --features "uv-distribution/static,test-defaults" 2>&1

echo ""
echo "Build complete!"
echo "Binary: $PROJECT_DIR/target/aarch64-unknown-linux-ohos/release/uv"
ls -la "$PROJECT_DIR/target/aarch64-unknown-linux-ohos/release/uv" 2>/dev/null || true

# Strip
if [ -f "$PROJECT_DIR/target/aarch64-unknown-linux-ohos/release/uv" ]; then
    echo ""
    echo "Stripping binary..."
    llvm-strip "$PROJECT_DIR/target/aarch64-unknown-linux-ohos/release/uv" 2>/dev/null || \
        strip "$PROJECT_DIR/target/aarch64-unknown-linux-ohos/release/uv" 2>/dev/null || true
    ls -la "$PROJECT_DIR/target/aarch64-unknown-linux-ohos/release/uv"
    echo ""
    echo "Done!"
fi

# Restore original config
cp "$CARGO_CONFIG_BAK" "$CARGO_CONFIG"
echo "Restored original .cargo/config.toml"
