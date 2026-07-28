#!/bin/sh
# uv for HarmonyOS (OHOS) 一键安装脚本
#
# 用法（国内镜像）:
#   /bin/sh -c "$(curl -fsSL https://ghfast.top/https://github.com/ljy9812/uv/releases/download/ohos-latest/install-uv-ohos.sh)"
#
# 用法（直连 GitHub）:
#   /bin/sh -c "$(curl -fsSL https://github.com/ljy9812/uv/releases/download/ohos-latest/install-uv-ohos.sh)"
#
# 自定义安装目录:
#   INSTALL_DIR=/your/path /bin/sh -c "$(curl -fsSL ...)"

set -e

# ── 配置 ──────────────────────────────────────────────
REPO="ljy9812/uv"
BINARY_NAME="uv-ohos-aarch64"
INSTALL_DIR="${INSTALL_DIR:-/storage/Users/currentUser/usr/uv}"
RELEASE_TAG="ohos-latest"

# GitHub 直连地址
GITHUB_BASE="https://github.com/${REPO}/releases/download/${RELEASE_TAG}"
GITHUB_API="https://api.github.com/repos/${REPO}/releases/tags/${RELEASE_TAG}"

# 国内镜像代理（按优先级排列，2026年6月验证可用）
MIRRORS="
https://ghfast.top/
https://gh-proxy.com/
https://cf.ghproxy.cc/
"

CACERT="/etc/ssl/certs/cacert.pem"

# ── 颜色 ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { printf "${CYAN}==> ${NC}%s\n" "$1"; }
warn()  { printf "${YELLOW}==> ${NC}%s\n" "$1"; }
ok()    { printf "${GREEN}==> ${NC}%s\n" "$1"; }
fail()  { printf "${RED}==> ${NC}%s\n" "$1"; }

# ── 网络请求封装 ──────────────────────────────────────
# 尝试 curl，自动处理证书问题
_do_curl() {
    url="$1"
    output="$2"  # 可选：输出文件路径

    if [ -n "$output" ]; then
        if [ -f "$CACERT" ]; then
            curl -fSL --cacert "$CACERT" --retry 1 --connect-timeout 10 --max-time 300 -o "$output" "$url" 2>/dev/null && return 0
        fi
        curl -fSL -k --retry 1 --connect-timeout 10 --max-time 300 -o "$output" "$url" 2>/dev/null && return 0
    else
        if [ -f "$CACERT" ]; then
            curl -fsSL --cacert "$CACERT" --connect-timeout 10 "$url" 2>/dev/null && return 0
        fi
        curl -fsSL -k --connect-timeout 10 "$url" 2>/dev/null && return 0
    fi
    return 1
}

# 带镜像回退的下载：先尝试镜像，最后回退到 GitHub 直连
download_with_fallback() {
    github_url="$1"
    output="$2"

    # 先尝试各镜像
    for mirror in $MIRRORS; do
        mirror_url="${mirror}${github_url}"
        info "尝试镜像: ${mirror%%/}"
        if _do_curl "$mirror_url" "$output"; then
            ok "镜像下载成功"
            return 0
        fi
        warn "镜像失败: ${mirror%%/}"
    done

    # 回退到 GitHub 直连
    info "尝试 GitHub 直连..."
    if _do_curl "$github_url" "$output"; then
        ok "直连下载成功"
        return 0
    fi

    return 1
}

# 获取文本内容（用于 API 调用），带镜像回退
fetch_text_with_fallback() {
    github_url="$1"

    # 先尝试 GitHub 直连（API 不一定有镜像）
    result=$(_do_curl "$github_url" "") && { echo "$result"; return 0; }

    # 尝试镜像代理
    for mirror in $MIRRORS; do
        mirror_url="${mirror}${github_url}"
        result=$(_do_curl "$mirror_url" "") && { echo "$result"; return 0; }
    done

    return 1
}

# ── 前置检查 ──────────────────────────────────────────
check_prereqs() {
    if ! command -v curl >/dev/null 2>&1; then
        fail "需要 curl，请先安装"
        exit 1
    fi

    if [ "$(uname -m)" != "aarch64" ]; then
        fail "本包仅支持 aarch64 架构，当前: $(uname -m)"
        exit 1
    fi

    # 检查安装目录可写
    if [ ! -d "$INSTALL_DIR" ]; then
        info "创建安装目录: $INSTALL_DIR"
        mkdir -p "$INSTALL_DIR" 2>/dev/null || {
            fail "无法创建目录: $INSTALL_DIR"
            fail "请通过 INSTALL_DIR 环境变量指定可写目录"
            exit 1
        }
    fi

    touch "$INSTALL_DIR/.uv_write_test" 2>/dev/null && rm -f "$INSTALL_DIR/.uv_write_test" || {
        fail "安装目录不可写: $INSTALL_DIR"
        fail "请通过 INSTALL_DIR 环境变量指定可写目录"
        exit 1
    }
}

# ── 获取最新版本 ──────────────────────────────────────
get_latest_version() {
    info "查询最新版本..."

    release_json=$(fetch_text_with_fallback "$GITHUB_API") || {
        fail "无法获取版本信息，请检查网络连接"
        fail "或手动下载: https://github.com/${REPO}/releases"
        exit 1
    }

    # 提取 tag_name
    TAG=$(echo "$release_json" | grep -m1 '"tag_name"' | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

    if [ -z "$TAG" ]; then
        # API 失败时使用默认 tag
        TAG="$RELEASE_TAG"
        warn "无法解析版本号，使用默认标签: $TAG"
    else
        ok "最新版本: $TAG"
    fi
}

# ── 下载 ──────────────────────────────────────────────
download() {
    download_url="${GITHUB_BASE}/${BINARY_NAME}"
    uvx_url="${GITHUB_BASE}/uvx-ohos-aarch64"
    target_path="${INSTALL_DIR}/uv"
    uvx_target_path="${INSTALL_DIR}/uvx"

    # 检查是否已存在
    if [ -f "$target_path" ]; then
        existing_ver=$("$target_path" --version 2>/dev/null || echo "unknown")
        warn "已存在 uv: $existing_ver"
        printf "是否覆盖？[y/N] "
        read -r answer < /dev/tty
        case "$answer" in
            y*|Y*) ;;
            *) ok "保留现有版本，跳过安装"; return 1 ;;
        esac
    fi

    info "下载 uv (OHOS aarch64)..."

    # 下载 uv
    tmp_file="${INSTALL_DIR}/.uv_downloading"
    if download_with_fallback "$download_url" "$tmp_file"; then
        mv "$tmp_file" "$target_path"
    else
        rm -f "$tmp_file"
        fail "下载失败，所有镜像和直连均不可用"
        fail "  URL: $download_url"
        exit 1
    fi

    # 下载 uvx
    info "下载 uvx (OHOS aarch64)..."
    tmp_file="${INSTALL_DIR}/.uvx_downloading"
    if download_with_fallback "$uvx_url" "$tmp_file"; then
        mv "$tmp_file" "$uvx_target_path"
    else
        rm -f "$tmp_file"
        warn "uvx 下载失败，uvx 命令将不可用"
        warn "  URL: $uvx_url"
    fi
}

# ── 安装 ──────────────────────────────────────────────
install_binary() {
    target_path="${INSTALL_DIR}/uv"
    uvx_target_path="${INSTALL_DIR}/uvx"

    info "设置可执行权限..."
    chmod +x "$target_path"
    if [ -f "$uvx_target_path" ]; then
        chmod +x "$uvx_target_path"
    fi

    # OHOS/HarmonyOS ELF 签名：部分设备需要签名后才能执行
    SIGN_TOOL=""
    if [ -n "$OHOS_BINARY_SIGN_TOOL" ] && [ -x "$OHOS_BINARY_SIGN_TOOL" ]; then
        SIGN_TOOL="$OHOS_BINARY_SIGN_TOOL"
    elif command -v binary-sign-tool >/dev/null 2>&1; then
        SIGN_TOOL="binary-sign-tool"
    else
        for sign_tool in \
            "$HOME"/usr/rust-*/tool/binary-sign-tool \
            /data/local/tmp/rust-*/tool/binary-sign-tool \
            /storage/Users/currentUser/usr/rust-*/tool/binary-sign-tool; do
            if [ -x "$sign_tool" ]; then
                SIGN_TOOL="$sign_tool"
                break
            fi
        done
    fi

    if [ -n "$SIGN_TOOL" ]; then
        info "使用签名工具: $SIGN_TOOL"
        "$SIGN_TOOL" "$target_path" 2>/dev/null && ok "uv 签名完成" || warn "uv 签名失败，尝试继续..."
        if [ -f "$uvx_target_path" ]; then
            "$SIGN_TOOL" "$uvx_target_path" 2>/dev/null && ok "uvx 签名完成" || warn "uvx 签名失败，尝试继续..."
        fi
    fi

    # 首次运行确认（OHOS ELF 签名机制可能需要）
    info "验证安装..."
    ver=$("$target_path" --version 2>&1) || {
        fail "uv 无法运行: $ver"
        fail ""
        fail "OHOS 需要对 ELF 二进制进行签名后才能执行。"
        fail "如果你已安装 Rust 工具链，请运行："
        fail ""
        fail "  \$OHOS_BINARY_SIGN_TOOL $target_path"
        fail ""
        fail "或查找签名工具："
        fail "  find \$HOME/usr -name binary-sign-tool"
        exit 1
    }

    ok "安装成功: $ver"
}

# ── PATH 配置 ─────────────────────────────────────────
setup_path() {
    ZSHRC="$HOME/.zshrc"
    COMMENT_LINE="# uv Python environment"
    PATH_LINE="export PATH=\"${INSTALL_DIR}:\$PATH\""
    UV_PYTHON_LINE="export UV_PYTHON_INSTALL_DIR=${INSTALL_DIR}/.local/share/uv/python"

    # 分别检查 PATH 和 UV_PYTHON_INSTALL_DIR
    NEED_PATH=true
    NEED_UV_PYTHON=true

    if [ -f "$ZSHRC" ]; then
        if grep -qF "PATH=\"${INSTALL_DIR}" "$ZSHRC"; then NEED_PATH=false; fi
        if grep -qF "UV_PYTHON_INSTALL_DIR" "$ZSHRC"; then NEED_UV_PYTHON=false; fi
    fi

    if [ "$NEED_PATH" = true ] || [ "$NEED_UV_PYTHON" = true ]; then
        info "配置 ~/.zshrc ..."
        # 只把真正的 export 行写入 .zshrc；ok/info 的彩色提示走终端，避免污染 rc 文件
        {
            echo ""
            echo "$COMMENT_LINE"
            if [ "$NEED_PATH" = true ]; then
                echo "$PATH_LINE"
            fi
            if [ "$NEED_UV_PYTHON" = true ]; then
                echo "$UV_PYTHON_LINE"
            fi
        } >> "$ZSHRC"
        if [ "$NEED_PATH" = true ]; then ok "PATH 已添加"; fi
        if [ "$NEED_UV_PYTHON" = true ]; then ok "UV_PYTHON_INSTALL_DIR 已添加"; fi
    else
        info "PATH 和 UV_PYTHON_INSTALL_DIR 已配置在 $ZSHRC，跳过"
    fi

    # 确保当前 shell 也加载
    export PATH="${INSTALL_DIR}:$PATH"
    export UV_PYTHON_INSTALL_DIR="${INSTALL_DIR}/.local/share/uv/python"
    source "$ZSHRC" 2>/dev/null || true
}

# ── Python 检测与安装 ─────────────────────────────────
setup_python() {
    UV_PYTHON_DIR="${INSTALL_DIR}/.local/share/uv/python"

    info "检测 Python ..."

    PYTHON_PATH=$(command -v python 2>/dev/null || true)
    if [ -n "$PYTHON_PATH" ]; then
        ok "Python 已存在: $PYTHON_PATH"
        return 0
    fi

    PYTHON3_PATH=$(command -v python3 2>/dev/null || true)
    if [ -z "$PYTHON3_PATH" ]; then
        info "未找到 Python，通过社区脚本安装 ..."
        if curl -fsSL https://gitcode.com/OpenHarmonyPCDeveloper/cmd-pkgs/releases/download/pkgs/install.sh | sh -s -- python 3.12.9; then
            source "$HOME/.zshrc" 2>/dev/null || true
            PYTHON3_PATH=$(command -v python3 2>/dev/null || true)
        fi
    fi

    if [ -z "$PYTHON3_PATH" ]; then
        warn "Python 安装失败，可稍后运行: ${INSTALL_DIR}/uv python install 3.12"
        return 1
    fi

    # 将 Python 复制到 uv 管理的目录
    PYTHON_INSTALL_PREFIX=$(dirname "$(dirname "$PYTHON3_PATH")")
    PYTHON_VERSION=$("$PYTHON3_PATH" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')")
    PYTHON_DEST="$UV_PYTHON_DIR/cpython-$PYTHON_VERSION-linux-aarch64-musl"

    info "安装 Python $PYTHON_VERSION 到: $PYTHON_DEST"
    mkdir -p "$PYTHON_DEST/bin" "$PYTHON_DEST/lib" "$PYTHON_DEST/include"
    cp -r "$PYTHON_INSTALL_PREFIX/bin"/* "$PYTHON_DEST/bin/" 2>/dev/null || true
    cp -r "$PYTHON_INSTALL_PREFIX/lib"/* "$PYTHON_DEST/lib/" 2>/dev/null || true
    cp -r "$PYTHON_INSTALL_PREFIX/include"/* "$PYTHON_DEST/include/" 2>/dev/null || true

    ln -sf python3.12 "$PYTHON_DEST/bin/python3" 2>/dev/null || true
    ln -sf python3.12 "$PYTHON_DEST/bin/python" 2>/dev/null || true

    # 固定 Python 版本
    echo "$PYTHON_VERSION" > "$HOME/.python-version"
    ok "Python $PYTHON_VERSION 已安装，版本固定: $HOME/.python-version"
}

# ── 完成 ──────────────────────────────────────────────
print_success() {
    target_path="${INSTALL_DIR}/uv"
    echo ""
    printf "${GREEN}${BOLD}  ✅ uv 安装成功！${NC}\n"
    echo ""
    printf "  版本:      ${CYAN}${TAG}${NC}\n"
    printf "  安装位置:  ${CYAN}${target_path}${NC}\n"
    echo ""
    printf "  ${BOLD}使用方法：${NC}\n"
    echo ""
    printf "    ${YELLOW}uv --version${NC}\n"
    printf "    ${YELLOW}uv python install 3.12${NC}\n"
    printf "    ${YELLOW}uv venv myenv${NC}\n"
    printf "    ${YELLOW}uv pip install requests${NC}\n"
    echo ""
    printf "  ${BOLD}卸载：${NC}\n"
    echo ""
    printf "    ${YELLOW}rm ${target_path}${NC}\n"
    echo ""
}

# ── 主流程 ────────────────────────────────────────────
main() {
    echo ""
    printf "${CYAN}${BOLD}  📦 uv for HarmonyOS (OHOS) 安装程序${NC}\n"
    echo "  ----------------------------------------"
    echo ""

    check_prereqs
    get_latest_version

    if download; then
        install_binary
        setup_path
        setup_python
        print_success
    fi
}

main "$@"
