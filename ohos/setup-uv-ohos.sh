#!/bin/bash
# =============================================================
# setup-uv-ohos.sh
# 在 OHOS PC 终端上配置 uv 环境，使用已签名的 Python
# 用法: bash setup-uv-ohos.sh
# =============================================================
set -euo pipefail

PYTHON_VER="3.12.9"
JSON_PATH="$HOME/.config/uv/ohos-python.json"
UV_TOML="$HOME/.config/uv/uv.toml"
PYTHON_URL="https://gitcode.com/OpenHarmonyPCDeveloper/cmd-pkgs/releases/download/pkgs/python-${PYTHON_VER}-ohos-aarch64.tar.gz"

MAJOR=$(echo "$PYTHON_VER" | cut -d. -f1)
MINOR=$(echo "$PYTHON_VER" | cut -d. -f2)
PATCH=$(echo "$PYTHON_VER" | cut -d. -f3)

# --- 1. 创建 JSON 元数据 ---
echo "[1/3] 创建 Python 下载元数据..."
mkdir -p "$(dirname "$JSON_PATH")"
cat > "$JSON_PATH" << EOF
{
  "cpython-${PYTHON_VER}-linux-aarch64-musl": {
    "name": "cpython",
    "arch": { "family": "aarch64" },
    "os": "linux",
    "libc": "musl",
    "major": ${MAJOR},
    "minor": ${MINOR},
    "patch": ${PATCH},
    "url": "${PYTHON_URL}",
    "variant": "default"
  }
}
EOF
echo "      $JSON_PATH ✓"

# --- 2. 配置 uv.toml ---
echo "[2/3] 写入 uv 配置..."
if [ -f "$UV_TOML" ] && grep -q "python-downloads-json-url" "$UV_TOML"; then
    echo "      uv.toml 已包含 python-downloads-json-url，跳过"
else
    cat >> "$UV_TOML" << EOF

[install-mirrors]
python-downloads-json-url = "${JSON_PATH}"
EOF
    echo "      $UV_TOML ✓"
fi

# --- 3. 验证 ---
echo "[3/3] 验证配置..."
echo ""
echo "  JSON:    $JSON_PATH"
echo "  uv.toml: $UV_TOML"
echo ""
echo "配置完成！现在可以直接使用:"
echo ""
echo "  uv python install ${PYTHON_VER}"
echo "  uv python find ${MINOR}"
echo "  uv venv myenv --python ${MINOR}"
echo ""
