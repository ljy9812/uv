#!/bin/bash
#
# uv 功能验证测试脚本 - 107 个用例
# 用法: bash test_uv_ohos.sh [--fast] [--timeout 60] [--uv-path uv]
#

set -o pipefail

UV_PATH="uv"
TIMEOUT=60
FAST=false
export UV_INDEX_URL="https://pypi.mirrors.ustc.edu.cn/simple/"
export UV_PYTHON_INSTALL_MIRROR="https://ghfast.top/https://github.com/indygreg/python-build-standalone/releases/download"
TMP="$(pwd)/.uv-test-tmp"
mkdir -p "$TMP"

while [[ $# -gt 0 ]]; do
    case $1 in
        --uv-path) UV_PATH="$2"; shift 2;;
        --timeout) TIMEOUT="$2"; shift 2;;
        --fast) FAST=true; shift;;
        -h|--help) echo "用法: bash test_uv_ohos.sh [--fast] [--timeout N] [--uv-path PATH]"; exit 0;;
        *) echo "未知: $1"; exit 1;;
    esac
done

# ── 全局 ──
declare -a IDS NAMES STATUSES OUTPUTS DURS ERRORS
PASS=0 FAIL=0 SKIP=0 UV_VERSION=""
B2_OK=false C1_OK=false D1_OK=false E1_OK=false

# 执行 uv → _CODE, _OUT, _DUR
run_uv() {
    local s=$(date +%s.%N)
    _OUT=$(timeout "$TIMEOUT" $UV_PATH "$@" 2>&1)
    _CODE=$?
    _DUR=$(printf "%.1f" "$(echo "$(date +%s.%N) - $s" | bc 2>/dev/null || echo 0)")
}

record() {
    local id="$1" name="$2" status="$3" out="${4:-}" dur="${5:-0}" err="${6:-}"
    IDS+=("$id"); NAMES+=("$name"); STATUSES+=("$status"); OUTPUTS+=("$out"); DURS+=("$dur"); ERRORS+=("$err")
    case $status in
        PASS) ((PASS++)); printf "  ✅ [%-4s] %s (%ss)\n" "$id" "$name" "$dur";;
        FAIL) ((FAIL++)); printf "  ❌ [%-4s] %s (%ss)%s\n" "$id" "$name" "$dur" "${err:+ - $err}";;
        SKIP) ((SKIP++)); printf "  ⏭️  [%-4s] %s - %s\n" "$id" "$name" "$err";;
    esac
}

pass_or_fail() {
    local id="$1" name="$2"
    if [[ $_CODE -eq 0 ]]; then
        record "$id" "$name" "PASS" "$_OUT" "$_DUR"
    else
        record "$id" "$name" "FAIL" "$_OUT" "$_DUR" "退出码 $_CODE"
    fi
}

skip() { record "$1" "$2" "SKIP" "" "0" "$3"; }
skip_batch() { local r="$1"; shift; for id in "$@"; do skip "$id" "" "$r"; done; }

# ── Group A: 基础命令 (19) ──
group_a() {
    echo -e "\n═══ Group A: 基础命令 (19) ═══"

    run_uv --version
    if [[ $_CODE -eq 0 ]] && echo "$_OUT" | grep -qi "uv"; then
        record "A1" "版本号" "PASS" "$_OUT" "$_DUR"
        UV_VERSION=$(echo "$_OUT" | grep -oE "uv [0-9.]+" | awk '{print $2}')
    else
        record "A1" "版本号" "FAIL" "$_OUT" "$_DUR" "无版本号"
    fi

    run_uv --help; pass_or_fail "A2" "帮助信息"

    local i=0
    for sub in pip python tool cache venv build self workspace auth; do
        local ids=(A3a A3b A3c A3d A3e A3f A3g A3h A3i)
        run_uv $sub --help
        pass_or_fail "${ids[$i]}" "$sub 帮助" "uv $sub --help"
        ((i++))
    done

    for pair in "A4:cache dir" "A5:cache size" "A6:tool dir" "A7:python dir" "A9:auth dir" "A10:self version"; do
        local id="${pair%%:*}" cmd="${pair#*:}"
        run_uv $cmd
        pass_or_fail "$id" "$cmd" "uv $cmd"
    done

    run_uv pip debug
    if [[ $_CODE -eq 0 || $_CODE -eq 2 ]]; then
        record "A8" "pip debug" "PASS" "$_OUT" "$_DUR"
    else
        record "A8" "pip debug" "FAIL" "$_OUT" "$_DUR" "退出码 $_CODE"
    fi

    run_uv self update --dry-run
    [[ $_CODE -eq 0 ]] && record "A11" "self update --dry-run" "PASS" "$_OUT" "$_DUR" || record "A11" "self update --dry-run" "FAIL" "$_OUT" "$_DUR" "不支持自更新"
}

# ── Group B: Python 管理 (9) ──
group_b() {
    echo -e "\n═══ Group B: Python 管理 (9) ═══"

    run_uv python list; pass_or_fail "B1" "Python 列表" "uv python list"

    run_uv python list --only-installed
    if [[ $_CODE -eq 0 ]] && echo "$_OUT" | grep -q "3\.12"; then
        B2_OK=true
        record "B2" "检查 Python 3.12" "PASS" "$_OUT" "$_DUR" "已安装"
    else
        record "B2" "检查 Python 3.12" "FAIL" "$_OUT" "$_DUR" "未安装 Python 3.12"
    fi

    # B3: python find
    run_uv python find 3.12
    pass_or_fail "B3" "查找 Python"
    # B5: python pin (在可写目录中执行)
    local old_dir="$PWD"
    mkdir -p "$TMP/pin_test" && cd "$TMP/pin_test"
    run_uv python pin 3.12
    if [[ $_CODE -ne 0 ]]; then echo "    [DEBUG B5] exit=$_CODE output: $(echo "$_OUT" | head -3)"; fi
    cd "$old_dir"
    pass_or_fail "B5" "Python pin"

    run_uv python list --only-installed
    echo "$_OUT" | grep -q "3\.12" && record "B6" "仅列出已安装" "PASS" "$_OUT" "$_DUR" || record "B6" "仅列出已安装" "FAIL" "$_OUT" "$_DUR"

    run_uv python list --all-versions; pass_or_fail "B7" "Python 列表 --all-versions" "uv python list --all-versions"
    run_uv python list --only-installed --output-format json; pass_or_fail "B8" "Python 列表 JSON" "uv python list --output-format json"

    skip "B9" "Python 重装" "不再主动安装"
}

group_b_cleanup() {
    echo -e "\n═══ Group B (cleanup) ═══"
    skip "B4" "卸载 Python" "不再主动安装"
}

# ── Group C: 虚拟环境 + pip (27) ──
group_c() {
    echo -e "\n═══ Group C: 虚拟环境 + pip (27) ═══"
    if [[ "$B2_OK" != "true" ]]; then
        skip_batch "B2 失败" C1 C10 C11 C12 C13 C14 C15 C16 C17 C2 C3 C3b C4 C5 C6 C7 C2b C3c C8 C8b C9 C9b C18 C19 C20 C21 C22; return
    fi

    local venv="$TMP/testvenv" py="$TMP/testvenv/bin/python"

    run_uv venv --python 3.12 "$venv"
    if [[ $_CODE -eq 0 ]]; then
        C1_OK=true
        record "C1" "创建虚拟环境" "PASS" "$_OUT" "$_DUR"
    else
        echo "    [DEBUG venv] exit=$_CODE output: $(echo "$_OUT" | head -5)"
        record "C1" "创建虚拟环境" "FAIL" "$_OUT" "$_DUR"
    fi

    if [[ "$C1_OK" != "true" ]]; then
        skip_batch "C1 失败" C10 C11 C12 C13 C14 C15 C16 C17 C2 C3 C3b C4 C5 C6 C7 C2b C3c C8 C8b C9 C9b C18 C19 C20 C21 C22; return
    fi

    run_uv venv --python 3.12 --seed "$TMP/testvenv_seed"; pass_or_fail "C10" "venv --seed"
    run_uv pip list --python "$TMP/testvenv_seed/bin/python"
    echo "$_OUT" | grep -qi "pip" && record "C11" "验证 seed" "PASS" "$_OUT" "$_DUR" || record "C11" "验证 seed" "FAIL" "$_OUT" "$_DUR"

    run_uv venv --python 3.12 "$TMP/testvenv_py"; pass_or_fail "C12" "venv --python 3.12"
    run_uv venv --python 3.12 --clear "$venv"; pass_or_fail "C13" "venv --clear"
    run_uv venv --python 3.12 --allow-existing "$venv"; pass_or_fail "C14" "venv --allow-existing"
    run_uv venv --python 3.12 --no-project "$TMP/testvenv2"; pass_or_fail "C15" "venv --no-project"
    run_uv venv --python 3.12 --system-site-packages "$TMP/testvenv_sys"; pass_or_fail "C16" "venv --system-site-packages"
    run_uv venv --python 3.12 --prompt myenv "$TMP/testvenv_prompt"; pass_or_fail "C17" "venv --prompt"

    run_uv pip install requests --python "$py"; pass_or_fail "C2" "pip install requests"
    run_uv pip list --python "$py"
    echo "$_OUT" | grep -qi "requests" && record "C3" "pip list" "PASS" "$_OUT" "$_DUR" || record "C3" "pip list" "FAIL" "$_OUT" "$_DUR"
    run_uv pip list --python "$py" --format json; pass_or_fail "C3b" "pip list JSON"
    run_uv pip show requests --python "$py"; pass_or_fail "C4" "pip show requests"
    run_uv pip freeze --python "$py"; pass_or_fail "C5" "pip freeze"
    run_uv pip check --python "$py"; pass_or_fail "C6" "pip check"
    run_uv pip tree --python "$py"; pass_or_fail "C7" "pip tree"
    run_uv pip install urllib3 --python "$py"; pass_or_fail "C2b" "pip install urllib3"
    run_uv pip list --python "$py" --outdated; pass_or_fail "C3c" "pip list --outdated"
    run_uv pip uninstall urllib3 --python "$py"; pass_or_fail "C8" "pip uninstall urllib3"
    run_uv pip uninstall requests --python "$py"; pass_or_fail "C8b" "pip uninstall requests"

    echo "requests" > "$TMP/requirements.in"
    run_uv pip compile "$TMP/requirements.in" -o "$TMP/requirements.txt"; pass_or_fail "C9" "pip compile"
    run_uv pip sync "$TMP/requirements.txt" --python "$py"; pass_or_fail "C9b" "pip sync"
    run_uv pip install -r "$TMP/requirements.txt" --python "$py"; pass_or_fail "C18" "pip install -r"
    run_uv pip install --upgrade requests --python "$py"; pass_or_fail "C19" "pip install --upgrade"
    run_uv pip install --no-deps idna --python "$py"; pass_or_fail "C20" "pip install --no-deps"

    run_uv init --lib --python 3.12 "$TMP/testproj_lib" > /dev/null 2>&1
    run_uv pip install -e "$TMP/testproj_lib" --python "$py"; pass_or_fail "C21" "pip install -e"
    run_uv pip uninstall -r "$TMP/requirements.txt" --python "$py"; pass_or_fail "C22" "pip uninstall -r"
}

# ── Group D: 项目管理 (28) ──
group_d() {
    echo -e "\n═══ Group D: 项目管理 (28) ═══"
    if [[ "$B2_OK" != "true" ]]; then
        skip_batch "B2 失败" D1 D2 D3 D4 D5 D5b D4b D6b D6 D7 D8 D7b D2b D3b D9 D10 D11 D12 D13 D14 D15 D16 D17 D18 D19 D20 D21 D22; return
    fi
    local proj="$TMP/testproj" p="--project $TMP/testproj --python 3.12"

    run_uv init --python 3.12 "$proj"
    [[ $_CODE -eq 0 ]] && D1_OK=true && record "D1" "init 项目" "PASS" "$_OUT" "$_DUR" || record "D1" "init 项目" "FAIL" "$_OUT" "$_DUR"
    if [[ "$D1_OK" != "true" ]]; then
        skip_batch "D1 失败" D2 D3 D4 D5 D5b D4b D6b D6 D7 D8 D7b D2b D3b D9 D10 D11 D12 D13 D14 D15 D16 D17 D18 D19 D20 D21 D22; return
    fi

    # D2 lock 可能较慢，增加超时
    local old_timeout="$TIMEOUT"; TIMEOUT=180
    run_uv lock $p; pass_or_fail "D2" "lock"
    TIMEOUT="$old_timeout"
    run_uv sync $p; pass_or_fail "D3" "sync"
    run_uv add requests $p; pass_or_fail "D4" "add 依赖"
    run_uv tree $p; pass_or_fail "D5" "tree"
    run_uv version $p; pass_or_fail "D5b" "project version"
    run_uv add --dev pytest $p; pass_or_fail "D4b" "add --dev"
    run_uv remove --dev pytest $p; pass_or_fail "D6b" "remove --dev"
    run_uv remove requests $p; pass_or_fail "D6" "remove 依赖"

    run_uv run $p -- python -c "print('hello')"
    echo "$_OUT" | grep -q "hello" && record "D7" "run" "PASS" "$_OUT" "$_DUR" || record "D7" "run" "FAIL" "$_OUT" "$_DUR"

    run_uv export $p; pass_or_fail "D8" "export"
    run_uv run --python 3.12 --with requests -- python -c "import requests; print(requests.__version__)"
    pass_or_fail "D7b" "run --with"
    run_uv lock --upgrade $p; pass_or_fail "D2b" "lock --upgrade"
    run_uv sync --frozen $p; pass_or_fail "D3b" "sync --frozen"
    rm -rf "$TMP/testproj_lib"
    run_uv init --lib --python 3.12 "$TMP/testproj_lib"
    pass_or_fail "D9" "init --lib"
    run_uv init --script --python 3.12 "$TMP/test_script.py"; pass_or_fail "D10" "init --script"
    run_uv add --script "$TMP/test_script.py" --python 3.12 requests; pass_or_fail "D11" "add --script"
    run_uv run --python 3.12 "$TMP/test_script.py"; pass_or_fail "D12" "run script.py"
    run_uv run --python 3.12 $p -m json.tool --help; pass_or_fail "D13" "run -m module"
    run_uv init --app --python 3.12 "$TMP/testproj_app"; pass_or_fail "D14" "init --app"

    if [[ "$FAST" == "true" ]]; then skip "D15" "add --optional" "--fast 跳过"
    else run_uv add --optional web flask $p; pass_or_fail "D15" "add --optional"; fi

    run_uv add --group lint ruff $p; pass_or_fail "D16" "add --group"
    run_uv add --editable "$TMP/testproj_lib" $p; pass_or_fail "D17" "add --editable"
    run_uv sync --no-dev $p; pass_or_fail "D18" "sync --no-dev"
    run_uv export --format pylock.toml $p; pass_or_fail "D19" "export pylock.toml"
    run_uv export --format cyclonedx1.5 $p; pass_or_fail "D20" "export cyclonedx1.5"

    echo "x=1" > "$proj/hello.py"
    run_uv format --preview $p; pass_or_fail "D21" "format"

    if [[ "$FAST" == "true" ]]; then skip "D22" "add --raw" "--fast 跳过"
    else run_uv add --raw httpx $p; pass_or_fail "D22" "add --raw"; fi
}

# ── Group E: Tool 管理 (12) ──
group_e() {
    echo -e "\n═══ Group E: Tool 管理 (12) ═══"
    run_uv tool install ruff
    [[ $_CODE -eq 0 ]] && E1_OK=true && record "E1" "tool install ruff" "PASS" "$_OUT" "$_DUR" || record "E1" "tool install ruff" "FAIL" "$_OUT" "$_DUR"
    if [[ "$E1_OK" != "true" ]]; then skip_batch "E1 失败" E2 E3 E4 E5 E5b E5c E6 E7 E8 E9 E10; return; fi

    run_uv tool list; pass_or_fail "E2" "tool list"
    run_uv tool run ruff --version; pass_or_fail "E3" "tool run ruff"
    run_uv tool uninstall ruff; pass_or_fail "E4" "tool uninstall ruff"
    run_uv tool install black; pass_or_fail "E5" "tool install black"
    run_uv tool upgrade black; pass_or_fail "E5b" "tool upgrade black"
    run_uv tool uninstall black; pass_or_fail "E5c" "tool uninstall black"
    run_uv tool dir --bin; pass_or_fail "E6" "tool dir --bin"

    if [[ "$FAST" == "true" ]]; then
        skip "E7" "tool run 指定版本" "--fast 跳过"
        skip "E8" "tool install --from" "--fast 跳过"
    else
        run_uv tool run ruff@0.3.0 --version; pass_or_fail "E7" "tool run 指定版本"
        run_uv tool install --from ruff ruff; pass_or_fail "E8" "tool install --from"
        [[ $_CODE -eq 0 ]] && run_uv tool uninstall ruff > /dev/null 2>&1
    fi

    run_uv tool upgrade --all; pass_or_fail "E9" "tool upgrade --all"
    run_uv tool list --show-paths; pass_or_fail "E10" "tool list --show-paths"
}

# ── Group F: Cache (2) ──
group_f() {
    echo -e "\n═══ Group F: Cache 管理 (2) ═══"
    run_uv cache prune; pass_or_fail "F1" "cache prune"
    run_uv cache clean; pass_or_fail "F2" "cache clean"
}

# ── Group G: Build (3) ──
group_g() {
    echo -e "\n═══ Group G: Build (3) ═══"
    if [[ "$B2_OK" != "true" ]]; then skip_batch "B2 失败" G1 G2 G3; return; fi
    local lib="$TMP/testproj_lib" out="$TMP/build_out"
    mkdir -p "$out"
    [[ -f "$lib/pyproject.toml" ]] || run_uv init --lib --python 3.12 "$lib"

    run_uv build --python 3.12 --sdist "$lib" --out-dir "$out"; pass_or_fail "G1" "build sdist"
    rm -rf "$out"/*
    run_uv build --python 3.12 --wheel "$lib" --out-dir "$out"; pass_or_fail "G2" "build wheel"
    rm -rf "$out"/*
    run_uv build --python 3.12 "$lib" --out-dir "$out"; pass_or_fail "G3" "build (all)"
}

# ── Group H: Auth (3) ──
group_h() {
    echo -e "\n═══ Group H: Auth 管理 (3) ═══"
    run_uv auth login --help; pass_or_fail "H1" "auth login 帮助"
    run_uv auth logout --help; pass_or_fail "H2" "auth logout 帮助"
    run_uv auth token --help; pass_or_fail "H3" "auth token 帮助"
}

# ── Group I: Workspace (3) ──
group_i() {
    echo -e "\n═══ Group I: Workspace (3) ═══"
    if [[ "$D1_OK" != "true" ]]; then skip_batch "D1 失败" I1 I2 I3; return; fi
    local p="--project $TMP/testproj"
    run_uv workspace dir $p; pass_or_fail "I1" "workspace dir"
    run_uv workspace list $p; pass_or_fail "I2" "workspace list"
    run_uv workspace metadata --frozen $p; pass_or_fail "I3" "workspace metadata"
}

# ── Group J: Publish (1) ──
group_j() {
    echo -e "\n═══ Group J: Publish (1) ═══"
    run_uv publish --help; pass_or_fail "J1" "publish 帮助"
}

# ── 报告 ──
generate_report() {
    local total=${#IDS[@]} executed=$((PASS + FAIL)) rate="0.0"
    [[ $executed -gt 0 ]] && rate=$(echo "scale=1; $PASS * 100 / $executed" | bc 2>/dev/null || echo "0.0")
    local ts=$(date +%Y%m%d_%H%M%S)
    local report="$(cd "$(dirname "$0")" && pwd)/ohos-uv-test-report-${ts}.md"

    {
        echo "# uv 测试报告"
        echo ""
        echo "## 测试摘要"
        echo ""
        echo "| 指标 | 数值 |"
        echo "|------|------|"
        echo "| 测试时间 | $(date '+%Y-%m-%d %H:%M:%S') |"
        echo "| uv 版本 | ${UV_VERSION:-未知} |"
        echo "| uv 路径 | $UV_PATH |"
        echo "| 超时设置 | ${TIMEOUT}s |"
        echo "| 快速模式 | $([ "$FAST" = true ] && echo 是 || echo 否) |"
        echo "| 总用例 | $total |"
        echo "| 通过 | $PASS |"
        echo "| 失败 | $FAIL |"
        echo "| 跳过 | $SKIP |"
        echo "| 通过率 | **${rate}%** |"
        echo ""
        echo "## 完整结果表格"
        echo ""
        echo "| ID | 测试用例 | 状态 | 耗时 |"
        echo "|----|---------|------|------|"
        for i in "${!IDS[@]}"; do
            local icon="⏭️"
            [[ "${STATUSES[$i]}" == "PASS" ]] && icon="✅"
            [[ "${STATUSES[$i]}" == "FAIL" ]] && icon="❌"
            local dur="${DURS[$i]}"
            [[ "$dur" == "0" || "$dur" == "0.0" ]] && dur="-" || dur="${dur}s"
            echo "| ${IDS[$i]} | ${NAMES[$i]} | $icon | $dur |"
        done
    } > "$report"
    echo "$report"
}

# ── 清理 ──
cleanup() {
    echo -e "\n═══ 清理临时文件 ═══"
    rm -rf "$TMP"/testvenv "$TMP"/testvenv_seed "$TMP"/testvenv_py "$TMP"/testvenv2 \
           "$TMP"/testvenv_sys "$TMP"/testvenv_prompt "$TMP"/testproj "$TMP"/testproj_lib \
           "$TMP"/testproj_app "$TMP"/test_script.py "$TMP"/requirements.in "$TMP"/requirements.txt \
           "$TMP"/build_out "$TMP"/pin_test
    echo "  已清理"
}

# ── 主流程 ──
echo "============================================================"
echo "  uv 功能验证测试 (107 用例)"
echo "  uv 路径: $UV_PATH | 超时: ${TIMEOUT}s | 快速模式: $([ "$FAST" = true ] && echo 是 || echo 否)"
echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# 预检
echo -e "\n[预检] 检查 uv..."
ver=$($UV_PATH --version 2>&1) || { echo "[ERROR] uv 未找到: $UV_PATH"; exit 1; }
echo "  ✓ $ver"

START=$(date +%s)
group_a; group_b; group_c; group_d; group_e; group_f; group_g; group_h; group_i; group_j; group_b_cleanup
cleanup

END=$(date +%s)
report=$(generate_report)
total=${#IDS[@]} executed=$((PASS + FAIL)) rate="0.0"
[[ $executed -gt 0 ]] && rate=$(echo "scale=1; $PASS * 100 / $executed" | bc 2>/dev/null || echo "0.0")

echo ""
echo "============================================================"
echo "  测试完成！总耗时: $((END - START))s"
echo "  总计: $total | 通过: $PASS | 失败: $FAIL | 跳过: $SKIP"
echo "  通过率: ${rate}%"
echo "  报告: $report"
echo "============================================================"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
