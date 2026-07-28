#!/bin/bash
# =============================================================================
# OHOS uv 功能验证测试脚本
# 在 uv 命令执行成功后，通过功能验证命令确认功能真正可用
# 独立脚本，自行完成环境准备，可在原测试脚本之后或独立运行
#
# 三种测试结果：
#   ✅ PASS     — 命令成功 + 功能验证通过
#   ⚠️  PARTIAL  — 命令成功 + 功能验证失败（功能可能损坏）
#   ❌ FAIL     — 命令本身失败
#   ⏭️  SKIP     — 前置条件不满足
#
# 用法: bash verify-uv-ohos.sh [--uv-path PATH] [--hdc PATH] [--timeout SECS]
# =============================================================================

set -uo pipefail

# 禁止 MSYS2 路径自动转换（Git Bash 兼容）
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

# --- 配置 ---
UV_PATH="/data/local/tmp/uv"
HDC="hdc"
TIMEOUT=120
REPORT_FILE="ohos-uv-verify-report-$(date +%Y%m%d_%H%M%S).md"

# uv 环境变量（国内镜像加速）
UV_ENV_VARS="UV_INDEX_URL=https://pypi.mirrors.ustc.edu.cn/simple/ UV_PYTHON_INSTALL_MIRROR=https://ghfast.top/https://github.com/indygreg/python-build-standalone/releases/download"

# 设备路径常量
DEVICE_HOME="/data/local/tmp"
VENV_DIR="/data/local/tmp/testvenv"
VENV_SEED_DIR="/data/local/tmp/testvenv_seed"
VENV_PY_DIR="/data/local/tmp/testvenv_py"
VENV_SYS_DIR="/data/local/tmp/testvenv_sys"
PROJECT_DIR="/data/local/tmp/testproj"
PROJECT_LIB_DIR="/data/local/tmp/testproj_lib"
PROJECT_APP_DIR="/data/local/tmp/testproj_app"
SCRIPT_FILE="/data/local/tmp/test_script.py"
BUILD_PROJECT="/data/local/tmp/test_build"

# --- 参数解析 ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --uv-path) UV_PATH="$2"; shift 2 ;;
        --hdc)     HDC="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --help)
            echo "用法: bash verify-uv-ohos.sh [--uv-path PATH] [--hdc PATH] [--timeout SECS]"
            echo "  --uv-path PATH   设备上 uv 的路径 (默认: /data/local/tmp/uv)"
            echo "  --hdc PATH       hdc 可执行文件路径 (默认: hdc)"
            echo "  --timeout SECS   每个测试的超时秒数 (默认: 120)"
            exit 0
            ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

# --- 分隔符 ---
SEP=$'\x1f'

# --- 统计 ---
TOTAL=0
PASSED=0
PARTIAL=0
FAILED=0
SKIPPED=0

# --- 结果数组 ---
RESULTS=()

# --- 日志函数 ---
log_info()    { echo -e "\033[34m[INFO]\033[0m    $*"; }
log_pass()    { echo -e "\033[32m[PASS]\033[0m    $*"; }
log_partial() { echo -e "\033[33m[PARTIAL]\033[0m $*"; }
log_fail()    { echo -e "\033[31m[FAIL]\033[0m    $*"; }
log_skip()    { echo -e "\033[90m[SKIP]\033[0m    $*"; }
log_group()   { echo -e "\n\033[1;36m=== $* ===\033[0m"; }

# ===========================================================================
# 核心函数
# ===========================================================================

# 在设备上执行命令（带超时，不捕获退出码）
run_on_device() {
    timeout "$TIMEOUT" "$HDC" shell "$@" 2>&1 || true
}

# 在设备上执行 uv 命令并获取真实退出码
# 设置全局变量: OUTPUT, DEVICE_EXIT_CODE
DEVICE_EXIT_CODE=0
OUTPUT=""
run_uv_with_exit() {
    local args="$*"
    local full_cmd="$UV_ENV_VARS $UV_PATH $args; echo __EXIT_CODE__=\$?"
    local raw_output
    raw_output=$(timeout "$TIMEOUT" "$HDC" shell "$full_cmd" 2>&1) || true

    # 提取退出码
    DEVICE_EXIT_CODE=$(echo "$raw_output" | grep "__EXIT_CODE__=" | tail -1 | sed 's/.*__EXIT_CODE__=//' | tr -d '[:space:]')
    OUTPUT=$(echo "$raw_output" | grep -v "^__EXIT_CODE__=" | sed '/^$/d')

    if [[ -z "$DEVICE_EXIT_CODE" ]]; then
        DEVICE_EXIT_CODE=0
    fi
}

# 在设备上执行验证命令（不需要退出码标记，只需输出）
# 设置全局变量: VERIFY_OUTPUT
VERIFY_OUTPUT=""
run_verify_cmd() {
    local cmd="$1"
    local raw_output
    raw_output=$(timeout "$TIMEOUT" "$HDC" shell "$cmd" 2>&1) || true
    VERIFY_OUTPUT=$(echo "$raw_output" | sed '/^$/d' | tr -d '\r')
}

# 核心测试函数：执行主命令 + 功能验证
# run_verify ID NAME MAIN_CMD EXPECTED_OUTPUT VERIFY_CMD VERIFY_EXPECT
#
# EXPECTED_OUTPUT:
#   空字符串  → 仅检查主命令退出码为 0
#   非空     → 额外检查主命令输出包含该字符串
#
# VERIFY_CMD:
#   空字符串  → 不执行功能验证，主命令通过即 PASS
#
# VERIFY_EXPECT:
#   "0"       → 验证命令退出码应为 0（正向验证）
#   "non-zero"→ 验证命令退出码应非 0（反向验证，如卸载后 import 失败）
#   其他字符串 → 验证命令退出码应为 0 且输出包含该字符串
run_verify() {
    local id="$1"
    local name="$2"
    local cmd="$3"
    local expect="${4:-}"
    local verify_cmd="${5:-}"
    local verify_expect="${6:-0}"

    TOTAL=$((TOTAL + 1))
    log_info "[$id] $name"
    log_info "    命令: $UV_PATH $cmd"

    local start_time
    start_time=$(date +%s)

    # 步骤1: 执行主命令
    run_uv_with_exit "$cmd"
    # 将换行替换为空格，防止 IFS read 解析 RESULTS 时断行
    local main_output="${OUTPUT//$'\n'/ }"
    local main_exit="$DEVICE_EXIT_CODE"

    # 步骤2: 检查主命令退出码
    if [[ "$main_exit" != "0" ]]; then
        local end_time elapsed
        end_time=$(date +%s)
        elapsed=$((end_time - start_time))
        FAILED=$((FAILED + 1))
        log_fail "[$id] 主命令失败 (exit=$main_exit) (${elapsed}s)"
        RESULTS+=("$id${SEP}$name${SEP}FAIL${SEP}主命令失败 (exit=$main_exit)${SEP}$UV_PATH $cmd${SEP}$main_output${SEP}${SEP}${SEP}")
        return 1
    fi

    # 步骤3: 检查主命令输出（如有期望值）
    if [[ -n "$expect" ]]; then
        if ! echo "$main_output" | grep -qi "$expect"; then
            local end_time elapsed
            end_time=$(date +%s)
            elapsed=$((end_time - start_time))
            FAILED=$((FAILED + 1))
            log_fail "[$id] 输出不包含 '$expect' (${elapsed}s)"
            RESULTS+=("$id${SEP}$name${SEP}FAIL${SEP}输出不包含 '$expect'${SEP}$UV_PATH $cmd${SEP}$main_output${SEP}${SEP}${SEP}")
            return 1
        fi
    fi

    # 步骤4: 执行功能验证（如有验证命令）
    if [[ -n "$verify_cmd" ]]; then
        log_info "    验证: $verify_cmd"
        run_verify_cmd "$verify_cmd"
        local v_output="${VERIFY_OUTPUT//$'\n'/ }"

        # 获取验证命令退出码（从最后一行 __EXIT_CODE__ 标记提取）
        # run_verify_cmd 不自动提取退出码，需要另一种方式
        # 重新执行，带退出码标记（使用唯一标记 __VX__ 避免与命令输出冲突）
        local verify_with_exit="$verify_cmd; echo __VX__=\$?"
        local verify_raw
        verify_raw=$(timeout "$TIMEOUT" "$HDC" shell "$verify_with_exit" 2>&1) || true
        local v_exit
        v_exit=$(echo "$verify_raw" | grep "^__VX__=" | tail -1 | sed 's/^__VX__=//' | tr -d '[:space:]')
        v_output=$(echo "$verify_raw" | grep -v "^__VX__=" | sed '/^[[:space:]]*$/d' | tr -d '\r' | tr '\n' ' ')

        if [[ -z "$v_exit" ]]; then
            v_exit=1
        fi

        local verify_ok=false

        if [[ "$verify_expect" == "0" ]]; then
            # 正向验证：退出码应为 0
            [[ "$v_exit" == "0" ]] && verify_ok=true
        elif [[ "$verify_expect" == "non-zero" ]]; then
            # 反向验证：退出码应非 0
            [[ "$v_exit" != "0" ]] && verify_ok=true
        else
            # 输出匹配验证：退出码为 0 且输出包含期望字符串
            if [[ "$v_exit" == "0" ]] && echo "$v_output" | grep -qi "$verify_expect"; then
                verify_ok=true
            fi
        fi

        local end_time elapsed
        end_time=$(date +%s)
        elapsed=$((end_time - start_time))

        if $verify_ok; then
            PASSED=$((PASSED + 1))
            log_pass "[$id] $name (${elapsed}s)"
            RESULTS+=("$id${SEP}$name${SEP}PASS${SEP}${SEP}$UV_PATH $cmd${SEP}$main_output${SEP}$verify_cmd${SEP}$v_output${SEP}")
            return 0
        else
            PARTIAL=$((PARTIAL + 1))
            log_partial "[$id] 命令成功但功能验证失败 (v_exit=$v_exit) (${elapsed}s)"
            RESULTS+=("$id${SEP}$name${SEP}PARTIAL${SEP}功能验证失败 (v_exit=$v_exit)${SEP}$UV_PATH $cmd${SEP}$main_output${SEP}$verify_cmd${SEP}$v_output${SEP}")
            return 2
        fi
    fi

    # 无验证命令 → 主命令通过即 PASS
    local end_time elapsed
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    PASSED=$((PASSED + 1))
    log_pass "[$id] $name (${elapsed}s)"
    RESULTS+=("$id${SEP}$name${SEP}PASS${SEP}${SEP}$UV_PATH $cmd${SEP}$main_output${SEP}${SEP}${SEP}")
    return 0
}

# 跳过测试
skip_verify() {
    local id="$1"
    local name="$2"
    local reason="$3"

    TOTAL=$((TOTAL + 1))
    SKIPPED=$((SKIPPED + 1))
    log_skip "[$id] $name — $reason"
    RESULTS+=("$id${SEP}$name${SEP}SKIP${SEP}$reason${SEP}${SEP}${SEP}${SEP}${SEP}")
}

# ===========================================================================
# 前置检查
# ===========================================================================
log_group "前置检查"

log_info "检查 hdc 连接..."
DEVICE_ID=$("$HDC" list targets 2>&1 | head -1 | tr -d '[:space:]')
if [[ -z "$DEVICE_ID" ]]; then
    echo "错误: 未检测到 OHOS 设备连接"
    exit 1
fi
log_pass "设备已连接: $DEVICE_ID"

log_info "检查 uv 二进制..."
UV_VERSION=$(run_uv_with_exit "--version" && echo "$OUTPUT" | head -1) || true
if [[ -z "$UV_VERSION" ]]; then
    echo "错误: 无法在设备上执行 uv"
    exit 1
fi
log_pass "uv 版本: $UV_VERSION"

# --- 清理上次测试残留 ---
log_info "清理上次测试残留..."
run_on_device "rm -rf $VENV_DIR $VENV_SEED_DIR $VENV_PY_DIR $VENV_SYS_DIR $PROJECT_DIR $PROJECT_LIB_DIR $PROJECT_APP_DIR $SCRIPT_FILE $BUILD_PROJECT /data/local/tmp/build_out /data/local/tmp/build_out2 /data/local/tmp/requirements.in /data/local/tmp/requirements.txt /data/local/tmp/requirements_install.txt /data/local/tmp/.python-version" 2>/dev/null || true

# ===========================================================================
# 状态标记
# ===========================================================================
PYTHON_INSTALLED=false
PYTHON_BIN=""
C_VENV_OK=false
PROJECT_OK=false

# ===========================================================================
# Group B: Python 管理（5 个验证用例）
# ===========================================================================
log_group "Group B: Python 管理 — 环境准备 + 功能验证"

# --- B 组环境准备: 安装 Python 3.12 ---
log_info "安装 Python 3.12..."
run_verify "B2" "安装 Python 3.12" \
    "python install 3.12" "" \
    "$UV_PATH python find 3.12" "3.12" || true

# 获取 Python 路径
if [[ "$DEVICE_EXIT_CODE" == "0" ]] || true; then
    PYTHON_BIN=$(run_on_device "$UV_ENV_VARS $UV_PATH python find 3.12" | tr -d '\r' | head -1)
    if [[ -n "$PYTHON_BIN" ]] && [[ "$PYTHON_BIN" == *"python"* ]]; then
        PYTHON_INSTALLED=true
        log_pass "Python 路径: $PYTHON_BIN"
    else
        log_fail "无法获取 Python 3.12 路径 (got: '$PYTHON_BIN')"
    fi
fi

if $PYTHON_INSTALLED; then
    # B2 验证: Python 可以执行并输出版本
    run_verify "B2v" "验证 Python 3.12 可执行" \
        "python find 3.12" "" \
        "$PYTHON_BIN -c \"import sys; print(sys.version)\"" "3.12" || true

    # B3: python find — 验证找到的路径真正可执行
    run_verify "B3" "查找 Python" \
        "python find" "" \
        "$PYTHON_BIN -c \"print('hello')\"" "hello" || true

    # B5: python pin — 验证 .python-version 文件内容
    run_verify "B5" "Python pin" \
        "python pin 3.12 --project $DEVICE_HOME" "" \
        "cat $DEVICE_HOME/.python-version" "3.12" || true

    # B9: python reinstall — 验证重装后仍可执行
    run_verify "B9" "Python 重装" \
        "python install --reinstall 3.12" "" \
        "$PYTHON_BIN -c \"import sys; print(sys.version)\"" "3.12" || true

    # B4: python uninstall — 验证卸载后不可执行（最后执行）
    # 延迟到最终清理时执行
else
    skip_verify "B2v" "验证 Python 3.12" "Python 安装失败"
    skip_verify "B3" "查找 Python" "Python 安装失败"
    skip_verify "B5" "Python pin" "Python 安装失败"
    skip_verify "B9" "Python 重装" "Python 安装失败"
fi

# ===========================================================================
# Group C: 虚拟环境 + pip（16 个验证用例）
# ===========================================================================
log_group "Group C: 虚拟环境 + pip — 环境准备 + 功能验证"

VP="$VENV_DIR/bin/python"

if $PYTHON_INSTALLED; then
    # --- C 组环境准备 ---
    log_info "创建测试虚拟环境..."

    # C1: 创建 venv + 验证 Python 可执行且前缀正确
    run_verify "C1" "创建虚拟环境" \
        "venv $VENV_DIR" "" \
        "$VP -c \"import sys; print(sys.prefix)\"" "testvenv" || true

    if [[ "$DEVICE_EXIT_CODE" == "0" ]]; then
        C_VENV_OK=true
    fi

    if $C_VENV_OK; then
        # C10: venv --seed — 验证 pip 存在于 seed venv
        run_verify "C10" "venv --seed" \
            "venv --seed $VENV_SEED_DIR" "" \
            "$VENV_SEED_DIR/bin/pip --version" "0" || true

        # C11: 验证 seed venv 中 pip 可 import
        run_verify "C11" "验证 seed pip" \
            "pip list --python $VENV_SEED_DIR/bin/python" "" \
            "$VENV_SEED_DIR/bin/python -c \"import pip; print(pip.__version__)\"" "0" || true

        # C12: venv --python 3.12 — 验证 Python 版本正确
        run_verify "C12" "venv --python 3.12" \
            "venv --python 3.12 $VENV_PY_DIR" "" \
            "$VENV_PY_DIR/bin/python -c \"import sys; print(sys.version)\"" "3.12" || true

        # C13: venv --clear — 验证清理后 venv 仍可正常工作
        run_verify "C13" "venv --clear" \
            "venv --clear $VENV_DIR" "" \
            "$VP -c \"import sys; print(sys.prefix)\"" "testvenv" || true

        # C14: venv --allow-existing — 验证已存在时不报错且可用
        run_verify "C14" "venv --allow-existing" \
            "venv --allow-existing $VENV_DIR" "" \
            "$VP -c \"print('ok')\"" "ok" || true

        # C15: venv --no-project — 验证 venv 可正常使用
        run_verify "C15" "venv --no-project" \
            "venv --no-project /data/local/tmp/testvenv2" "" \
            "/data/local/tmp/testvenv2/bin/python -c \"print('ok')\"" "ok" || true

        # C16: venv --system-site-packages — 验证 venv 可用
        run_verify "C16" "venv --system-site-packages" \
            "venv --system-site-packages $VENV_SYS_DIR" "" \
            "$VENV_SYS_DIR/bin/python -c \"import sys; print(sys.prefix)\"" "testvenv_sys" || true

        # C17: venv --prompt — 验证 venv 可用（prompt 名称无法直接验证）
        run_verify "C17" "venv --prompt" \
            "venv --prompt myenv /data/local/tmp/testvenv_prompt" "" \
            "/data/local/tmp/testvenv_prompt/bin/python -c \"print('ok')\"" "ok" || true

        # --- 准备 editable 测试用的 lib 项目 ---
        log_info "创建 testproj_lib (editable 测试用)..."
        run_on_device "mkdir -p $PROJECT_LIB_DIR/src/test_ohos_lib && cat > $PROJECT_LIB_DIR/pyproject.toml << 'TOML'
[build-system]
requires = [\"hatchling\"]
build-backend = \"hatchling.build\"

[project]
name = \"test-ohos-lib\"
version = \"0.1.0\"
TOML
echo 'def hello(): return \"hi\"' > $PROJECT_LIB_DIR/src/test_ohos_lib/__init__.py" 2>/dev/null || true

        # ===================================================================
        # pip 操作验证
        # ===================================================================
        log_group "Group C: pip 操作 — 功能验证"

        # C2: pip install requests — 验证包可以 import
        run_verify "C2" "pip install requests" \
            "pip install requests --python $VP" "" \
            "$VP -c \"import requests; print(requests.__version__)\"" "[0-9]" || true

        # C3: pip list — 验证 list 中的包确实可 import
        run_verify "C3" "pip list" \
            "pip list --python $VP" "requests" \
            "$VP -c \"import requests\"" "0" || true

        # C2b: pip install urllib3（为后续卸载测试准备）
        run_verify "C2b" "pip install urllib3" \
            "pip install urllib3 --python $VP" "" \
            "$VP -c \"import urllib3; print(urllib3.__version__)\"" "[0-9]" || true

        # C8: pip uninstall urllib3 — 验证卸载后 import 失败
        run_verify "C8" "pip uninstall urllib3" \
            "pip uninstall urllib3 --python $VP" "" \
            "if $VP -c \"import urllib3\" 2>/dev/null; then false; else echo OK; fi" "OK" || true

        # C8b: pip uninstall requests — 验证卸载后 import 失败
        run_verify "C8b" "pip uninstall requests" \
            "pip uninstall requests --python $VP" "" \
            "if $VP -c \"import requests\" 2>/dev/null; then false; else echo OK; fi" "OK" || true

        # C9 + C9b: pip compile + pip sync — 验证 sync 后包可用
        run_on_device "echo 'requests' > /data/local/tmp/requirements.in" 2>/dev/null || true
        run_verify "C9" "pip compile" \
            "pip compile /data/local/tmp/requirements.in -o /data/local/tmp/requirements.txt" "" \
            "cat /data/local/tmp/requirements.txt" "requests" || true

        run_verify "C9b" "pip sync" \
            "pip sync /data/local/tmp/requirements.txt --python $VP" "" \
            "$VP -c \"import requests; print(requests.__version__)\"" "[0-9]" || true

        # C18: pip install -r — 验证从文件安装后包可 import
        run_on_device "echo 'chardet' > /data/local/tmp/requirements_install.txt" 2>/dev/null || true
        run_verify "C18" "pip install -r" \
            "pip install -r /data/local/tmp/requirements_install.txt --python $VP" "" \
            "$VP -c \"import chardet; print(chardet.__version__)\"" "[0-9]" || true

        # C19: pip install --upgrade — 验证升级后仍可 import
        run_verify "C19" "pip install --upgrade" \
            "pip install --upgrade requests --python $VP" "" \
            "$VP -c \"import requests; print(requests.__version__)\"" "[0-9]" || true

        # C20: pip install --no-deps — 验证包本身可 import
        run_verify "C20" "pip install --no-deps" \
            "pip install --no-deps idna --python $VP" "" \
            "$VP -c \"import idna; print(idna.__version__)\"" "[0-9]" || true

        # C21: pip install -e — 验证 editable 安装指向源码目录（核心验证！）
        run_verify "C21" "pip install -e (editable)" \
            "pip install -e $PROJECT_LIB_DIR --python $VP" "" \
            "$VP -c \"import test_ohos_lib; print(test_ohos_lib.__file__)\"" "testproj_lib" || true

        # C22: pip uninstall -r — 验证批量卸载后 import 失败
        run_verify "C22" "pip uninstall -r" \
            "pip uninstall -r /data/local/tmp/requirements_install.txt --python $VP" "" \
            "if $VP -c \"import chardet\" 2>/dev/null; then false; else echo OK; fi" "OK" || true

        # 清理 C 组 venv 产物
        run_on_device "rm -rf $VENV_SEED_DIR $VENV_PY_DIR $VENV_SYS_DIR /data/local/tmp/testvenv2 /data/local/tmp/testvenv_prompt /data/local/tmp/requirements.in /data/local/tmp/requirements.txt /data/local/tmp/requirements_install.txt" 2>/dev/null || true

    else
        # C_VENV_OK=false → 跳过所有 pip 测试
        for tid in C10 C11 C12 C13 C14 C15 C16 C17 C2 C3 C2b C8 C8b C9 C9b C18 C19 C20 C21 C22; do
            skip_verify "$tid" "pip/venv 测试" "venv 创建失败"
        done
    fi
else
    C_TESTS="C1 C10 C11 C12 C13 C14 C15 C16 C17 C2 C3 C2b C8 C8b C9 C9b C18 C19 C20 C21 C22"
    for tid in $C_TESTS; do
        skip_verify "$tid" "pip/venv 测试" "Python 未安装"
    done
fi

# ===========================================================================
# Group D: 项目管理（14 个验证用例）
# ===========================================================================
log_group "Group D: 项目管理 — 环境准备 + 功能验证"

if $PYTHON_INSTALLED; then
    # D1: init — 验证 pyproject.toml 文件存在
    run_verify "D1" "init 项目" \
        "init $PROJECT_DIR" "" \
        "ls $PROJECT_DIR/pyproject.toml" "0" || true

    if [[ "$DEVICE_EXIT_CODE" == "0" ]]; then
        PROJECT_OK=true
    fi

    if $PROJECT_OK; then
        # D2: lock — 验证 uv.lock 文件存在
        run_verify "D2" "lock" \
            "lock --project $PROJECT_DIR" "" \
            "ls $PROJECT_DIR/uv.lock" "0" || true

        # D4: add requests — 验证依赖写入 pyproject.toml
        run_verify "D4" "add requests" \
            "add requests --project $PROJECT_DIR" "" \
            "grep 'requests' $PROJECT_DIR/pyproject.toml" "requests" || true

        # D6: remove requests — 验证依赖从 pyproject.toml 移除
        run_verify "D6" "remove requests" \
            "remove requests --project $PROJECT_DIR" "" \
            "if grep -q 'requests' $PROJECT_DIR/pyproject.toml; then false; else echo OK; fi" "OK" || true

        # D4b: add --dev pytest — 验证 dev 依赖写入
        run_verify "D4b" "add --dev pytest" \
            "add --dev pytest --project $PROJECT_DIR" "" \
            "grep 'pytest' $PROJECT_DIR/pyproject.toml" "pytest" || true

        # D6b: remove --dev pytest — 验证 dev 依赖移除
        run_verify "D6b" "remove --dev pytest" \
            "remove --dev pytest --project $PROJECT_DIR" "" \
            "if grep -q 'pytest' $PROJECT_DIR/pyproject.toml; then false; else echo OK; fi" "OK" || true

        # D5: tree — 先添加一个依赖再检查 tree 输出
        run_verify "D5" "tree" \
            "add requests --project $PROJECT_DIR" "" \
            "$UV_ENV_VARS $UV_PATH tree --project $PROJECT_DIR" "requests" || true

        # D5b: version — 验证输出版本号
        run_verify "D5b" "version" \
            "version --project $PROJECT_DIR" "" \
            "$UV_ENV_VARS $UV_PATH version --project $PROJECT_DIR" "0" || true

        # D7: run — 输出本身即验证
        run_verify "D7" "run" \
            "run --project $PROJECT_DIR python -c \"print('hello from ohos')\"" "hello from ohos" \
            "" "" || true

        # D7b: run --with — 输出本身即验证
        run_verify "D7b" "run --with" \
            "run --with requests --project $PROJECT_DIR python -c \"import requests; print(requests.__version__)\"" "[0-9]" \
            "" "" || true

        # D9: init --lib — 验证 lib 项目结构存在（先清理 C21 阶段创建的目录）
        run_on_device "rm -rf $PROJECT_LIB_DIR" 2>/dev/null || true
        run_verify "D9" "init --lib" \
            "init --lib $PROJECT_LIB_DIR" "" \
            "ls $PROJECT_LIB_DIR/pyproject.toml" "0" || true

        # D10: init --script — 验证 PEP 723 metadata 头部
        run_verify "D10" "init --script" \
            "init --script $SCRIPT_FILE" "" \
            "head -5 $SCRIPT_FILE" "script" || true

        # D11: add --script — 验证 metadata 中包含依赖
        run_verify "D11" "add --script" \
            "add --script $SCRIPT_FILE requests" "" \
            "grep 'requests' $SCRIPT_FILE" "requests" || true

        # D14: init --app — 验证 app 项目结构存在
        run_verify "D14" "init --app" \
            "init --app $PROJECT_APP_DIR" "" \
            "ls $PROJECT_APP_DIR/pyproject.toml" "0" || true

        # D15: add --optional flask — 验证可选依赖写入
        run_verify "D15" "add --optional" \
            "add --optional web flask --project $PROJECT_DIR" "" \
            "grep 'flask' $PROJECT_DIR/pyproject.toml" "flask" || true

        # D17: add --editable — 验证 editable 依赖写入
        run_verify "D17" "add --editable" \
            "add --editable $PROJECT_LIB_DIR --project $PROJECT_DIR" "" \
            "grep 'testproj-lib' $PROJECT_DIR/pyproject.toml" "testproj-lib" || true

        # 清理 D 组项目产物
        run_on_device "rm -rf $PROJECT_LIB_DIR $PROJECT_APP_DIR $SCRIPT_FILE" 2>/dev/null || true

    else
        D_TESTS="D2 D4 D6 D4b D6b D5 D5b D7 D7b D9 D10 D11 D14 D15 D17"
        for tid in $D_TESTS; do
            skip_verify "$tid" "项目管理测试" "init 失败"
        done
    fi
else
    D_TESTS="D1 D2 D4 D6 D4b D6b D5 D5b D7 D7b D9 D10 D11 D14 D15 D17"
    for tid in $D_TESTS; do
        skip_verify "$tid" "项目管理测试" "Python 未安装"
    done
fi

# ===========================================================================
# Group E: Tool 管理（5 个验证用例）
# ===========================================================================
log_group "Group E: Tool 管理 — 功能验证"

TOOL_BIN=""
run_verify_cmd "$UV_ENV_VARS $UV_PATH tool dir --bin"
TOOL_BIN=$(echo "$VERIFY_OUTPUT" | head -1 | tr -d '[:space:]')

# E1: tool install ruff — 验证 ruff 二进制可执行
run_verify "E1" "tool install ruff" \
    "tool install ruff" "" \
    "$TOOL_BIN/ruff --version" "0" || true

E1_OK=false
if [[ "$DEVICE_EXIT_CODE" == "0" ]]; then
    E1_OK=true
fi

if $E1_OK; then
    # E2: tool list — 验证列表中包含 ruff
    run_verify "E2" "tool list" \
        "tool list" "" \
        "$UV_ENV_VARS $UV_PATH tool list" "ruff" || true

    # E4: tool uninstall ruff — 验证列表中不再包含 ruff
    run_verify "E4" "tool uninstall ruff" \
        "tool uninstall ruff" "" \
        "if $UV_ENV_VARS $UV_PATH tool list | grep -qF ruff; then false; else echo OK; fi" "OK" || true

    # E5: tool install black — 验证 black 可执行
    run_verify "E5" "tool install black" \
        "tool install black" "" \
        "$TOOL_BIN/black --version" "0" || true

    # E5c: tool uninstall black — 验证列表中不再包含 black
    run_verify "E5c" "tool uninstall black" \
        "tool uninstall black" "" \
        "if $UV_ENV_VARS $UV_PATH tool list | grep -qF black; then false; else echo OK; fi" "OK" || true
else
    for tid in E2 E4 E5 E5c; do
        skip_verify "$tid" "Tool 测试" "tool install ruff 失败"
    done
fi

# ===========================================================================
# Group G: Build（3 个验证用例）
# ===========================================================================
log_group "Group G: Build — 环境准备 + 功能验证"

if $PYTHON_INSTALLED; then
    # G 组环境准备: 创建简单构建项目
    log_info "创建 build 测试项目..."
    run_on_device "mkdir -p $BUILD_PROJECT && cat > $BUILD_PROJECT/pyproject.toml << 'TOML'
[build-system]
requires = [\"setuptools\"]
build-backend = \"setuptools.build_meta\"

[project]
name = \"test-ohos-build\"
version = \"0.1.0\"
TOML
mkdir -p $BUILD_PROJECT/test_ohos_build && echo 'def hello(): return \"hi\"' > $BUILD_PROJECT/test_ohos_build/__init__.py" 2>/dev/null || true

    # G1: build --sdist — 验证 sdist 包含项目文件
    run_verify "G1" "build sdist" \
        "build --sdist $BUILD_PROJECT --out-dir /data/local/tmp/build_out" "" \
        "ls /data/local/tmp/build_out/*.tar.gz" "0" || true

    # G2: build --wheel — 验证 wheel 可安装且包可 import
    run_verify "G2" "build wheel" \
        "build --wheel $BUILD_PROJECT --out-dir /data/local/tmp/build_out" "" \
        "$UV_ENV_VARS $UV_PATH pip install /data/local/tmp/build_out/*.whl --python $VP && $VP -c \"import test_ohos_build; print('ok')\"" "ok" || true

    # G3: build (all) — 验证两种格式产物都存在
    run_verify "G3" "build (all)" \
        "build $BUILD_PROJECT --out-dir /data/local/tmp/build_out2" "" \
        "ls /data/local/tmp/build_out2/" "0" || true

    # 清理
    run_on_device "rm -rf $BUILD_PROJECT /data/local/tmp/build_out /data/local/tmp/build_out2" 2>/dev/null || true
else
    for tid in G1 G2 G3; do
        skip_verify "$tid" "Build 测试" "Python 未安装"
    done
fi

# ===========================================================================
# 最终清理
# ===========================================================================
log_group "最终清理"

# B4: 卸载 Python（同时作为验证用例）
if $PYTHON_INSTALLED; then
    run_verify "B4" "卸载 Python 3.12" \
        "python uninstall 3.12" "" \
        "if $PYTHON_BIN -c \"import sys\" 2>/dev/null; then false; else echo OK; fi" "OK" || true
fi

# 清理所有测试残留
log_info "清理所有测试残留..."
run_on_device "rm -rf $VENV_DIR $VENV_SEED_DIR $VENV_PY_DIR $VENV_SYS_DIR $PROJECT_DIR $PROJECT_LIB_DIR $PROJECT_APP_DIR $SCRIPT_FILE $BUILD_PROJECT /data/local/tmp/testvenv2 /data/local/tmp/testvenv_prompt /data/local/tmp/build_out /data/local/tmp/build_out2 /data/local/tmp/requirements.in /data/local/tmp/requirements.txt /data/local/tmp/requirements_install.txt /data/local/tmp/.python-version /data/local/tmp/.cache /data/local/tmp/.local" 2>/dev/null || true

# ===========================================================================
# 生成报告
# ===========================================================================
log_group "生成报告"

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
    echo "| ✅ 通过 | $PASSED |"
    echo "| ⚠️ 部分通过 | $PARTIAL |"
    echo "| ❌ 失败 | $FAILED |"
    echo "| ⏭️ 跳过 | $SKIPPED |"
    echo ""

    # --- PARTIAL 用例诊断详情 ---
    if [[ $PARTIAL -gt 0 ]]; then
        echo "## ⚠️ 部分通过的用例 ($PARTIAL 个)"
        echo ""
        echo "> 命令执行成功但功能验证失败，可能表示功能在 OHOS 上存在兼容性问题"
        echo ""
        for result in "${RESULTS[@]}"; do
            IFS=$SEP read -r id name status reason cmd main_out v_cmd v_out _ <<< "$result"
            if [[ "$status" == "PARTIAL" ]]; then
                echo "### ${id}: ${name}"
                echo ""
                echo "**主命令**:"
                echo '```bash'
                echo "$cmd"
                echo '```'
                echo ""
                echo "**主命令输出**:"
                echo '```'
                echo "${main_out:-"(无输出)"}" | head -20
                echo '```'
                echo ""
                echo "**验证命令**:"
                echo '```bash'
                echo "$v_cmd"
                echo '```'
                echo ""
                echo "**验证输出**:"
                echo '```'
                echo "${v_out:-"(无输出)"}" | head -20
                echo '```'
                echo ""
                echo "---"
                echo ""
            fi
        done
    fi

    # --- FAIL 用例详情 ---
    if [[ $FAILED -gt 0 ]]; then
        echo "## ❌ 失败的用例 ($FAILED 个)"
        echo ""
        for result in "${RESULTS[@]}"; do
            IFS=$SEP read -r id name status reason cmd main_out v_cmd v_out _ <<< "$result"
            if [[ "$status" == "FAIL" ]]; then
                echo "### ${id}: ${name}"
                echo ""
                echo "**失败原因**: $reason"
                echo ""
                echo "**输入命令**:"
                echo '```bash'
                echo "$cmd"
                echo '```'
                echo ""
                echo "**实际输出**:"
                echo '```'
                echo "${main_out:-"(无输出)"}" | head -30
                echo '```'
                echo ""
                echo "---"
                echo ""
            fi
        done
    fi

    # --- SKIP 用例列表 ---
    if [[ $SKIPPED -gt 0 ]]; then
        echo "## ⏭️ 跳过的用例 ($SKIPPED 个)"
        echo ""
        echo "| ID | 测试用例 | 跳过原因 |"
        echo "|----|---------|---------|"
        for result in "${RESULTS[@]}"; do
            IFS=$SEP read -r id name status reason _ _ _ _ _ <<< "$result"
            if [[ "$status" == "SKIP" ]]; then
                echo "| $id | $name | $reason |"
            fi
        done
        echo ""
    fi

    # --- 全部用例详细记录 ---
    echo "## 全部测试详细记录"
    echo ""
    TEST_NUM=1
    for result in "${RESULTS[@]}"; do
        IFS=$SEP read -r id name status reason cmd main_out v_cmd v_out _ <<< "$result"

        case "$status" in
            PASS)    emoji="✅" ;;
            PARTIAL) emoji="⚠️" ;;
            FAIL)    emoji="❌" ;;
            SKIP)    emoji="⏭️" ;;
        esac

        echo "### ${TEST_NUM}. [${emoji}] ${id}: ${name}"
        echo ""

        if [[ -n "$reason" ]]; then
            echo "**说明**: $reason"
            echo ""
        fi

        if [[ -n "$cmd" ]]; then
            echo "**主命令**:"
            echo '```bash'
            echo "$cmd"
            echo '```'
            echo ""
        fi

        if [[ -n "$main_out" ]]; then
            echo "**主命令输出**:"
            echo '```'
            echo "$main_out" | head -15
            echo '```'
            echo ""
        fi

        if [[ -n "$v_cmd" ]]; then
            echo "**验证命令**:"
            echo '```bash'
            echo "$v_cmd"
            echo '```'
            echo ""
        fi

        if [[ -n "$v_out" ]]; then
            echo "**验证输出**:"
            echo '```'
            echo "$v_out" | head -15
            echo '```'
            echo ""
        fi

        echo "---"
        echo ""
        TEST_NUM=$((TEST_NUM + 1))
    done

    echo ""
    echo "*报告由 verify-uv-ohos.sh 自动生成*"
} > "$REPORT_FILE"

log_pass "报告已保存: $REPORT_FILE"

# --- 终端摘要 ---
echo ""
echo "========================================="
echo "  功能验证测试完成"
echo "========================================="
echo "  ✅ 通过:     $PASSED"
echo "  ⚠️  部分通过: $PARTIAL"
echo "  ❌ 失败:     $FAILED"
echo "  ⏭️  跳过:     $SKIPPED"
echo "  总计:        $TOTAL"
echo "  报告:        $REPORT_FILE"
echo "========================================="

if [[ $PARTIAL -gt 0 ]]; then
    echo ""
    echo "⚠️  有 $PARTIAL 个用例命令成功但功能验证失败"
    echo "   请查看报告中的 PARTIAL 用例详情进行诊断"
fi

# --- 退出码 ---
if [[ $FAILED -gt 0 ]] || [[ $PARTIAL -gt 0 ]]; then
    exit 1
fi
