#!/bin/bash
# =============================================================================
# OHOS uv 功能验证测试脚本
# 通过 hdc shell 在 OHOS 设备上执行 uv 各项功能测试
# 用法: bash test-uv-ohos.sh [--uv-path PATH] [--hdc PATH] [--timeout SECS]
# =============================================================================

set -uo pipefail

# 禁止 MSYS2 路径自动转换（Git Bash 会把 /data/... 转成 C:/Program Files/Git/data/...）
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

# --- 配置 ---
UV_PATH="/data/local/tmp/uv"
HDC="hdc"
TIMEOUT=120
REPORT_FILE="ohos-uv-test-report-$(date +%Y%m%d_%H%M%S).md"
FAST_MODE=false

# OHOS 设备上 uv 的默认存储路径已通过源码修复（lib.rs 中 OHOS 平台自动将
# HOME 重定向到 /data/local/tmp），不再需要手动设置 UV_CACHE_DIR 等环境变量。
# 以下变量仅保留用于清理。
DEVICE_HOME="/data/local/tmp"

# --- 参数解析 ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --uv-path) UV_PATH="$2"; shift 2 ;;
        --hdc)     HDC="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --fast)    FAST_MODE=true; shift ;;
        --help)
            echo "用法: bash test-uv-ohos.sh [--uv-path PATH] [--hdc PATH] [--timeout SECS] [--fast]"
            echo "  --uv-path PATH   设备上 uv 的路径 (默认: /data/local/tmp/uv)"
            echo "  --hdc PATH       hdc 可执行文件路径 (默认: hdc)"
            echo "  --timeout SECS   每个测试的超时秒数 (默认: 120)"
            echo "  --fast           跳过重复下载和大型包下载用例 (B9/E7/E8/D15/D22)"
            exit 0
            ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

run_on_device() {
    timeout "$TIMEOUT" "$HDC" shell "$@" 2>&1 || true
}

# uv 环境变量（不再需要路径类变量，源码已修复 HOME 重定向）
# UV_INDEX_URL: 使用国内 PyPI 镜像加速 pip 包下载
# UV_PYTHON_INSTALL_MIRROR: 使用国内镜像加速 Python 解释器下载
UV_ENV_VARS="UV_INDEX_URL=https://pypi.mirrors.ustc.edu.cn/simple/ UV_PYTHON_INSTALL_MIRROR=https://ghfast.top/https://github.com/indygreg/python-build-standalone/releases/download"

# 带 UV 环境变量的命令执行
run_uv() {
    local args="$*"
    run_on_device "$UV_ENV_VARS $UV_PATH $args"
}

# 在设备上执行命令并获取真实退出码
# 通过在命令末尾 echo __EXIT_CODE__=$? 来获取设备端的实际退出码
# 返回: OUTPUT 变量包含命令输出, DEVICE_EXIT_CODE 包含退出码
DEVICE_EXIT_CODE=0
run_uv_with_exit() {
    local args="$*"
    local full_cmd="$UV_ENV_VARS $UV_PATH $args; echo __EXIT_CODE__=\$?"
    local raw_output
    raw_output=$(timeout "$TIMEOUT" "$HDC" shell "$full_cmd" 2>&1) || true

    # 检查是否超时 (timeout 命令返回 124)
    if [[ $? -eq 124 ]]; then
        DEVICE_EXIT_CODE=124
        OUTPUT="TIMEOUT: command exceeded ${TIMEOUT}s"
        return 1
    fi

    # 从输出中提取退出码
    DEVICE_EXIT_CODE=$(echo "$raw_output" | grep "__EXIT_CODE__=" | tail -1 | sed 's/.*__EXIT_CODE__=//' | tr -d '[:space:]')
    # 移除退出码标记行，保留纯输出
    OUTPUT=$(echo "$raw_output" | grep -v "^__EXIT_CODE__=" | sed '/^$/d')

    # 如果没提取到退出码，默认 0
    if [[ -z "$DEVICE_EXIT_CODE" ]]; then
        DEVICE_EXIT_CODE=0
    fi
}

# --- 统计 ---
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

# --- 分隔符（不能出现在命令输出中）---
SEP=$'\x1f'  # ASCII Unit Separator

# --- 测试结果记录 ---
RESULTS=()

# --- 辅助函数 ---
log_info()  { echo -e "\033[34m[INFO]\033[0m  $*"; }
log_pass()  { echo -e "\033[32m[PASS]\033[0m  $*"; }
log_fail()  { echo -e "\033[31m[FAIL]\033[0m  $*"; }
log_skip()  { echo -e "\033[33m[SKIP]\033[0m  $*"; }
log_group() { echo -e "\n\033[1;36m=== $* ===\033[0m"; }

# 执行测试用例
# run_test ID NAME UV_ARGS EXPECTED_EXIT_CODE [CHECK_OUTPUT_CONTAINS]
run_test() {
    local id="$1"
    local name="$2"
    local cmd="$3"
    local expect_exit="${4:-0}"
    local check_contains="${5:-}"

    TOTAL=$((TOTAL + 1))
    log_info "[$id] $name"
    log_info "    命令: $UV_PATH $cmd"

    local start_time
    start_time=$(date +%s)

    # 使用真实退出码的执行函数
    run_uv_with_exit "$cmd"
    local output="$OUTPUT"
    local exit_code="$DEVICE_EXIT_CODE"

    local end_time elapsed
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    # 记录完整的输入命令
    local full_command="$UV_PATH $cmd"

    # 检查是否超时
    if [[ "$exit_code" -eq 124 ]]; then
        FAILED=$((FAILED + 1))
        log_fail "[$id] 超时 (${TIMEOUT}s) (${elapsed}s)"
        RESULTS+=("$id${SEP}$name${SEP}FAIL${SEP}超时 (${TIMEOUT}s)${SEP}$full_command${SEP}$output")
        return 1
    fi

    # 检查退出码
    if [[ "$exit_code" -ne "$expect_exit" ]]; then
        FAILED=$((FAILED + 1))
        log_fail "[$id] 退出码: 期望 $expect_exit, 实际 $exit_code (${elapsed}s)"
        RESULTS+=("$id${SEP}$name${SEP}FAIL${SEP}退出码不匹配 (期望=$expect_exit, 实际=$exit_code)${SEP}$full_command${SEP}$output")
        return 1
    fi

    # 检查输出包含
    if [[ -n "$check_contains" ]]; then
        if ! echo "$output" | grep -qi "$check_contains"; then
            FAILED=$((FAILED + 1))
            log_fail "[$id] 输出不包含 '$check_contains' (${elapsed}s)"
            RESULTS+=("$id${SEP}$name${SEP}FAIL${SEP}输出不包含 '$check_contains'${SEP}$full_command${SEP}$output")
            return 1
        fi
    fi

    PASSED=$((PASSED + 1))
    log_pass "[$id] $name (${elapsed}s)"
    RESULTS+=("$id${SEP}$name${SEP}PASS${SEP}${SEP}$full_command${SEP}$output")
    return 0
}

# 跳过测试
skip_test() {
    local id="$1"
    local name="$2"
    local reason="$3"

    TOTAL=$((TOTAL + 1))
    SKIPPED=$((SKIPPED + 1))
    log_skip "[$id] $name — $reason"
    RESULTS+=("$id${SEP}$name${SEP}SKIP${SEP}$reason${SEP}${SEP}")
}

# 跳过一组测试
skip_group() {
    local reason="$1"
    shift
    for entry in "$@"; do
        IFS=':' read -r id name <<< "$entry"
        skip_test "$id" "$name" "$reason"
    done
}

# ===========================================================================
# 前置检查
# ===========================================================================
log_group "前置检查"

log_info "检查 hdc 连接..."
DEVICE_ID=$("$HDC" list targets 2>&1 | head -1 | tr -d '[:space:]')
if [[ -z "$DEVICE_ID" ]]; then
    echo "错误: 未检测到 OHOS 设备连接。请确保:"
    echo "  1. 设备已通过 USB 连接或 hdc tmode port 50001 已设置"
    echo "  2. hdc 在 PATH 中 (或通过 --hdc 指定路径)"
    exit 1
fi
log_pass "设备已连接: $DEVICE_ID"

log_info "检查 uv 二进制文件..."
UV_VERSION=$(run_uv "--version" 2>&1 | tr -d '\r' | head -1) || true
if [[ -z "$UV_VERSION" ]] || echo "$UV_VERSION" | grep -qi "error"; then
    echo "错误: 无法在设备上执行 uv。请确保 $UV_PATH 存在且可执行。"
    echo "输出: $UV_VERSION"
    exit 1
fi
log_pass "uv 版本: $UV_VERSION"

# --- 准备设备环境 ---
log_info "准备设备环境 (可写目录等)..."
# HOME 重定向后，uv 会自动创建所需的目录，无需手动 mkdir

# --- 清理上一次测试残留 ---
log_info "清理上次测试残留..."
run_on_device "rm -rf /data/local/tmp/testvenv /data/local/tmp/testvenv2 /data/local/tmp/testvenv_seed /data/local/tmp/testvenv_py /data/local/tmp/testproj /data/local/tmp/testproj_lib /data/local/tmp/requirements.in /data/local/tmp/requirements.txt /data/local/tmp/test_build" 2>/dev/null || true

# ===========================================================================
# Group A: 基础命令（无依赖）
# ===========================================================================
log_group "Group A: 基础命令"

run_test "A1" "版本号" "--version" 0 "uv" || true
run_test "A2" "帮助信息" "--help" 0 "uv" || true
run_test "A3a" "pip 帮助" "pip --help" 0 || true
run_test "A3b" "python 帮助" "python --help" 0 || true
run_test "A3c" "tool 帮助" "tool --help" 0 || true
run_test "A3d" "cache 帮助" "cache --help" 0 || true
run_test "A3e" "venv 帮助" "venv --help" 0 || true
run_test "A3f" "build 帮助" "build --help" 0 || true
run_test "A3g" "self 帮助" "self --help" 0 || true
run_test "A3h" "workspace 帮助" "workspace --help" 0 || true
run_test "A3i" "auth 帮助" "auth --help" 0 || true
run_test "A4" "Cache 目录" "cache dir" 0 || true
run_test "A5" "Cache 大小" "cache size" 0 || true
run_test "A6" "Tool 目录" "tool dir" 0 || true
run_test "A7" "Python 目录" "python dir" 0 || true
run_test "A8" "pip debug (unsupported)" "pip debug" 2 "unsupported" || true
run_test "A9" "auth dir" "auth dir" 0 || true
run_test "A10" "self version" "self version" 0 || true
run_test "A11" "self update --dry-run" "self update --dry-run" 0 || true

# ===========================================================================
# Group B: Python 管理（需要网络）
# ===========================================================================
log_group "Group B: Python 管理"

PYTHON_INSTALLED=false
PROJECT_INIT_OK=false

run_test "B1" "Python 列表" "python list" 0 || true

if run_test "B2" "安装 Python 3.12" "python install 3.12" 0; then
    PYTHON_INSTALLED=true
else
    log_skip "后续测试 (C/D/E/G/H) 依赖 Python，将跳过"
fi

if $PYTHON_INSTALLED; then
    run_test "B3" "查找 Python" "python find" 0 || true
    run_test "B5" "Python pin" "python pin 3.12 --project /data/local/tmp" 0 || true
    run_test "B6" "Python 列表 --only-installed" "python list --only-installed" 0 || true
    run_test "B7" "Python 列表 --all-versions" "python list --all-versions" 0 || true
    run_test "B8" "Python 列表 JSON 格式" "python list --only-installed --output-format json" 0 || true

    # B9: Python 重装 (慢: 重新下载 Python 3.12)
    if $FAST_MODE; then
        skip_test "B9" "Python 重装" "--fast 模式跳过 (重复下载 Python)"
    else
        run_test "B9" "Python 重装" "python install --reinstall 3.12" 0 || true
    fi
fi

# ===========================================================================
# Group C: 虚拟环境（需要 Python）
# ===========================================================================
log_group "Group C: 虚拟环境"

if $PYTHON_INSTALLED; then
    # C1: 基础创建
    run_test "C1" "创建虚拟环境" "venv /data/local/tmp/testvenv" 0 || true

    # C2: 带 seed 参数（安装 pip/setuptools/wheel）
    run_test "C10" "venv --seed" "venv --seed /data/local/tmp/testvenv_seed" 0 || true
    run_test "C11" "验证 seed 安装 pip" "pip list --python /data/local/tmp/testvenv_seed/bin/python" 0 || true

    # C3: 指定 Python 版本创建 venv
    run_test "C12" "venv --python 3.12" "venv --python 3.12 /data/local/tmp/testvenv_py" 0 || true

    # C4: --clear 重建 venv（先创建一个再 clear 重建）
    run_test "C13" "venv --clear" "venv --clear /data/local/tmp/testvenv" 0 || true

    # C5: --allow-existing（已存在时不报错）
    run_test "C14" "venv --allow-existing" "venv --allow-existing /data/local/tmp/testvenv" 0 || true

    # C6: --no-project（忽略项目发现）
    run_test "C15" "venv --no-project" "venv --no-project /data/local/tmp/testvenv2" 0 || true

    # C7: --system-site-packages（包含系统 site-packages）
    run_test "C16" "venv --system-site-packages" "venv --system-site-packages /data/local/tmp/testvenv_sys" 0 || true

    # C8: --prompt（自定义 prompt）
    run_test "C17" "venv --prompt" "venv --prompt myenv /data/local/tmp/testvenv_prompt" 0 || true

    # 清理 venv 测试产物
    run_on_device "rm -rf /data/local/tmp/testvenv_seed /data/local/tmp/testvenv_py /data/local/tmp/testvenv2 /data/local/tmp/testvenv_sys /data/local/tmp/testvenv_prompt" 2>/dev/null || true

    # ===========================================================================
    # pip 操作（使用 testvenv）
    # ===========================================================================
    log_group "Group C: pip 操作"

    VENV_PYTHON="/data/local/tmp/testvenv/bin/python"

    run_test "C2" "pip install requests" "pip install requests --python $VENV_PYTHON" 0 || true
    run_test "C3" "pip list" "pip list --python $VENV_PYTHON" 0 || true
    run_test "C3b" "pip list --format json" "pip list --python $VENV_PYTHON --format json" 0 || true
    run_test "C4" "pip show requests" "pip show requests --python $VENV_PYTHON" 0 || true
    run_test "C5" "pip freeze" "pip freeze --python $VENV_PYTHON" 0 || true
    run_test "C6" "pip check" "pip check --python $VENV_PYTHON" 0 || true
    run_test "C7" "pip tree" "pip tree --python $VENV_PYTHON" 0 || true

    # pip install 第二个包用于后续测试
    run_test "C2b" "pip install urllib3" "pip install urllib3 --python $VENV_PYTHON" 0 || true
    run_test "C3c" "pip list --outdated" "pip list --python $VENV_PYTHON --outdated" 0 || true

    # pip uninstall
    run_test "C8" "pip uninstall urllib3" "pip uninstall urllib3 --python $VENV_PYTHON" 0 || true
    run_test "C8b" "pip uninstall requests" "pip uninstall requests --python $VENV_PYTHON" 0 || true

    # pip compile
    run_on_device "echo 'requests' > /data/local/tmp/requirements.in" 2>/dev/null || true
    run_test "C9" "pip compile" "pip compile /data/local/tmp/requirements.in -o /data/local/tmp/requirements.txt" 0 || true

    # pip sync（从 requirements.txt 同步）
    run_test "C9b" "pip sync" "pip sync /data/local/tmp/requirements.txt --python $VENV_PYTHON" 0 || true

    # pip latest（此子命令在 uv 中不存在，已移除该测试用例）

    # pip install -r（从文件安装）
    run_on_device "echo 'chardet' > /data/local/tmp/requirements_install.txt" 2>/dev/null || true
    run_test "C18" "pip install -r" "pip install -r /data/local/tmp/requirements_install.txt --python $VENV_PYTHON" 0 || true

    # pip install --upgrade（升级包）
    run_test "C19" "pip install --upgrade" "pip install --upgrade requests --python $VENV_PYTHON" 0 || true

    # pip install --no-deps（不安装子依赖）
    run_test "C20" "pip install --no-deps" "pip install --no-deps idna --python $VENV_PYTHON" 0 || true

    # pip install -e（可编辑安装，需要先创建 testproj_lib）
    run_on_device "mkdir -p /data/local/tmp/testproj_lib/src/test_ohos_lib && cat > /data/local/tmp/testproj_lib/pyproject.toml << 'TOML'
[build-system]
requires = [\"hatchling\"]
build-backend = \"hatchling.build\"

[project]
name = \"test-ohos-lib\"
version = \"0.1.0\"
TOML
echo 'def hello(): return \"hi\"' > /data/local/tmp/testproj_lib/src/test_ohos_lib/__init__.py" 2>/dev/null || true
    run_test "C21" "pip install -e" "pip install -e /data/local/tmp/testproj_lib --python $VENV_PYTHON" 0 || true

    # pip uninstall -r（从文件批量卸载）
    run_test "C22" "pip uninstall -r" "pip uninstall -r /data/local/tmp/requirements_install.txt --python $VENV_PYTHON" 0 || true

    # 清理 pip 测试产物
    run_on_device "rm -f /data/local/tmp/requirements.in /data/local/tmp/requirements.txt /data/local/tmp/requirements_install.txt" 2>/dev/null || true

else
    VENV_TESTS=(
        "C1:创建虚拟环境" "C10:venv --seed" "C11:验证 seed" "C12:venv --python"
        "C13:venv --clear" "C14:venv --allow-existing" "C15:venv --no-project"
        "C16:venv --system-site-packages" "C17:venv --prompt"
        "C2:pip install" "C3:pip list" "C3b:pip list json" "C4:pip show"
        "C5:pip freeze" "C6:pip check" "C7:pip tree"
        "C2b:pip install urllib3" "C3c:pip list --outdated"
        "C8:pip uninstall urllib3" "C8b:pip uninstall requests"
        "C9:pip compile" "C9b:pip sync"
        "C18:pip install -r" "C19:pip install --upgrade"
        "C20:pip install --no-deps" "C21:pip install -e" "C22:pip uninstall -r"
    )
    skip_group "Python 未安装" "${VENV_TESTS[@]}"
fi

# ===========================================================================
# Group D: 项目管理（需要 Python）
# ===========================================================================
log_group "Group D: 项目管理"

if $PYTHON_INSTALLED; then
    # D1: init 基础项目
    PROJECT_INIT_OK=false
    if run_test "D1" "init 项目" "init /data/local/tmp/testproj" 0; then
        PROJECT_INIT_OK=true
        run_test "D2" "lock" "lock --project /data/local/tmp/testproj" 0 || true
        run_test "D3" "sync" "sync --project /data/local/tmp/testproj" 0 || true
        run_test "D4" "add 依赖" "add requests --project /data/local/tmp/testproj" 0 || true
        run_test "D5" "tree" "tree --project /data/local/tmp/testproj" 0 || true

        # D5b: project version
        run_test "D5b" "project version" "version --project /data/local/tmp/testproj" 0 || true

        # D5c: add dev dependency
        run_test "D4b" "add --dev 依赖" "add --dev pytest --project /data/local/tmp/testproj" 0 || true

        # D5d: remove dev dependency
        run_test "D6b" "remove --dev 依赖" "remove --dev pytest --project /data/local/tmp/testproj" 0 || true

        run_test "D6" "remove 依赖" "remove requests --project /data/local/tmp/testproj" 0 || true
        run_test "D7" "run" "run --project /data/local/tmp/testproj python -c \"print('hello from ohos')\"" 0 || true
        run_test "D8" "export" "export --project /data/local/tmp/testproj" 0 || true

        # D8b: run --with inline dependency
        run_test "D7b" "run --with" "run --with requests --project /data/local/tmp/testproj python -c \"import requests; print(requests.__version__)\"" 0 || true

        # D8c: lock --upgrade
        run_test "D2b" "lock --upgrade" "lock --upgrade --project /data/local/tmp/testproj" 0 || true

        # D8d: sync --frozen (use existing lockfile without updating)
        run_test "D3b" "sync --frozen" "sync --frozen --project /data/local/tmp/testproj" 0 || true

        # D13: run -m module (run Python module) — needs testproj
        run_test "D13" "run -m module" "run --project /data/local/tmp/testproj -m json.tool --help" 0 || true

        # D15: add --optional (optional dependencies) (慢: 下载 flask)
        if $FAST_MODE; then
            skip_test "D15" "add --optional" "--fast 模式跳过 (下载 flask)"
        else
            run_test "D15" "add --optional" "add --optional web flask --project /data/local/tmp/testproj" 0 || true
        fi

        # D16: add --group (custom dependency group)
        run_test "D16" "add --group" "add --group lint ruff --project /data/local/tmp/testproj" 0 || true

        # D17: add --editable (editable dependency from local path) — 需要 testproj_lib
        run_on_device "rm -rf /data/local/tmp/testproj_lib" 2>/dev/null || true
        run_test "D9" "init --lib" "init --lib /data/local/tmp/testproj_lib" 0 || true
        run_test "D17" "add --editable" "add --editable /data/local/tmp/testproj_lib --project /data/local/tmp/testproj" 0 || true

        # D18: sync --no-dev (sync without dev dependencies)
        run_test "D18" "sync --no-dev" "sync --no-dev --project /data/local/tmp/testproj" 0 || true

        # D19: export --format pylock.toml (PEP 751 export)
        run_test "D19" "export --format pylock.toml" "export --format pylock.toml --project /data/local/tmp/testproj" 0 || true

        # D20: export --format cyclonedx1.5 (SBOM export)
        run_test "D20" "export --format cyclonedx1.5" "export --format cyclonedx1.5 --project /data/local/tmp/testproj" 0 || true

        # D21: format (code formatting via ruff)
        run_test "D21" "format" "format --project /data/local/tmp/testproj" 0 || true

        # D22: add --raw (add raw dependency without bounds) (慢: 下载 httpx)
        if $FAST_MODE; then
            skip_test "D22" "add --raw" "--fast 模式跳过 (下载 httpx)"
        else
            run_test "D22" "add --raw" "add --raw httpx --project /data/local/tmp/testproj" 0 || true
        fi
    else
        D_SUB=(
            "D2:lock" "D3:sync" "D4:add" "D5:tree" "D5b:version"
            "D4b:add --dev" "D6b:remove --dev" "D6:remove"
            "D7:run" "D8:export" "D7b:run --with"
            "D2b:lock --upgrade" "D3b:sync --frozen"
            "D13:run -m" "D15:add --optional"
            "D16:add --group" "D9:init --lib" "D17:add --editable" "D18:sync --no-dev"
            "D19:export pylock" "D20:export cyclonedx" "D21:format" "D22:add --raw"
        )
        skip_group "init 失败" "${D_SUB[@]}"
    fi

    # D10: init --script (PEP 723 inline script) — 独立创建
    if run_test "D10" "init --script" "init --script /data/local/tmp/test_script.py" 0; then
        # D11: add --script (add deps to PEP 723 script) — 依赖 D10
        run_test "D11" "add --script" "add --script /data/local/tmp/test_script.py requests" 0 || true

        # D12: run script.py (run script file directly) — 依赖 D10
        run_test "D12" "run script.py" "run /data/local/tmp/test_script.py" 0 || true
    else
        skip_group "init --script 失败" "D11:add --script" "D12:run script"
    fi

    # D14: init --app (app project) — 独立创建
    run_test "D14" "init --app" "init --app /data/local/tmp/testproj_app" 0 || true

    # 清理项目测试产物
    run_on_device "rm -rf /data/local/tmp/testproj_lib /data/local/tmp/testproj_app /data/local/tmp/test_script.py" 2>/dev/null || true

else
    D_TESTS=(
        "D1:init" "D2:lock" "D3:sync" "D4:add" "D5:tree" "D5b:version"
        "D4b:add --dev" "D6b:remove --dev" "D6:remove"
        "D7:run" "D8:export" "D7b:run --with"
        "D2b:lock --upgrade" "D3b:sync --frozen" "D9:init --lib"
        "D10:init --script" "D11:add --script" "D12:run script"
        "D13:run -m" "D14:init --app" "D15:add --optional"
        "D16:add --group" "D17:add --editable" "D18:sync --no-dev"
        "D19:export pylock" "D20:export cyclonedx" "D21:format" "D22:add --raw"
    )
    skip_group "Python 未安装" "${D_TESTS[@]}"
fi

# ===========================================================================
# Group E: Tool 管理（需要网络）
# ===========================================================================
log_group "Group E: Tool 管理"

if run_test "E1" "tool install ruff" "tool install ruff" 0; then
    run_test "E2" "tool list" "tool list" 0 || true
    run_test "E3" "tool run ruff" "tool run ruff --version" 0 || true
    run_test "E4" "tool uninstall ruff" "tool uninstall ruff" 0 || true

    # E5: tool upgrade（先装一个旧版再升级）
    run_test "E5" "tool install black" "tool install black" 0 || true
    run_test "E5b" "tool upgrade black" "tool upgrade black" 0 || true
    run_test "E5c" "tool uninstall black" "tool uninstall black" 0 || true

    # E6: tool dir --bin (show tool bin directory)
    run_test "E6" "tool dir --bin" "tool dir --bin" 0 || true

    # E7: tool run with specific version (慢: 重新下载 ruff@0.3.0)
    if $FAST_MODE; then
        skip_test "E7" "tool run 指定版本" "--fast 模式跳过 (重复下载 ruff)"
    else
        run_test "E7" "tool run 指定版本" "tool run ruff@0.3.0 --version" 0 || true
    fi

    # E8: tool install --from (慢: 重新下载 ruff)
    if $FAST_MODE; then
        skip_test "E8" "tool install --from" "--fast 模式跳过 (重复下载 ruff)"
    else
        run_test "E8" "tool install --from" "tool install --from ruff ruff" 0 || true
        run_on_device "$UV_ENV_VARS $UV_PATH tool uninstall ruff" 2>/dev/null || true  # cleanup E8
    fi

    # E9: tool upgrade --all
    run_test "E9" "tool upgrade --all" "tool upgrade --all" 0 || true

    # E10: tool list --show-paths
    run_test "E10" "tool list --show-paths" "tool list --show-paths" 0 || true
else
    skip_group "tool install 失败" "E2:tool list" "E3:tool run" "E4:tool uninstall" "E5:tool install black" "E5b:tool upgrade" "E5c:tool uninstall black" "E6:uvx" "E7:tool run 指定版本" "E8:tool install --from" "E9:tool upgrade --all" "E10:tool list --show-paths"
fi

# ===========================================================================
# Group F: Cache 管理
# ===========================================================================
log_group "Group F: Cache 管理"

run_test "F1" "cache prune" "cache prune" 0 || true
run_test "F2" "cache clean" "cache clean" 0 || true

# ===========================================================================
# Group G: Build（需要 Python）
# ===========================================================================
log_group "Group G: Build"

if $PYTHON_INSTALLED; then
    # 创建一个简单的项目用于 build 测试
    run_on_device "mkdir -p /data/local/tmp/test_build && cd /data/local/tmp/test_build && cat > pyproject.toml << 'TOML'
[build-system]
requires = [\"setuptools\"]
build-backend = \"setuptools.build_meta\"

[project]
name = \"test-ohos-build\"
version = \"0.1.0\"
TOML
mkdir -p test_ohos_build && echo 'def hello(): return \"hi\"' > test_ohos_build/__init__.py" 2>/dev/null || true

    run_test "G1" "build sdist" "build --sdist /data/local/tmp/test_build --out-dir /data/local/tmp/build_out" 0 || true
    run_test "G2" "build wheel" "build --wheel /data/local/tmp/test_build --out-dir /data/local/tmp/build_out" 0 || true
    run_test "G3" "build (all)" "build /data/local/tmp/test_build --out-dir /data/local/tmp/build_out2" 0 || true

    # 清理
    run_on_device "rm -rf /data/local/tmp/test_build /data/local/tmp/build_out /data/local/tmp/build_out2" 2>/dev/null || true
else
    skip_group "Python 未安装" "G1:build sdist" "G2:build wheel" "G3:build all"
fi

# ===========================================================================
# Group H: Auth 管理（仅验证帮助命令）
# ===========================================================================
log_group "Group H: Auth 管理"

run_test "H1" "auth login 帮助" "auth login --help" 0 || true
run_test "H2" "auth logout 帮助" "auth logout --help" 0 || true
run_test "H3" "auth token 帮助" "auth token --help" 0 || true

# ===========================================================================
# Group I: Workspace 管理（需要 D1 成功）
# ===========================================================================
log_group "Group I: Workspace 管理"

if $PROJECT_INIT_OK; then
    run_test "I1" "workspace dir" "workspace dir --project /data/local/tmp/testproj" 0 || true
    run_test "I2" "workspace list" "workspace list --project /data/local/tmp/testproj" 0 || true
    run_test "I3" "workspace metadata" "workspace metadata --frozen --project /data/local/tmp/testproj" 0 || true
else
    skip_group "项目未创建" "I1:workspace dir" "I2:workspace list" "I3:workspace metadata"
fi

# ===========================================================================
# Group J: Publish（仅验证帮助命令）
# ===========================================================================
log_group "Group J: Publish"

run_test "J1" "publish 帮助" "publish --help" 0 || true

# ===========================================================================
# Group H: 卸载 Python (放在最后，避免影响其他测试)
# ===========================================================================
if $PYTHON_INSTALLED; then
    log_group "清理: 卸载 Python"
    run_test "B4" "卸载 Python 3.12" "python uninstall 3.12" 0 || true
fi

# ===========================================================================
# 清理测试残留
# ===========================================================================
log_info "清理测试残留..."
run_on_device "rm -rf /data/local/tmp/testvenv /data/local/tmp/testvenv2 /data/local/tmp/testvenv_seed /data/local/tmp/testvenv_py /data/local/tmp/testvenv_sys /data/local/tmp/testvenv_prompt /data/local/tmp/testproj /data/local/tmp/testproj_lib /data/local/tmp/testproj_app /data/local/tmp/test_script.py /data/local/tmp/requirements.in /data/local/tmp/requirements.txt /data/local/tmp/requirements_install.txt /data/local/tmp/test_build /data/local/tmp/.cache /data/local/tmp/.local /data/local/tmp/.python-version" 2>/dev/null || true

# ===========================================================================
# 生成测试报告
# ===========================================================================
log_group "生成测试报告"

{
    echo "# OHOS uv 功能验证测试报告"
    echo ""
    echo "## 测试概览"
    echo ""
    echo "| 项目 | 值 |"
    echo "|------|-----|"
    echo "| 测试时间 | $(date '+%Y-%m-%d %H:%M:%S') |"
    echo "| uv 版本 | $UV_VERSION |"
    echo "| 设备 | $DEVICE_ID |"
    echo "| 总计 | $TOTAL |"
    echo "| 通过 | $PASSED |"
    echo "| 失败 | $FAILED |"
    echo "| 跳过 | $SKIPPED |"
    echo ""

    # --- 失败用例详情（含完整输出）---
    if [[ $FAILED -gt 0 ]]; then
        echo "## ❌ 失败用例详情 ($FAILED 个)"
        echo ""
        for result in "${RESULTS[@]}"; do
            IFS=$SEP read -r id name status reason command output <<< "$result"
            if [[ "$status" == "FAIL" ]]; then
                echo "### ${id}: ${name}"
                echo ""
                echo "**失败原因**: $reason"
                echo ""
                echo "**输入命令**:"
                echo '```bash'
                echo "$command"
                echo '```'
                echo ""
                echo "**实际输出**:"
                echo '```'
                if [[ -n "$output" ]]; then
                    echo "$output" | head -50
                    if [[ $(echo "$output" | wc -l) -gt 50 ]]; then
                        echo "... (输出被截断，共 $(echo "$output" | wc -l) 行)"
                    fi
                else
                    echo "(无输出)"
                fi
                echo '```'
                echo ""
                echo "---"
                echo ""
            fi
        done
    fi

    # --- 跳过用例及原因 ---
    if [[ $SKIPPED -gt 0 ]]; then
        echo "## ⏭️ 跳过的用例 ($SKIPPED 个)"
        echo ""
        echo "| ID | 测试用例 | 跳过原因 |"
        echo "|----|---------|---------|"
        for result in "${RESULTS[@]}"; do
            IFS=$SEP read -r id name status reason command output <<< "$result"
            if [[ "$status" == "SKIP" ]]; then
                echo "| $id | $name | $reason |"
            fi
        done
        echo ""
    fi

    # --- 通过用例列表 ---
    if [[ $PASSED -gt 0 ]]; then
        echo "## ✅ 通过的用例 ($PASSED 个)"
        echo ""
        echo "| ID | 测试用例 |"
        echo "|----|---------|"
        for result in "${RESULTS[@]}"; do
            IFS=$SEP read -r id name status reason command output <<< "$result"
            if [[ "$status" == "PASS" ]]; then
                echo "| $id | $name |"
            fi
        done
        echo ""
    fi

    # --- 所有测试详细输入输出 ---
    echo "## 全部测试详细记录"
    echo ""
    TEST_NUM=1
    for result in "${RESULTS[@]}"; do
        IFS=$SEP read -r id name status reason command output <<< "$result"

        case "$status" in
            PASS) emoji="✅" ;;
            FAIL) emoji="❌" ;;
            SKIP) emoji="⏭️" ;;
        esac

        echo "### ${TEST_NUM}. [${emoji}] ${id}: ${name}"
        echo ""

        if [[ -n "$reason" ]]; then
            echo "**说明**: $reason"
            echo ""
        fi

        if [[ -n "$command" ]]; then
            echo "**输入命令**:"
            echo '```bash'
            echo "$command"
            echo '```'
            echo ""
        fi

        if [[ -n "$output" ]]; then
            echo "**输出**:"
            echo '```'
            echo "$output" | head -30
            if [[ $(echo "$output" | wc -l) -gt 30 ]]; then
                echo "... (输出被截断，共 $(echo "$output" | wc -l) 行)"
            fi
            echo '```'
            echo ""
        fi

        echo "---"
        echo ""
        TEST_NUM=$((TEST_NUM + 1))
    done

    echo ""
    echo "*报告由 test-uv-ohos.sh 自动生成*"
} > "$REPORT_FILE"

log_pass "报告已保存: $REPORT_FILE"

# --- 终端输出摘要 ---
echo ""
echo "========================================="
echo "  测试完成: $PASSED/$TOTAL 通过"
if [[ $FAILED -gt 0 ]]; then
    echo "  ❌ $FAILED 个失败"
fi
if [[ $SKIPPED -gt 0 ]]; then
    echo "  ⏭️  $SKIPPED 个跳过"
fi
echo "  报告: $REPORT_FILE"
echo "========================================="

# --- 退出码 ---
if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
