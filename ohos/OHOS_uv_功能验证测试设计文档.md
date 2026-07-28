# OHOS uv 功能验证测试设计文档

## 1. 测试概述

本文档描述在 OpenHarmony (OHOS) 设备上对 uv 工具进行**端到端功能验证**的测试设计。

与原有测试（`test-uv-ohos.sh`）仅通过命令退出码判断 PASS/FAIL 不同，本测试在执行主命令后，额外运行**功能验证命令**来确认功能真正可用，引入 `PARTIAL` 状态：

```
┌────────────┐    ┌──────────────┐    ┌────────────────┐
│  主命令     │───▶│ 退出码 == 0? │───▶│  功能验证命令   │
│ (uv xxx)   │    │              │    │ (import/文件检查)│
└────────────┘    └──────┬───────┘    └────────┬───────┘
                        │                       │
                    NO → ❌ FAIL            成功 → ✅ PASS
                    YES ↓                  失败 → ⚠️ PARTIAL
                  执行验证命令
```

**三种结果：**
- ✅ **PASS**：命令成功 + 功能验证通过
- ⚠️ **PARTIAL**：命令成功 + 功能验证失败（功能可能损坏）
- ❌ **FAIL**：命令本身失败
- ⏭️ **SKIP**：前置条件不满足

## 2. 预置条件

与原测试脚本一致，详见 `OHOS_uv_测试设计文档.md`。本脚本自行完成环境准备，可独立运行。

## 3. 验证用例清单（43 个）

### 3.1 Group B: Python 管理（5 个）

| ID | 主命令 | 验证命令 | 验证逻辑 |
|----|--------|---------|---------|
| B2 | `python install 3.12` | `$PY -c "import sys; print(sys.version)"` | 输出包含 "3.12" |
| B3 | `python find` | `$FOUND_PY -c "print('hello')"` | 退出码为 0，输出 "hello" |
| B5 | `python pin 3.12 --project /data/local/tmp` | `cat /data/local/tmp/.python-version` | 内容包含 "3.12" |
| B9 | `python install --reinstall 3.12` | `$PY -c "import sys; print(sys.version)"` | 重装后仍可执行，输出包含 "3.12" |
| B4 | `python uninstall 3.12` | `$PY -c "import sys" 2>/dev/null; echo $?` | 退出码非 0（已卸载不可执行） |

> `$PY`：通过 `uv python find` 获取的已安装 Python 解释器完整路径

### 3.2 Group C: 虚拟环境 + pip（16 个）

| ID | 主命令 | 验证命令 | 验证逻辑 |
|----|--------|---------|---------|
| C1 | `venv /data/local/tmp/testvenv` | `$VP -c "import sys; print(sys.prefix)"` | 输出包含 "testvenv" |
| C10 | `venv --seed /data/local/tmp/testvenv_seed` | `/data/local/tmp/testvenv_seed/bin/pip --version` | 退出码为 0 |
| C11 | `pip list --python testvenv_seed/bin/python` | `testvenv_seed/bin/python -c "import pip; print(pip.__version__)"` | 输出匹配版本号 |
| C12 | `venv --python 3.12 testvenv_py` | `testvenv_py/bin/python -c "import sys; print(sys.version)"` | 输出包含 "3.12" |
| C13 | `venv --clear testvenv` | `$VP -c "import sys; print(sys.prefix)"` | --clear 后 venv 仍可用 |
| C2 | `pip install requests` | `$VP -c "import requests; print(requests.__version__)"` | 输出匹配版本号 `[0-9]+\.` |
| C3 | `pip list` | `$VP -c "import requests"` | 退出码为 0（与 list 交叉验证） |
| C8 | `pip uninstall urllib3` | `$VP -c "import urllib3" 2>/dev/null; echo $?` | 退出码非 0（卸载成功） |
| C8b | `pip uninstall requests` | `$VP -c "import requests" 2>/dev/null; echo $?` | 退出码非 0（卸载成功） |
| C9b | `pip sync requirements.txt` | `$VP -c "import requests; print(requests.__version__)"` | sync 后 requests 可 import |
| C18 | `pip install -r requirements_install.txt` | `$VP -c "import chardet; print(chardet.__version__)"` | 从文件安装后包可 import |
| C19 | `pip install --upgrade requests` | `$VP -c "import requests; print(requests.__version__)"` | 升级后仍可 import |
| C20 | `pip install --no-deps idna` | `$VP -c "import idna; print(idna.__version__)"` | 包本身可 import |
| C21 | `pip install -e testproj_lib` | `$VP -c "import test_ohos_lib; print(test_ohos_lib.__file__)"` | 路径包含 "testproj_lib" 且不含 "site-packages" |
| C22 | `pip uninstall -r requirements_install.txt` | `$VP -c "import chardet" 2>/dev/null; echo $?` | 退出码非 0（批量卸载成功） |

> `$VP`：`/data/local/tmp/testvenv/bin/python`

**注**：C14（--allow-existing）、C15（--no-project）、C16（--system-site-packages）、C17（--prompt）仅测试 venv 创建参数，无额外功能状态可验证，由原测试脚本覆盖。

### 3.3 Group D: 项目管理（14 个）

| ID | 主命令 | 验证命令 | 验证逻辑 |
|----|--------|---------|---------|
| D1 | `init /data/local/tmp/testproj` | `ls /data/local/tmp/testproj/pyproject.toml` | 文件存在（退出码 0） |
| D2 | `lock` | `ls /data/local/tmp/testproj/uv.lock` | 锁文件存在 |
| D4 | `add requests` | `grep "requests" testproj/pyproject.toml` | 依赖写入 pyproject.toml |
| D6 | `remove requests` | `grep "requests" testproj/pyproject.toml; echo $?` | 退出码非 0（依赖已移除） |
| D4b | `add --dev pytest` | `grep "pytest" testproj/pyproject.toml` | dev 依赖写入 |
| D6b | `remove --dev pytest` | `grep "pytest" testproj/pyproject.toml; echo $?` | 退出码非 0（dev 依赖已移除） |
| D7 | `run python -c "print('hello from ohos')"` | —（输出即验证） | 输出包含 "hello from ohos" |
| D7b | `run --with requests python -c "import requests; print(requests.__version__)"` | —（输出即验证） | 输出匹配版本号 |
| D9 | `init --lib testproj_lib` | `ls testproj_lib/pyproject.toml` | lib 项目结构存在 |
| D10 | `init --script test_script.py` | `head -5 test_script.py` | 包含 PEP 723 metadata |
| D11 | `add --script test_script.py requests` | `grep "requests" test_script.py` | metadata 包含 requests |
| D14 | `init --app testproj_app` | `ls testproj_app/pyproject.toml` | app 项目结构存在 |
| D15 | `add --optional web flask` | `grep "flask" testproj/pyproject.toml` | 可选依赖写入 |
| D17 | `add --editable testproj_lib` | `grep "test-ohos-lib" testproj/pyproject.toml` | editable 依赖写入 |

**注**：D5/D5b/D8/D2b/D3b/D13/D16/D18/D19/D20/D21/D22 的验证通过命令本身的输出完成（如 tree 显示依赖树、export 输出依赖列表），无需额外验证命令。

### 3.4 Group E: Tool 管理（5 个）

| ID | 主命令 | 验证命令 | 验证逻辑 |
|----|--------|---------|---------|
| E1 | `tool install ruff` | `$(uv tool dir --bin)/ruff --version` | 退出码为 0，输出版本号 |
| E2 | `tool list` | `uv tool list \| grep "ruff"` | 列表包含 ruff |
| E4 | `tool uninstall ruff` | `uv tool list \| grep "ruff"` | 列表中不包含 ruff（退出码非 0） |
| E5 | `tool install black` | `$(uv tool dir --bin)/black --version` | 退出码为 0，输出版本号 |
| E5c | `tool uninstall black` | `uv tool list \| grep "black"` | 列表中不包含 black |

**注**：E3（tool run ruff --version）本身就是功能验证。

### 3.5 Group G: Build（3 个）

| ID | 主命令 | 验证命令 | 验证逻辑 |
|----|--------|---------|---------|
| G1 | `build --sdist --out-dir build_out` | `tar tzf build_out/*.tar.gz \| grep pyproject.toml` | sdist 包含项目文件 |
| G2 | `build --wheel --out-dir build_out` | `pip install build_out/*.whl` + `import test_ohos_build` | wheel 可安装且可 import |
| G3 | `build --out-dir build_out2` | `ls build_out2/*.tar.gz build_out2/*.whl` | 两种格式产物都存在 |

## 4. 测试执行流程

### 4.1 执行顺序

```
前置检查
  → 环境清理
  → Group B（Python 安装 + 验证 → 卸载）
  → Group C（venv 创建 + pip 操作 + 验证）
  → Group D（项目创建 + 依赖管理 + 验证）
  → Group E（Tool 安装/卸载 + 验证）
  → Group G（Build + 产物验证）
  → 最终清理
  → 生成报告
```

### 4.2 跳过策略

- B2 失败：跳过所有 B/C/D/G 组
- C1 失败：跳过所有 C 组验证
- D1 失败：跳过所有 D 组验证
- E1 失败：跳过所有 E 组验证

## 5. 报告格式

Markdown 格式，包含：
1. 测试摘要（PASS/PARTIAL/FAIL/SKIP 数量）
2. PARTIAL 用例诊断详情（主命令输出 + 验证命令 + 验证输出）
3. FAIL 用例详情
4. 全部用例详细记录

报告文件名：`ohos-uv-verify-report-YYYYMMDD_HHMMSS.md`

## 6. 脚本位置

```
ohos/verify-uv-ohos.sh
```

## 7. 运行方式

```bash
# 独立运行（自行准备环境）
bash ohos/verify-uv-ohos.sh --timeout 120

# 参数与原测试脚本一致
#   --uv-path PATH   设备上 uv 路径（默认 /data/local/tmp/uv）
#   --hdc PATH       hdc 路径（默认 hdc）
#   --timeout SECS   超时秒数（默认 120）
```
