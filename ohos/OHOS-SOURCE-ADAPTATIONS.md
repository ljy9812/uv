# uv OHOS 源码适配点清单

> 本文档列出 `ljy9812/uv` 相对于上游 `astral-sh/uv`（v0.11.31）的所有 Rust/Python 源码改动，用于 OHOS/HarmonyOS aarch64（`aarch64-unknown-linux-ohos`，musl libc）适配。
>
> 适配移植自 `sb-fy-sb/uv`，因基线差异（sb-fy-sb 基线 PR #19641，本仓 #20608）逐项对照 0.11.31 重新落位。每笔为独立原子提交，CI（`.github/workflows/ohos-build.yml`）交叉编译验证每笔可构建。
>
> 不含 CI workflow、安装脚本等非源码文件（见 `OHOS-README.md`）。

---

## 适配点与提交

| # | 提交 | 文件 | 内容 | 解决的问题 |
|---|------|------|------|-----------|
| 1 | `feat(platform-tags): add Ohos platform tag variant` | `crates/uv-platform-tags/src/platform_tag.rs` | 新增 `PlatformTag::Ohos { arch }` 变体；`pretty()`=`"OHOS"`、`Display`=`ohos_{arch}`、`FromStr` 解析 `ohos_` 前缀 | 识别 OHOS aarch64 wheel 标签 |
| 2 | `feat(platform-tags): emit Ohos tag for musllinux interpreters` | `crates/uv-platform-tags/src/tags.rs` | `compatible_tags()` 的 `Musllinux` 分支追加 `PlatformTag::Ohos` | musllinux aarch64 解释器可装 `ohos_aarch64` wheel |
| 3 | `feat(distribution): imply linux markers for Ohos wheels` | `crates/uv-distribution-types/src/prioritized_distribution.rs` | `implied_platform_markers()` 的 Linux 臂加 `PlatformTag::Ohos` | OHOS wheel 获得 `sys_platform=="linux"` marker |
| 4 | `feat(platform): detect OHOS musl libc version` | `crates/uv-platform/src/libc.rs` | 新增 `detect_ohos_musl_version()`（读 OHOS 版本文件，正则提 major.minor）；`detect_linux_libc()` 入口 fast path、`detect_musl_version()` 末尾 fallback | OHOS musl loader 不输出标准版本信息 |
| 5 | `feat(python): unify Python subprocess launch helpers` | `crates/uv-python/src/interpreter.rs` | 新增 `python_command` / `python_command_tokio` / `python_command_impl`；切换内部 `InterpreterInfo` 调用点 | 统一 Python 子进程启动方式，预留 OHOS 扩展点 |
| 6 | `refactor(run): launch Python via python_command_tokio` | `crates/uv/src/commands/project/run.rs` + `crates/uv-installer/src/compile.rs` | `as_command()` 7 处 + 字节码编译改用 `python_command_tokio`（entrypoint/pythonw/external 不动） | `uv run` / 字节码编译走统一启动 |
| 7 | `feat(build-frontend): inject OHOS platform stub for PEP 517` | `crates/uv-build-frontend/src/lib.rs` | `OHOS_PLATFORM_STUB` 常量（`cfg(target_env="ohos")` 把 `sysconfig.get_platform()` 的 `harmonyos`→`linux`）；注入 `backend_import()`；build 子进程改用 `python_command_tokio` | setuptools 等构建后端不认 `harmonyos` |
| 8 | `feat(uv): redirect HOME and preset UV_LIBC on OHOS` | `crates/uv/src/lib.rs` | `main()` 入口两段 `cfg(target_env="ohos")`：HOME 重定向到 `current_exe` 父目录；`UV_LIBC` 未设时置 `musl` | 根 fs 只读致 HOME 不可写；沙箱内 libc 检测失败 |
| 9 | `feat(python): recognize OHOS in interpreter detection` | `crates/uv-python/python/get_interpreter_info.py` + `packaging/_musllinux.py` | `harmonyos`/`ohos` 走 Linux 分支并跳过 glibc；`_get_musl_version()` 加 3 层 fallback（loader try/except→版本文件→二进制正则→默认 1.2） | 解释器信息获取 + musl 版本识别兼容 OHOS |
| 10 | （并入 bootstrap 提交）`ci(ohos): bootstrap OHOS aarch64 cross-compile pipeline` | `crates/uv-performance-memory-allocator/Cargo.toml` + `src/lib.rs` | jemalloc 的 `cfg(all(...))` 加 `not(target_env="ohos")` | jemalloc 在 OHOS musl 下 configure 失败（Windows 构建主机不认）；OHOS 落系统 allocator |
| 11 | `feat(distribution): point Python downloads at OHOS cpython 3.12.9` | `crates/uv-python/download-metadata.json` | 整体替换为单条 `cpython-3.12.9-linux-aarch64-musl`（指向 OHOS python 镜像） | 指向自建/沿用 Python 镜像 |

### 关于第 10 项（jemalloc）并入 bootstrap 的说明

clean 0.11.31 无法直接交叉编译到 OHOS——`tikv-jemalloc-sys` 的 `configure` 不认 Windows 构建主机（`x86_64-pc-win32`），构建在依赖阶段即失败。禁用 OHOS 上的 jemalloc（`not(target_env="ohos")`）是让基线能交叉编译的最小必要改动，因此与 CI bootstrap 提交一并合入，使第一笔 CI 验证即绿。该改动在非 OHOS 目标上是 no-op。`target_env="ohos"` 经 `rustc --target aarch64-unknown-linux-ohos --print cfg` 确认成立。

---

## 与 sb-fy-sb 的差异（工程层）

适配逻辑与 sb-fy-sb 一致，以下为落位/工程差异：
- **C4 正则**：sb-fy-sb 用 `LazyLock<Regex>` + `Regex::new`；本仓 0.11.31 的 `libc.rs` 用 `regex!` 宏习惯，故改用 `regex!`（免新增 import）。
- **C5/C6/C7 import 清理**：sb-fy-sb 切换到 `python_command*` 后遗留了 `unused import: Command` 警告；本仓顺手清掉（interpreter.rs / compile.rs / build-frontend）。
- **C10 并入 bootstrap**：见上节。
- **CI workflow**：基于 sb-fy-sb 的 `ohos-build.yml` 改写（SDK 路径 `D:\ohos/sdk`、代理 `7897`、`RUSTUP_TOOLCHAIN=stable-msvc` 覆盖坏掉的 1.97.1 钉版、fork-PR 安全守卫、debug 构建验编译+链接）。

## 回合上游

源码适配提交（C1–C9、C11）均为纯源码、原子、`cfg` 守卫或平台标签增量，可从 `main` 直接 cherry-pick 到上游 `Eulogizethesun/uv`。C0 bootstrap（含 CI 文件 + jemalloc 禁用）不应 cherry-pick（CI 文件属 fork 专属；jemalloc 禁用在非 OHOS 上游无意义）。
