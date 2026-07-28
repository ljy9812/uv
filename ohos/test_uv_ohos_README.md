# OHOS uv Python 测试脚本使用说明

## 文件位置

```
/storage/Users/currentUser/uv/uv/ohos/test_uv_ohos.py
```

## 运行方式

### 完整测试模式（推荐）
测试全部 107 个用例，包括重复下载验证：

```bash
cd /storage/Users/currentUser/uv/uv/ohos/
uv run test_uv_ohos.py
```

### 快速模式
跳过重复下载的用例（B9/E7/E8/D15/D22），约节省 50% 时间：

```bash
uv run test_uv_ohos.py --fast
```

### 自定义参数

```bash
# 指定超时时间（默认 60 秒）
uv run test_uv_ohos.py --timeout 90

# 指定 hdc 路径
uv run test_uv_ohos.py --hdc /path/to/hdc

# 指定设备上 uv 路径（默认 /data/local/tmp/uv）
uv run test_uv_ohos.py --uv-path /data/local/tmp/uv

# 组合使用
uv run test_uv_ohos.py --fast --timeout 90 --hdc /usr/local/bin/hdc
```

## 测试覆盖

| 模块 | 用例数 | 说明 |
|------|--------|------|
| A. 基础命令 | 19 | 版本、帮助、目录查询、self update |
| B. Python 管理 | 9 | 安装、卸载、查询、列表、pin、重装 |
| C. 虚拟环境 + pip | 27 | venv 创建、pip install/list/show/freeze/check/tree |
| D. 项目管理 | 28 | init/lock/sync/add/remove/run/export/build/format |
| E. Tool 管理 | 12 | install/run/upgrade/uninstall/list |
| F. Cache 管理 | 2 | prune/clean |
| G. Build | 3 | sdist/wheel/all |
| H. Auth 管理 | 3 | login/logout/token 帮助 |
| I. Workspace | 3 | dir/list/metadata |
| J. Publish | 1 | publish 帮助 |
| **总计** | **107** | |

## 依赖跳过策略

当关键测试失败时，后续依赖测试自动跳过：

- **B2 失败**（Python 安装）：跳过所有 C/D/G 组（约 58 个用例）
- **C1 失败**（venv 创建）：跳过所有 pip 测试（约 18 个用例）
- **D1 失败**（项目初始化）：跳过所有项目管理测试及 Group I（约 27 个用例）
- **E1 失败**（tool install）：跳过 E2-E10（约 11 个用例）

## 快速模式跳过用例

`--fast` 模式额外跳过以下重复下载用例：

- **B9**：Python reinstall（重复下载 Python 3.12）
- **E7**：tool run ruff@0.3.0（重复下载 ruff）
- **E8**：tool install --from ruff（重复下载 ruff）
- **D15**：add --optional flask（下载 Flask + 依赖）
- **D22**：add --raw httpx（下载 httpx）

## 测试报告

测试完成后自动生成 Markdown 报告：

```
ohos-uv-test-report-YYYYMMDD_HHMMSS.md
```

报告包含：
- 测试摘要（时间、版本、通过率）
- 失败用例详情（命令、错误、输出）
- 跳过用例列表（跳过原因）
- 完整结果表格（每个用例的状态和耗时）

## 前置条件

1. **hdc 工具**已安装并在 PATH 中
2. **OHOS 设备**已通过 USB 连接
3. **uv 二进制**已部署到设备 `/data/local/tmp/uv`
4. **设备网络**可访问互联网（下载 Python、pip 包）
5. **镜像源**已配置（USTC PyPI + ghfast.top Python Build）

## 环境变量

脚本自动配置以下环境变量：

```bash
MSYS_NO_PATHCONV=1                    # Git Bash 路径兼容
MSYS2_ARG_CONV_EXCL="*"               # MSYS2 路径转换禁用
UV_CACHE_DIR=/data/local/tmp/.uv-cache
UV_INDEX_URL=https://pypi.mirrors.ustc.edu.cn/simple/
UV_PYTHON_INSTALL_MIRROR=https://ghfast.top/https://github.com/indygreg/python-build-standalone/releases/download
```

## 示例输出

```
============================================================
  OHOS uv 功能验证测试
  设备: hdc | uv: /data/local/tmp/uv
  超时: 60s | 快速模式: 否
  时间: 2026-06-17 14:30:00
============================================================

═══ Group A: 基础命令 ═══
  ✅ [A1] 版本号 (0.5s)
  ✅ [A2] 帮助信息 (0.3s)
  ✅ [A3a] pip 帮助 (0.4s)
  ...

═══ Group B: Python 管理 ═══
  ✅ [B1] Python 列表 (1.2s)
  ✅ [B2] 安装 Python 3.12 (45.3s)
  ...

============================================================
  测试完成！总耗时: 342.5s
  总计: 107 | 通过: 106 | 失败: 1 | 跳过: 0
  通过率: 99.1%
  报告: /storage/Users/currentUser/uv/uv/ohos/ohos-uv-test-report-20260617_143542.md
============================================================
```

## 故障排查

### hdc 连接失败
```bash
hdc list targets                    # 检查设备连接
hdc shell "echo test"               # 测试 shell 执行
```

### uv 命令超时
增加超时时间：
```bash
uv run test_uv_ohos.py --timeout 120
```

### 网络下载慢
确认镜像源配置正确，或手动设置：
```bash
export UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple/
```

### 查看单个测试
修改脚本，注释掉不需要的测试组，或添加调试输出。

## 脚本特性

- ✅ 纯 Python 标准库，无额外依赖
- ✅ 支持 `uv run` 直接运行（PEP 723 内联元数据）
- ✅ 自动依赖管理和跳过策略
- ✅ 详细的时间统计和错误信息
- ✅ Markdown 格式测试报告
- ✅ 自动清理设备临时文件
- ✅ 支持快速模式跳过重复下载

## 版本历史

- **v1.0** (2026-06-17): 初始版本，覆盖全部 107 个用例
