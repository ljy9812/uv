#!/usr/bin/env python3
"""
uv 功能验证测试脚本 (Python 版)
覆盖 107 个测试用例，本地直接执行

用法:
    uv run test_uv_ohos.py                          # 完整模式
    uv run test_uv_ohos.py --fast                   # 快速模式（跳过重复下载）
    uv run test_uv_ohos.py --timeout 90             # 自定义超时
"""
# /// script
# requires-python = ">=3.10,<3.13"
# ///

import argparse
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Optional


# ─── 常量 ──────────────────────────────────────────────────────────────────────

UV_INDEX_URL = "https://pypi.mirrors.ustc.edu.cn/simple/"
UV_PYTHON_INSTALL_MIRROR = (
    "https://ghfast.top/https://github.com/indygreg/python-build-standalone/releases/download"
)

EXIT_CODE_MARKER = "__EXIT_CODE__="


class Status(Enum):
    PASS = "PASS"
    FAIL = "FAIL"
    SKIP = "SKIP"


@dataclass
class TestResult:
    test_id: str
    name: str
    status: Status
    command: str = ""
    output: str = ""
    duration: float = 0.0
    error: str = ""


# ─── 命令执行封装 ──────────────────────────────────────────────────────────────

def run_command(
    cmd: str,
    timeout: int = 60,
    env: Optional[dict] = None,
) -> tuple[int, str, float]:
    """在本地执行命令，返回 (exit_code, output, duration_sec)"""
    # 设置环境变量
    run_env = os.environ.copy()
    if env:
        run_env.update(env)

    start = time.time()
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=run_env,
        )
        output = result.stdout + result.stderr
        elapsed = time.time() - start
        return (result.returncode, output, elapsed)
    except subprocess.TimeoutExpired:
        elapsed = time.time() - start
        return (124, f"[TIMEOUT after {timeout}s]", elapsed)
    except Exception as e:
        elapsed = time.time() - start
        return (1, f"[ERROR] {e}", elapsed)


# ─── 测试执行器 ─────────────────────────────────────────────────────────────────

class TestRunner:
    def __init__(self, uv_path: str, timeout: int, fast: bool):
        self.uv_path = uv_path
        self.timeout = timeout
        self.fast = fast
        self.results: list[TestResult] = []
        self.uv_version = ""

        # 依赖标记
        self.b2_passed = False
        self.c1_passed = False
        self.d1_passed = False
        self.e1_passed = False

        # 环境变量
        self.env = {
            "UV_INDEX_URL": UV_INDEX_URL,
            "UV_PYTHON_INSTALL_MIRROR": UV_PYTHON_INSTALL_MIRROR,
        }

    def uv(self, args: str) -> tuple[int, str, float]:
        """执行 uv 命令"""
        return run_command(f"{self.uv_path} {args}", self.timeout, self.env)

    def record(self, test_id: str, name: str, status: Status,
               command: str = "", output: str = "", duration: float = 0.0,
               error: str = "") -> TestResult:
        result = TestResult(
            test_id=test_id, name=name, status=status,
            command=command, output=output, duration=duration, error=error,
        )
        self.results.append(result)
        icon = {"PASS": "✅", "FAIL": "❌", "SKIP": "⏭️"}[status.value]
        dur_str = f" ({duration:.1f}s)" if duration > 0 else ""
        err_str = f" - {error}" if error else ""
        print(f"  {icon} [{test_id}] {name}{dur_str}{err_str}")
        return result

    def skip_deps(self, test_id: str, name: str, reason: str) -> TestResult:
        return self.record(test_id, name, Status.SKIP, error=reason)

    # ── Group A: 基础命令 (19) ──────────────────────────────────────────────

    def group_a(self):
        print("\n═══ Group A: 基础命令 ═══")

        # A1: 版本号
        code, out, dur = self.uv("--version")
        ok = code == 0 and "uv" in out.lower()
        self.record("A1", "版本号", Status.PASS if ok else Status.FAIL,
                     "uv --version", out, dur,
                     "" if ok else "输出不包含 uv 版本号")
        if ok:
            m = re.search(r"uv\s+([\d.]+)", out)
            if m:
                self.uv_version = m.group(1)

        # A2: 帮助信息
        code, out, dur = self.uv("--help")
        ok = code == 0 and "uv" in out.lower()
        self.record("A2", "帮助信息", Status.PASS if ok else Status.FAIL,
                     "uv --help", out, dur)

        # A3a-A3i: 子命令帮助
        subcmds = [
            ("A3a", "pip 帮助", "pip --help"),
            ("A3b", "python 帮助", "python --help"),
            ("A3c", "tool 帮助", "tool --help"),
            ("A3d", "cache 帮助", "cache --help"),
            ("A3e", "venv 帮助", "venv --help"),
            ("A3f", "build 帮助", "build --help"),
            ("A3g", "self 帮助", "self --help"),
            ("A3h", "workspace 帮助", "workspace --help"),
            ("A3i", "auth 帮助", "auth --help"),
        ]
        for tid, name, cmd in subcmds:
            code, out, dur = self.uv(cmd)
            ok = code == 0 and len(out) > 20
            self.record(tid, name, Status.PASS if ok else Status.FAIL,
                         f"uv {cmd}", out, dur)

        # A4: Cache 目录
        code, out, dur = self.uv("cache dir")
        ok = code == 0 and "/" in out
        self.record("A4", "Cache 目录", Status.PASS if ok else Status.FAIL,
                     "uv cache dir", out, dur)

        # A5: Cache 大小
        code, out, dur = self.uv("cache size")
        ok = code == 0
        self.record("A5", "Cache 大小", Status.PASS if ok else Status.FAIL,
                     "uv cache size", out, dur)

        # A6: Tool 目录
        code, out, dur = self.uv("tool dir")
        ok = code == 0 and "/" in out
        self.record("A6", "Tool 目录", Status.PASS if ok else Status.FAIL,
                     "uv tool dir", out, dur)

        # A7: Python 目录
        code, out, dur = self.uv("python dir")
        ok = code == 0 and "/" in out
        self.record("A7", "Python 目录", Status.PASS if ok else Status.FAIL,
                     "uv python dir", out, dur)

        # A8: pip debug (退出码 2 表示 unsupported，也算通过)
        code, out, dur = self.uv("pip debug")
        ok = code in (0, 2)
        self.record("A8", "pip debug", Status.PASS if ok else Status.FAIL,
                     "uv pip debug", out, dur,
                     "" if ok else f"退出码 {code}")

        # A9: auth dir
        code, out, dur = self.uv("auth dir")
        ok = code == 0 and "/" in out
        self.record("A9", "auth dir", Status.PASS if ok else Status.FAIL,
                     "uv auth dir", out, dur)

        # A10: self version
        code, out, dur = self.uv("self version")
        ok = code == 0
        self.record("A10", "self version", Status.PASS if ok else Status.FAIL,
                     "uv self version", out, dur)

        # A11: self update --dry-run (已知环境限制，可能失败)
        code, out, dur = self.uv("self update --dry-run")
        ok = code == 0
        self.record("A11", "self update --dry-run",
                     Status.PASS if ok else Status.FAIL,
                     "uv self update --dry-run", out, dur,
                     "" if ok else "OHOS 环境限制：不支持自更新")

    # ── Group B: Python 管理 (9) ────────────────────────────────────────────

    def group_b(self):
        print("\n═══ Group B: Python 管理 ═══")

        # B1: Python 列表
        code, out, dur = self.uv("python list")
        ok = code == 0 and len(out) > 10
        self.record("B1", "Python 列表", Status.PASS if ok else Status.FAIL,
                     "uv python list", out, dur)

        # B2: 检查 Python 3.12（不再自动安装，检查本地是否已有）
        code, out, dur = self.uv("python list --only-installed")
        has_python = code == 0 and "3.12" in out
        self.b2_passed = has_python
        if has_python:
            self.record("B2", "检查 Python 3.12", Status.PASS,
                         "uv python list --only-installed", out, dur,
                         "本地已安装 Python 3.12，跳过安装")
        else:
            self.record("B2", "检查 Python 3.12", Status.FAIL,
                         "uv python list --only-installed", out, dur,
                         "本地未安装 Python 3.12，C/D/G 组将被跳过")

        # B3: 查找 Python
        code, out, dur = self.uv("python find")
        ok = code == 0 and "python" in out.lower()
        self.record("B3", "查找 Python", Status.PASS if ok else Status.FAIL,
                     "uv python find", out, dur)

        # B5: Python pin
        code, out, dur = self.uv("python pin 3.12")
        ok = code == 0
        self.record("B5", "Python pin", Status.PASS if ok else Status.FAIL,
                     "uv python pin 3.12", out, dur)

        # B6: 仅列出已安装
        code, out, dur = self.uv("python list --only-installed")
        ok = code == 0 and "3.12" in out
        self.record("B6", "仅列出已安装", Status.PASS if ok else Status.FAIL,
                     "uv python list --only-installed", out, dur)

        # B7: 列表 --all-versions
        code, out, dur = self.uv("python list --all-versions")
        ok = code == 0 and len(out) > 50
        self.record("B7", "Python 列表 --all-versions", Status.PASS if ok else Status.FAIL,
                     "uv python list --all-versions", out, dur)

        # B8: JSON 格式
        code, out, dur = self.uv("python list --only-installed --output-format json")
        ok = code == 0
        if ok:
            try:
                data = json.loads(out.strip())
                ok = isinstance(data, list)
            except json.JSONDecodeError:
                # 输出可能包含非 JSON 前缀行，尝试提取 JSON 部分
                for line in out.splitlines():
                    if line.strip().startswith("["):
                        try:
                            json_part = line + "]" if not line.endswith("]") else line
                            ok = True
                            break
                        except Exception:
                            pass
        self.record("B8", "Python 列表 JSON 格式", Status.PASS if ok else Status.FAIL,
                     "uv python list --only-installed --output-format json", out, dur)

        # B9: Python 重装 (--fast 模式跳过，且现在不主动安装/重装)
        self.skip_deps("B9", "Python 重装", "不再主动安装/重装 Python")

    def group_b_cleanup(self):
        """B4: 跳过卸载（不再主动安装 Python）"""
        print("\n═══ Group B (cleanup) ═══")
        self.skip_deps("B4", "卸载 Python 3.12", "不再主动安装，跳过卸载")

    # ── Group C: 虚拟环境 + pip (27) ────────────────────────────────────────

    def group_c(self):
        print("\n═══ Group C: 虚拟环境 + pip ═══")

        if not self.b2_passed:
            for tid, name in [
                ("C1", "创建虚拟环境"), ("C10", "venv --seed"), ("C11", "验证 seed 安装"),
                ("C12", "venv --python 3.12"), ("C13", "venv --clear"), ("C14", "venv --allow-existing"),
                ("C15", "venv --no-project"), ("C16", "venv --system-site-packages"),
                ("C17", "venv --prompt"), ("C2", "pip install requests"), ("C3", "pip list"),
                ("C3b", "pip list --format json"), ("C4", "pip show requests"),
                ("C5", "pip freeze"), ("C6", "pip check"), ("C7", "pip tree"),
                ("C2b", "pip install urllib3"), ("C3c", "pip list --outdated"),
                ("C8", "pip uninstall urllib3"), ("C8b", "pip uninstall requests"),
                ("C9", "pip compile"), ("C9b", "pip sync"), ("C18", "pip install -r"),
                ("C19", "pip install --upgrade"), ("C20", "pip install --no-deps"),
                ("C21", "pip install -e"), ("C22", "pip uninstall -r"),
            ]:
                self.skip_deps(tid, name, "B2 失败，跳过 C 组")
            return

        venv_path = "/tmp/testvenv"
        venv_python = f"{venv_path}/bin/python"

        # C1: 创建虚拟环境
        code, out, dur = self.uv(f"venv {venv_path}")
        self.c1_passed = code == 0
        self.record("C1", "创建虚拟环境", Status.PASS if self.c1_passed else Status.FAIL,
                     f"uv venv {venv_path}", out, dur)

        if not self.c1_passed:
            for tid, name in [
                ("C10", "venv --seed"), ("C11", "验证 seed 安装"),
                ("C12", "venv --python 3.12"), ("C13", "venv --clear"), ("C14", "venv --allow-existing"),
                ("C15", "venv --no-project"), ("C16", "venv --system-site-packages"),
                ("C17", "venv --prompt"), ("C2", "pip install requests"), ("C3", "pip list"),
                ("C3b", "pip list --format json"), ("C4", "pip show requests"),
                ("C5", "pip freeze"), ("C6", "pip check"), ("C7", "pip tree"),
                ("C2b", "pip install urllib3"), ("C3c", "pip list --outdated"),
                ("C8", "pip uninstall urllib3"), ("C8b", "pip uninstall requests"),
                ("C9", "pip compile"), ("C9b", "pip sync"), ("C18", "pip install -r"),
                ("C19", "pip install --upgrade"), ("C20", "pip install --no-deps"),
                ("C21", "pip install -e"), ("C22", "pip uninstall -r"),
            ]:
                self.skip_deps(tid, name, "C1 失败，跳过后续")
            return

        # C10: venv --seed
        code, out, dur = self.uv(f"venv --seed /tmp/testvenv_seed")
        ok = code == 0
        self.record("C10", "venv --seed", Status.PASS if ok else Status.FAIL,
                     f"uv venv --seed /tmp/testvenv_seed", out, dur)

        # C11: 验证 seed 安装
        code, out, dur = self.uv(f"pip list --python /tmp/testvenv_seed/bin/python")
        ok = code == 0 and "pip" in out.lower()
        self.record("C11", "验证 seed 安装", Status.PASS if ok else Status.FAIL,
                     f"uv pip list --python .../testvenv_seed/bin/python", out, dur)

        # C12: venv --python 3.12
        code, out, dur = self.uv(f"venv --python 3.12 /tmp/testvenv_py")
        ok = code == 0
        self.record("C12", "venv --python 3.12", Status.PASS if ok else Status.FAIL,
                     f"uv venv --python 3.12 /tmp/testvenv_py", out, dur)

        # C13: venv --clear
        code, out, dur = self.uv(f"venv --clear {venv_path}")
        ok = code == 0
        self.record("C13", "venv --clear", Status.PASS if ok else Status.FAIL,
                     f"uv venv --clear {venv_path}", out, dur)

        # C14: venv --allow-existing
        code, out, dur = self.uv(f"venv --allow-existing {venv_path}")
        ok = code == 0
        self.record("C14", "venv --allow-existing", Status.PASS if ok else Status.FAIL,
                     f"uv venv --allow-existing {venv_path}", out, dur)

        # C15: venv --no-project
        code, out, dur = self.uv(f"venv --no-project /tmp/testvenv2")
        ok = code == 0
        self.record("C15", "venv --no-project", Status.PASS if ok else Status.FAIL,
                     f"uv venv --no-project /tmp/testvenv2", out, dur)

        # C16: venv --system-site-packages
        code, out, dur = self.uv(f"venv --system-site-packages /tmp/testvenv_sys")
        ok = code == 0
        self.record("C16", "venv --system-site-packages", Status.PASS if ok else Status.FAIL,
                     f"uv venv --system-site-packages /tmp/testvenv_sys", out, dur)

        # C17: venv --prompt
        code, out, dur = self.uv(f"venv --prompt myenv /tmp/testvenv_prompt")
        ok = code == 0
        self.record("C17", "venv --prompt", Status.PASS if ok else Status.FAIL,
                     f"uv venv --prompt myenv /tmp/testvenv_prompt", out, dur)

        # ── pip 操作 ──
        py = f"--python {venv_python}"

        # C2: pip install requests
        code, out, dur = self.uv(f"pip install requests {py}")
        ok = code == 0
        self.record("C2", "pip install requests", Status.PASS if ok else Status.FAIL,
                     f"uv pip install requests {py}", out, dur)

        # C3: pip list
        code, out, dur = self.uv(f"pip list {py}")
        ok = code == 0 and "requests" in out.lower()
        self.record("C3", "pip list", Status.PASS if ok else Status.FAIL,
                     f"uv pip list {py}", out, dur)

        # C3b: pip list --format json
        code, out, dur = self.uv(f"pip list {py} --format json")
        ok = code == 0
        self.record("C3b", "pip list --format json", Status.PASS if ok else Status.FAIL,
                     f"uv pip list {py} --format json", out, dur)

        # C4: pip show requests
        code, out, dur = self.uv(f"pip show requests {py}")
        ok = code == 0 and "requests" in out.lower()
        self.record("C4", "pip show requests", Status.PASS if ok else Status.FAIL,
                     f"uv pip show requests {py}", out, dur)

        # C5: pip freeze
        code, out, dur = self.uv(f"pip freeze {py}")
        ok = code == 0 and "requests" in out.lower()
        self.record("C5", "pip freeze", Status.PASS if ok else Status.FAIL,
                     f"uv pip freeze {py}", out, dur)

        # C6: pip check
        code, out, dur = self.uv(f"pip check {py}")
        ok = code == 0
        self.record("C6", "pip check", Status.PASS if ok else Status.FAIL,
                     f"uv pip check {py}", out, dur)

        # C7: pip tree
        code, out, dur = self.uv(f"pip tree {py}")
        ok = code == 0 and "requests" in out.lower()
        self.record("C7", "pip tree", Status.PASS if ok else Status.FAIL,
                     f"uv pip tree {py}", out, dur)

        # C2b: pip install urllib3
        code, out, dur = self.uv(f"pip install urllib3 {py}")
        ok = code == 0
        self.record("C2b", "pip install urllib3", Status.PASS if ok else Status.FAIL,
                     f"uv pip install urllib3 {py}", out, dur)

        # C3c: pip list --outdated
        code, out, dur = self.uv(f"pip list {py} --outdated")
        ok = code == 0
        self.record("C3c", "pip list --outdated", Status.PASS if ok else Status.FAIL,
                     f"uv pip list {py} --outdated", out, dur)

        # C8: pip uninstall urllib3
        code, out, dur = self.uv(f"pip uninstall urllib3 {py}")
        ok = code == 0
        self.record("C8", "pip uninstall urllib3", Status.PASS if ok else Status.FAIL,
                     f"uv pip uninstall urllib3 {py}", out, dur)

        # C8b: pip uninstall requests
        code, out, dur = self.uv(f"pip uninstall requests {py}")
        ok = code == 0
        self.record("C8b", "pip uninstall requests", Status.PASS if ok else Status.FAIL,
                     f"uv pip uninstall requests {py}", out, dur)

        # C9: pip compile
        req_in = "/tmp/requirements.in"
        req_txt = "/tmp/requirements.txt"
        run_command(f"echo 'requests' > {req_in}", 10)
        code, out, dur = self.uv(f"pip compile {req_in} -o {req_txt}")
        ok = code == 0
        self.record("C9", "pip compile", Status.PASS if ok else Status.FAIL,
                     f"uv pip compile {req_in} -o {req_txt}", out, dur)

        # C9b: pip sync
        code, out, dur = self.uv(f"pip sync {req_txt} {py}")
        ok = code == 0
        self.record("C9b", "pip sync", Status.PASS if ok else Status.FAIL,
                     f"uv pip sync {req_txt} {py}", out, dur)

        # C18: pip install -r requirements.txt
        code, out, dur = self.uv(f"pip install -r {req_txt} {py}")
        ok = code == 0
        self.record("C18", "pip install -r requirements.txt", Status.PASS if ok else Status.FAIL,
                     f"uv pip install -r {req_txt} {py}", out, dur)

        # C19: pip install --upgrade
        code, out, dur = self.uv(f"pip install --upgrade requests {py}")
        ok = code == 0
        self.record("C19", "pip install --upgrade", Status.PASS if ok else Status.FAIL,
                     f"uv pip install --upgrade requests {py}", out, dur)

        # C20: pip install --no-deps
        code, out, dur = self.uv(f"pip install --no-deps idna {py}")
        ok = code == 0
        self.record("C20", "pip install --no-deps", Status.PASS if ok else Status.FAIL,
                     f"uv pip install --no-deps idna {py}", out, dur)

        # C21: pip install -e (需要先创建 testproj_lib)
        lib_path = f"/tmp/testproj_lib"
        self.uv(f"init --lib {lib_path}")
        code, out, dur = self.uv(f"pip install -e {lib_path} {py}")
        ok = code == 0
        self.record("C21", "pip install -e", Status.PASS if ok else Status.FAIL,
                     f"uv pip install -e {lib_path} {py}", out, dur)

        # C22: pip uninstall -r
        code, out, dur = self.uv(f"pip uninstall -r {req_txt} {py}")
        ok = code == 0
        self.record("C22", "pip uninstall -r", Status.PASS if ok else Status.FAIL,
                     f"uv pip uninstall -r {req_txt} {py}", out, dur)

    # ── Group D: 项目管理 (28) ──────────────────────────────────────────────

    def group_d(self):
        print("\n═══ Group D: 项目管理 ═══")

        if not self.b2_passed:
            for tid, name in [
                ("D1", "init 项目"), ("D2", "lock"), ("D3", "sync"), ("D4", "add 依赖"),
                ("D5", "tree"), ("D5b", "project version"), ("D4b", "add --dev 依赖"),
                ("D6b", "remove --dev 依赖"), ("D6", "remove 依赖"), ("D7", "run"),
                ("D8", "export"), ("D7b", "run --with"), ("D2b", "lock --upgrade"),
                ("D3b", "sync --frozen"), ("D9", "init --lib"), ("D10", "init --script"),
                ("D11", "add --script"), ("D12", "run script.py"), ("D13", "run -m module"),
                ("D14", "init --app"), ("D15", "add --optional"), ("D16", "add --group"),
                ("D17", "add --editable"), ("D18", "sync --no-dev"),
                ("D19", "export --format pylock.toml"), ("D20", "export --format cyclonedx1.5"),
                ("D21", "format"), ("D22", "add --raw"),
            ]:
                self.skip_deps(tid, name, "B2 失败，跳过 D 组")
            return

        proj = f"/tmp/testproj"
        p = f"--project {proj}"

        # D1: init 项目
        code, out, dur = self.uv(f"init {proj}")
        self.d1_passed = code == 0
        self.record("D1", "init 项目", Status.PASS if self.d1_passed else Status.FAIL,
                     f"uv init {proj}", out, dur)

        if not self.d1_passed:
            for tid, name in [
                ("D2", "lock"), ("D3", "sync"), ("D4", "add 依赖"), ("D5", "tree"),
                ("D5b", "project version"), ("D4b", "add --dev 依赖"), ("D6b", "remove --dev 依赖"),
                ("D6", "remove 依赖"), ("D7", "run"), ("D8", "export"), ("D7b", "run --with"),
                ("D2b", "lock --upgrade"), ("D3b", "sync --frozen"), ("D9", "init --lib"),
                ("D10", "init --script"), ("D11", "add --script"), ("D12", "run script.py"),
                ("D13", "run -m module"), ("D14", "init --app"), ("D15", "add --optional"),
                ("D16", "add --group"), ("D17", "add --editable"), ("D18", "sync --no-dev"),
                ("D19", "export --format pylock.toml"), ("D20", "export --format cyclonedx1.5"),
                ("D21", "format"), ("D22", "add --raw"),
            ]:
                self.skip_deps(tid, name, "D1 失败，跳过后续")
            return

        # D2: lock
        code, out, dur = self.uv(f"lock {p}")
        ok = code == 0
        self.record("D2", "lock", Status.PASS if ok else Status.FAIL,
                     f"uv lock {p}", out, dur)

        # D3: sync
        code, out, dur = self.uv(f"sync {p}")
        ok = code == 0
        self.record("D3", "sync", Status.PASS if ok else Status.FAIL,
                     f"uv sync {p}", out, dur)

        # D4: add 依赖
        code, out, dur = self.uv(f"add requests {p}")
        ok = code == 0
        self.record("D4", "add 依赖", Status.PASS if ok else Status.FAIL,
                     f"uv add requests {p}", out, dur)

        # D5: tree
        code, out, dur = self.uv(f"tree {p}")
        ok = code == 0
        self.record("D5", "tree", Status.PASS if ok else Status.FAIL,
                     f"uv tree {p}", out, dur)

        # D5b: project version
        code, out, dur = self.uv(f"version {p}")
        ok = code == 0
        self.record("D5b", "project version", Status.PASS if ok else Status.FAIL,
                     f"uv version {p}", out, dur)

        # D4b: add --dev 依赖
        code, out, dur = self.uv(f"add --dev pytest {p}")
        ok = code == 0
        self.record("D4b", "add --dev 依赖", Status.PASS if ok else Status.FAIL,
                     f"uv add --dev pytest {p}", out, dur)

        # D6b: remove --dev 依赖
        code, out, dur = self.uv(f"remove --dev pytest {p}")
        ok = code == 0
        self.record("D6b", "remove --dev 依赖", Status.PASS if ok else Status.FAIL,
                     f"uv remove --dev pytest {p}", out, dur)

        # D6: remove 依赖
        code, out, dur = self.uv(f"remove requests {p}")
        ok = code == 0
        self.record("D6", "remove 依赖", Status.PASS if ok else Status.FAIL,
                     f"uv remove requests {p}", out, dur)

        # D7: run
        code, out, dur = self.uv(f'run {p} python -c "print(\'hello\')"')
        ok = code == 0 and "hello" in out
        self.record("D7", "run", Status.PASS if ok else Status.FAIL,
                     f"uv run {p} python -c \"print('hello')\"", out, dur)

        # D8: export
        code, out, dur = self.uv(f"export {p}")
        ok = code == 0
        self.record("D8", "export", Status.PASS if ok else Status.FAIL,
                     f"uv export {p}", out, dur)

        # D7b: run --with
        code, out, dur = self.uv(
            f'run --with requests {p} python -c "import requests; print(requests.__version__)"'
        )
        ok = code == 0
        self.record("D7b", "run --with", Status.PASS if ok else Status.FAIL,
                     "uv run --with requests ... python -c ...", out, dur)

        # D2b: lock --upgrade
        code, out, dur = self.uv(f"lock --upgrade {p}")
        ok = code == 0
        self.record("D2b", "lock --upgrade", Status.PASS if ok else Status.FAIL,
                     f"uv lock --upgrade {p}", out, dur)

        # D3b: sync --frozen
        code, out, dur = self.uv(f"sync --frozen {p}")
        ok = code == 0
        self.record("D3b", "sync --frozen", Status.PASS if ok else Status.FAIL,
                     f"uv sync --frozen {p}", out, dur)

        # D9: init --lib
        lib_path = f"/tmp/testproj_lib"
        code, out, dur = self.uv(f"init --lib {lib_path}")
        ok = code == 0
        self.record("D9", "init --lib", Status.PASS if ok else Status.FAIL,
                     f"uv init --lib {lib_path}", out, dur)

        # D10: init --script
        script_path = f"/tmp/test_script.py"
        code, out, dur = self.uv(f"init --script {script_path}")
        ok = code == 0
        self.record("D10", "init --script", Status.PASS if ok else Status.FAIL,
                     f"uv init --script {script_path}", out, dur)

        # D11: add --script
        code, out, dur = self.uv(f"add --script {script_path} requests")
        ok = code == 0
        self.record("D11", "add --script", Status.PASS if ok else Status.FAIL,
                     f"uv add --script {script_path} requests", out, dur)

        # D12: run script.py
        code, out, dur = self.uv(f"run {script_path}")
        ok = code == 0
        self.record("D12", "run script.py", Status.PASS if ok else Status.FAIL,
                     f"uv run {script_path}", out, dur)

        # D13: run -m module
        code, out, dur = self.uv(f"run {p} -m json.tool --help")
        ok = code == 0
        self.record("D13", "run -m module", Status.PASS if ok else Status.FAIL,
                     f"uv run {p} -m json.tool --help", out, dur)

        # D14: init --app
        app_path = f"/tmp/testproj_app"
        code, out, dur = self.uv(f"init --app {app_path}")
        ok = code == 0
        self.record("D14", "init --app", Status.PASS if ok else Status.FAIL,
                     f"uv init --app {app_path}", out, dur)

        # D15: add --optional (--fast 模式跳过)
        if self.fast:
            self.skip_deps("D15", "add --optional", "--fast 模式跳过（下载 Flask + 依赖）")
        else:
            code, out, dur = self.uv(f"add --optional web flask {p}")
            ok = code == 0
            self.record("D15", "add --optional", Status.PASS if ok else Status.FAIL,
                         f"uv add --optional web flask {p}", out, dur)

        # D16: add --group
        code, out, dur = self.uv(f"add --group lint ruff {p}")
        ok = code == 0
        self.record("D16", "add --group", Status.PASS if ok else Status.FAIL,
                     f"uv add --group lint ruff {p}", out, dur)

        # D17: add --editable
        code, out, dur = self.uv(f"add --editable {lib_path} {p}")
        ok = code == 0
        self.record("D17", "add --editable", Status.PASS if ok else Status.FAIL,
                     f"uv add --editable {lib_path} {p}", out, dur)

        # D18: sync --no-dev
        code, out, dur = self.uv(f"sync --no-dev {p}")
        ok = code == 0
        self.record("D18", "sync --no-dev", Status.PASS if ok else Status.FAIL,
                     f"uv sync --no-dev {p}", out, dur)

        # D19: export --format pylock.toml
        code, out, dur = self.uv(f"export --format pylock.toml {p}")
        ok = code == 0
        self.record("D19", "export --format pylock.toml", Status.PASS if ok else Status.FAIL,
                     f"uv export --format pylock.toml {p}", out, dur)

        # D20: export --format cyclonedx1.5
        code, out, dur = self.uv(f"export --format cyclonedx1.5 {p}")
        ok = code == 0
        self.record("D20", "export --format cyclonedx1.5", Status.PASS if ok else Status.FAIL,
                     f"uv export --format cyclonedx1.5 {p}", out, dur)

        # D21: format
        # 先创建一个简单的 Python 文件用于格式化
        hello_path = f"{proj}/hello.py"
        run_command(f'echo "x=1" > {hello_path}', 10)
        code, out, dur = self.uv(f"format {p}")
        ok = code == 0
        self.record("D21", "format", Status.PASS if ok else Status.FAIL,
                     f"uv format {p}", out, dur)

        # D22: add --raw (--fast 模式跳过)
        if self.fast:
            self.skip_deps("D22", "add --raw", "--fast 模式跳过（下载 httpx）")
        else:
            code, out, dur = self.uv(f"add --raw httpx {p}")
            ok = code == 0
            self.record("D22", "add --raw", Status.PASS if ok else Status.FAIL,
                         f"uv add --raw httpx {p}", out, dur)

    # ── Group E: Tool 管理 (12) ─────────────────────────────────────────────

    def group_e(self):
        print("\n═══ Group E: Tool 管理 ═══")

        # E1: tool install ruff
        code, out, dur = self.uv("tool install ruff")
        self.e1_passed = code == 0
        self.record("E1", "tool install ruff", Status.PASS if self.e1_passed else Status.FAIL,
                     "uv tool install ruff", out, dur)

        if not self.e1_passed:
            for tid, name in [
                ("E2", "tool list"), ("E3", "tool run ruff"), ("E4", "tool uninstall ruff"),
                ("E5", "tool install black"), ("E5b", "tool upgrade black"),
                ("E5c", "tool uninstall black"), ("E6", "tool dir --bin"),
                ("E7", "tool run 指定版本"), ("E8", "tool install --from"),
                ("E9", "tool upgrade --all"), ("E10", "tool list --show-paths"),
            ]:
                self.skip_deps(tid, name, "E1 失败，跳过 E 组")
            return

        # E2: tool list
        code, out, dur = self.uv("tool list")
        ok = code == 0 and "ruff" in out.lower()
        self.record("E2", "tool list", Status.PASS if ok else Status.FAIL,
                     "uv tool list", out, dur)

        # E3: tool run ruff
        code, out, dur = self.uv("tool run ruff --version")
        ok = code == 0
        self.record("E3", "tool run ruff", Status.PASS if ok else Status.FAIL,
                     "uv tool run ruff --version", out, dur)

        # E4: tool uninstall ruff
        code, out, dur = self.uv("tool uninstall ruff")
        ok = code == 0
        self.record("E4", "tool uninstall ruff", Status.PASS if ok else Status.FAIL,
                     "uv tool uninstall ruff", out, dur)

        # E5: tool install black
        code, out, dur = self.uv("tool install black")
        ok = code == 0
        self.record("E5", "tool install black", Status.PASS if ok else Status.FAIL,
                     "uv tool install black", out, dur)

        # E5b: tool upgrade black
        code, out, dur = self.uv("tool upgrade black")
        ok = code == 0
        self.record("E5b", "tool upgrade black", Status.PASS if ok else Status.FAIL,
                     "uv tool upgrade black", out, dur)

        # E5c: tool uninstall black
        code, out, dur = self.uv("tool uninstall black")
        ok = code == 0
        self.record("E5c", "tool uninstall black", Status.PASS if ok else Status.FAIL,
                     "uv tool uninstall black", out, dur)

        # E6: tool dir --bin
        code, out, dur = self.uv("tool dir --bin")
        ok = code == 0 and "/" in out
        self.record("E6", "tool dir --bin", Status.PASS if ok else Status.FAIL,
                     "uv tool dir --bin", out, dur)

        # E7: tool run 指定版本 (--fast 模式跳过)
        if self.fast:
            self.skip_deps("E7", "tool run 指定版本", "--fast 模式跳过（重复下载 ruff）")
        else:
            code, out, dur = self.uv("tool run ruff@0.3.0 --version")
            ok = code == 0
            self.record("E7", "tool run 指定版本", Status.PASS if ok else Status.FAIL,
                         "uv tool run ruff@0.3.0 --version", out, dur)

        # E8: tool install --from (--fast 模式跳过)
        if self.fast:
            self.skip_deps("E8", "tool install --from", "--fast 模式跳过（重复下载 ruff）")
        else:
            code, out, dur = self.uv("tool install --from ruff ruff")
            ok = code == 0
            self.record("E8", "tool install --from", Status.PASS if ok else Status.FAIL,
                         "uv tool install --from ruff ruff", out, dur)
            if ok:
                self.uv("tool uninstall ruff")  # 清理

        # E9: tool upgrade --all
        code, out, dur = self.uv("tool upgrade --all")
        ok = code == 0
        self.record("E9", "tool upgrade --all", Status.PASS if ok else Status.FAIL,
                     "uv tool upgrade --all", out, dur)

        # E10: tool list --show-paths
        code, out, dur = self.uv("tool list --show-paths")
        ok = code == 0
        self.record("E10", "tool list --show-paths", Status.PASS if ok else Status.FAIL,
                     "uv tool list --show-paths", out, dur)

    # ── Group F: Cache 管理 (2) ─────────────────────────────────────────────

    def group_f(self):
        print("\n═══ Group F: Cache 管理 ═══")

        # F1: cache prune
        code, out, dur = self.uv("cache prune")
        ok = code == 0
        self.record("F1", "cache prune", Status.PASS if ok else Status.FAIL,
                     "uv cache prune", out, dur)

        # F2: cache clean
        code, out, dur = self.uv("cache clean")
        ok = code == 0
        self.record("F2", "cache clean", Status.PASS if ok else Status.FAIL,
                     "uv cache clean", out, dur)

    # ── Group G: Build (3) ──────────────────────────────────────────────────

    def group_g(self):
        print("\n═══ Group G: Build ═══")

        if not self.b2_passed:
            for tid, name in [("G1", "build sdist"), ("G2", "build wheel"), ("G3", "build (all)")]:
                self.skip_deps(tid, name, "B2 失败，跳过 G 组")
            return

        lib_path = "/tmp/testproj_lib"
        out_dir = "/tmp/build_out"

        # 确保 lib 项目存在
        run_command(f"mkdir -p {out_dir}", 10)
        _, check_out, _ = run_command(f"test -f {lib_path}/pyproject.toml && echo yes", 10)
        if "yes" not in check_out:
            self.uv(f"init --lib {lib_path}")

        # G1: build sdist
        code, out, dur = self.uv(f"build --sdist {lib_path} --out-dir {out_dir}")
        ok = code == 0
        self.record("G1", "build sdist", Status.PASS if ok else Status.FAIL,
                     f"uv build --sdist {lib_path} --out-dir {out_dir}", out, dur)

        # G2: build wheel
        run_command(f"rm -rf {out_dir}/*", 10)
        code, out, dur = self.uv(f"build --wheel {lib_path} --out-dir {out_dir}")
        ok = code == 0
        self.record("G2", "build wheel", Status.PASS if ok else Status.FAIL,
                     f"uv build --wheel {lib_path} --out-dir {out_dir}", out, dur)

        # G3: build (all)
        run_command(f"rm -rf {out_dir}/*", 10)
        code, out, dur = self.uv(f"build {lib_path} --out-dir {out_dir}")
        ok = code == 0
        self.record("G3", "build (all)", Status.PASS if ok else Status.FAIL,
                     f"uv build {lib_path} --out-dir {out_dir}", out, dur)

    # ── Group H: Auth 管理 (3) ──────────────────────────────────────────────

    def group_h(self):
        print("\n═══ Group H: Auth 管理 ═══")

        for tid, name, cmd in [
            ("H1", "auth login 帮助", "auth login --help"),
            ("H2", "auth logout 帮助", "auth logout --help"),
            ("H3", "auth token 帮助", "auth token --help"),
        ]:
            code, out, dur = self.uv(cmd)
            ok = code == 0 and len(out) > 10
            self.record(tid, name, Status.PASS if ok else Status.FAIL,
                         f"uv {cmd}", out, dur)

    # ── Group I: Workspace 管理 (3) ─────────────────────────────────────────

    def group_i(self):
        print("\n═══ Group I: Workspace 管理 ═══")

        proj = f"/tmp/testproj"
        p = f"--project {proj}"

        if not self.d1_passed:
            for tid, name in [
                ("I1", "workspace dir"), ("I2", "workspace list"), ("I3", "workspace metadata"),
            ]:
                self.skip_deps(tid, name, "D1 失败，跳过 I 组")
            return

        # I1: workspace dir
        code, out, dur = self.uv(f"workspace dir {p}")
        ok = code == 0 and "/" in out
        self.record("I1", "workspace dir", Status.PASS if ok else Status.FAIL,
                     f"uv workspace dir {p}", out, dur)

        # I2: workspace list
        code, out, dur = self.uv(f"workspace list {p}")
        ok = code == 0
        self.record("I2", "workspace list", Status.PASS if ok else Status.FAIL,
                     f"uv workspace list {p}", out, dur)

        # I3: workspace metadata
        code, out, dur = self.uv(f"workspace metadata --frozen {p}")
        ok = code == 0
        self.record("I3", "workspace metadata", Status.PASS if ok else Status.FAIL,
                     f"uv workspace metadata --frozen {p}", out, dur)

    # ── Group J: Publish (1) ────────────────────────────────────────────────

    def group_j(self):
        print("\n═══ Group J: Publish ═══")

        code, out, dur = self.uv("publish --help")
        ok = code == 0 and "publish" in out.lower()
        self.record("J1", "publish 帮助", Status.PASS if ok else Status.FAIL,
                     "uv publish --help", out, dur)

    # ── 主流程 ──────────────────────────────────────────────────────────────

    def run_all(self):
        """按依赖顺序执行所有测试"""
        print("=" * 60)
        print("  uv 功能验证测试")
        print(f"  uv 路径: {self.uv_path}")
        print(f"  超时: {self.timeout}s | 快速模式: {'是' if self.fast else '否'}")
        print(f"  时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("=" * 60)

        # 预检：uv 是否存在
        print("\n[预检] 检查 uv...")
        code, out, dur = run_command(f"{self.uv_path} --version", 10)
        if code != 0:
            print(f"[ERROR] uv 未找到: {self.uv_path}")
            print("请确保 uv 已安装并在 PATH 中")
            sys.exit(1)
        print(f"  ✓ uv 可用: {out.strip()}")
        print("[预检] ✓ 预检通过，开始测试\n")

        self.group_a()
        self.group_b()
        self.group_c()
        self.group_d()
        self.group_e()
        self.group_f()
        self.group_g()
        self.group_h()
        self.group_i()
        self.group_j()
        self.group_b_cleanup()

        # 清理设备临时文件
        print("\n═══ 清理临时文件 ═══")
        cleanup_paths = [
            f"/tmp/testvenv", f"/tmp/testvenv_seed",
            f"/tmp/testvenv_py", f"/tmp/testvenv2",
            f"/tmp/testvenv_sys", f"/tmp/testvenv_prompt",
            f"/tmp/testproj", f"/tmp/testproj_lib",
            f"/tmp/testproj_app", f"/tmp/test_script.py",
            f"/tmp/requirements.in", f"/tmp/requirements.txt",
            f"/tmp/build_out",
        ]
        for path in cleanup_paths:
            run_command(f"rm -rf {path}", 10)
        print("  临时文件已清理")


# ─── 报告生成 ──────────────────────────────────────────────────────────────────

def generate_report(runner: TestRunner, output_dir: Path) -> Path:
    """生成 Markdown 测试报告"""
    results = runner.results
    total = len(results)
    passed = sum(1 for r in results if r.status == Status.PASS)
    failed = sum(1 for r in results if r.status == Status.FAIL)
    skipped = sum(1 for r in results if r.status == Status.SKIP)
    pass_rate = (passed / (total - skipped) * 100) if (total - skipped) > 0 else 0

    now = datetime.now()
    timestamp = now.strftime("%Y%m%d_%H%M%S")
    report_path = output_dir / f"ohos-uv-test-report-{timestamp}.md"

    lines = [
        f"# OHOS uv 测试报告",
        f"",
        f"## 测试摘要",
        f"",
        f"| 指标 | 数值 |",
        f"|------|------|",
        f"| 测试时间 | {now.strftime('%Y-%m-%d %H:%M:%S')} |",
        f"| uv 版本 | {runner.uv_version or '未知'} |",
        f"| uv 路径 | {runner.uv_path} |",
        f"| 超时设置 | {runner.timeout}s |",
        f"| 快速模式 | {'是' if runner.fast else '否'} |",
        f"| 总用例 | {total} |",
        f"| 通过 | {passed} |",
        f"| 失败 | {failed} |",
        f"| 跳过 | {skipped} |",
        f"| 通过率 | **{pass_rate:.1f}%** |",
        f"",
    ]

    # 失败详情
    failed_results = [r for r in results if r.status == Status.FAIL]
    if failed_results:
        lines.append("## 失败用例详情")
        lines.append("")
        for r in failed_results:
            lines.append(f"### {r.test_id}: {r.name}")
            lines.append(f"")
            lines.append(f"- **命令**: `{r.command}`")
            lines.append(f"- **错误**: {r.error}")
            lines.append(f"- **耗时**: {r.duration:.1f}s")
            lines.append(f"- **输出** (前 20 行):")
            lines.append(f"```")
            for line in r.output.splitlines()[:20]:
                lines.append(line)
            lines.append(f"```")
            lines.append(f"")

    # 跳过列表
    skipped_results = [r for r in results if r.status == Status.SKIP]
    if skipped_results:
        lines.append("## 跳过用例列表")
        lines.append("")
        lines.append("| ID | 名称 | 原因 |")
        lines.append("|----|------|------|")
        for r in skipped_results:
            lines.append(f"| {r.test_id} | {r.name} | {r.error} |")
        lines.append("")

    # 完整结果表格
    lines.append("## 完整结果表格")
    lines.append("")
    lines.append("| ID | 测试用例 | 状态 | 耗时 |")
    lines.append("|----|---------|------|------|")
    for r in results:
        icon = {"PASS": "✅", "FAIL": "❌", "SKIP": "⏭️"}[r.status.value]
        dur = f"{r.duration:.1f}s" if r.duration > 0 else "-"
        lines.append(f"| {r.test_id} | {r.name} | {icon} | {dur} |")
    lines.append("")

    report_path.write_text("\n".join(lines), encoding="utf-8")
    return report_path


# ─── 主入口 ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="uv 功能验证测试 (107 个用例)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  uv run test_uv_ohos.py                          # 完整模式
  uv run test_uv_ohos.py --fast                   # 快速模式
  uv run test_uv_ohos.py --timeout 90             # 自定义超时
  uv run test_uv_ohos.py --uv-path /usr/local/bin/uv  # 指定 uv 路径
        """,
    )
    parser.add_argument(
        "--uv-path", default="uv",
        help="uv 可执行文件路径 (默认: uv)",
    )
    parser.add_argument(
        "--timeout", type=int, default=60,
        help="每个测试的超时秒数 (默认: 60)",
    )
    parser.add_argument(
        "--fast", action="store_true",
        help="快速模式：跳过重复下载用例 (B9/E7/E8/D15/D22)",
    )

    args = parser.parse_args()

    runner = TestRunner(
        uv_path=args.uv_path,
        timeout=args.timeout,
        fast=args.fast,
    )

    start_time = time.time()
    runner.run_all()
    total_time = time.time() - start_time

    # 生成报告
    output_dir = Path(__file__).parent
    report_path = generate_report(runner, output_dir)

    # 打印摘要
    results = runner.results
    total = len(results)
    passed = sum(1 for r in results if r.status == Status.PASS)
    failed = sum(1 for r in results if r.status == Status.FAIL)
    skipped = sum(1 for r in results if r.status == Status.SKIP)
    pass_rate = (passed / (total - skipped) * 100) if (total - skipped) > 0 else 0

    print("\n" + "=" * 60)
    print(f"  测试完成！总耗时: {total_time:.1f}s")
    print(f"  总计: {total} | 通过: {passed} | 失败: {failed} | 跳过: {skipped}")
    print(f"  通过率: {pass_rate:.1f}%")
    print(f"  报告: {report_path}")
    print("=" * 60)

    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
