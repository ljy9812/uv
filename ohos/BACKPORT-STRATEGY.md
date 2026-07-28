# OHOS 适配回合上游策略与提交方案

> 仓库：`ljy9812/uv`（`Eulogizethesun/uv` 的 fork，基线 uv v0.11.31，HEAD `b7fdec6` 与上游 main 一致）
> 目标：把 OHOS/HarmonyOS aarch64 适配回合到 `Eulogizethesun/uv`，使其成为官方支持 OHOS 的上游。
> 参考实现 `sb-fy-sb/uv` 把所有工作压成 1 个 mega-commit；ljy9812/uv 已拆成原子提交 C0–C12。
> 原则：先忠实移植（C1–C12，含 sb-fy-sb 已知外溢），再追加「后修复」提交（C13–C16）消除外溢 + 防御性修复，最后按主题拆 PR 回合上游。
>
> 本文已经过技术审计并修订（审计要点见文末附录）。

---

## 一、ljy9812/uv 现状

- `main` = 上游 0.11.31 干净基线 + OHOS 源码适配（C0–C12，13 个提交）。
- `ohos-release` = main + 发版工程（CI release workflow、签名材料、install/setup 脚本、测试套件、交叉编译配置）。

### C0–C12 提交清单

| C# | 主题 | 文件 | 守卫 | 非 OHOS host 影响 |
|----|------|------|------|-------------------|
| C0 | ci(ohos): bootstrap 交叉编译 CI | `.github/workflows/ohos-build.yml`、`ohos-windows-toolchain.cmake`、`uv-performance-memory-allocator/Cargo.toml`+`src/lib.rs` | 无 cfg；CI/runner | 无（CI 不在 host 跑） |
| C1 | feat(platform-tags): Ohos 枚举变体 | `crates/uv-platform-tags/src/platform_tag.rs` | 枚举增量 | 无（纯枚举 + Display/FromStr） |
| C2 | feat(platform-tags): 为 musllinux 发 Ohos 标签 | `crates/uv-platform-tags/src/tags.rs` | **无 cfg** | **有外溢**：任何 musl host 都发 ohos 标签 → C13 消除 |
| C3 | feat(distribution): Ohos wheel 继承 linux markers | `crates/uv-distribution-types/src/prioritized_distribution.rs` | match 臂扩展 | **潜在外溢**：Ohos wheel implied `sys_platform=="linux"` → C13 在平台标签兼容性过滤阶段挡掉 ohos wheel，使其不进入 marker 求值（见风险栏） |
| C4 | feat(platform): 检测 OHOS musl 版本 | `crates/uv-platform/src/libc.rs` | 无 cfg，运行时读文件 | **微弱外溢**：每个 Linux host 额外 2 次文件探测（<1ms，返回 None）；可选 `#[cfg(target_env="ohos")]` 门起调用（见 C13 注） |
| C5 | feat(python): 统一 Python 子进程启动 helper | `crates/uv-python/src/interpreter.rs` | 无 cfg | 无（非 OHOS 等价 `Command::new`，已核实） |
| C6 | refactor(run): 改用 python_command_tokio | `crates/uv/src/commands/project/run.rs`、`crates/uv-installer/src/compile.rs` | 无 cfg | 无（行为等价）；**但 cargo fmt 不过** → C16 修 |
| C7 | feat(build-frontend): PEP517 平台桩 | `crates/uv-build-frontend/src/lib.rs` | `#[cfg(target_env="ohos")]` 双臂 | 无（stub 空串，formatdoc 字节一致，已核实） |
| C8 | feat(uv): OHOS 重定向 HOME + 预设 UV_LIBC | `crates/uv/src/lib.rs` | `#[cfg(target_env="ohos")]` | 无（纯 cfg）；复用上游既有 `pub unsafe fn main` + `#[allow(unsafe_code)]`（**非 C8 引入**），在其中加两处 `unsafe { set_var }` + SAFETY 注释（见 PR-4 风险） |
| C9 | feat(python): 识别 OHOS 解释器 | `crates/uv-python/python/get_interpreter_info.py`、`packaging/_musllinux.py` | Python，无 cfg | **有外溢**：musl fallback（regex/默认 1.2）对非 OHOS 也生效 → C14 消除。注：`_musllinux.py` 是 vendored 自 pypa/packaging 的文件 |
| C10 | feat(distribution): Python 下载指向 OHOS cpython 3.12.9 | `crates/uv-python/download-metadata.json` | 无 cfg，覆盖全表 | **破坏性**：删 89927 行 + 版本解析泄漏（见 PR-6） |
| C11 | ci(ohos): json 变更触发 CI | `.github/workflows/ohos-build.yml` | — | 无 |
| C12 | docs(ohos): 源码适配说明 | `ohos/OHOS-SOURCE-ADAPTATIONS.md` | — | 无 |

### 外溢来源确认

C2/C9 的外溢**来自 sb-fy-sb 原版**（sb-fy-sb `tags.rs:592` 同样无条件 `push(Ohos)`；`_musllinux.py:64-89` 同样 fallback），ljy9812/uv 忠实移植，非新引入。C13/C14 用于消除之。

---

## 二、main 上新增的「后修复」提交（4 笔）

保持 C1–C12 不动，追加：

### C13 — `fix(platform-tags): gate Ohos tag emission to OHOS builds`
- **文件**：`crates/uv-platform-tags/src/tags.rs`
- **改动**：C2 的 `platform_tags.push(PlatformTag::Ohos { arch })`（行 631）用 `#[cfg(target_env = "ohos")]` 属性包进块，编译期消除（比 `cfg!` 宏更干净，非 OHOS 二进制不含该 push）：
  ```rust
  #[cfg(target_env = "ohos")]
  { platform_tags.push(PlatformTag::Ohos { arch }); }
  ```
- **C3 影响**：C3 的 match 臂**非死代码**——`PlatformTag::Ohos` 仍由 `FromStr`（`platform_tag.rs:602`）解析 `ohos_<arch>` wheel 文件名时构造，故臂编译可达、无 dead-code 警告。但非 OHOS host 因 C13 不再产生 Ohos 兼容标签，ohos wheel 在平台标签兼容性过滤阶段即被剔除，不进入 marker 求值 → C3 外溢被 C13 间接阻断。
- **C4 关联**：同理把 `detect_linux_libc`/`detect_musl_version` 里的 `detect_ohos_musl_version()` 调用（`libc.rs:157`、`:276`）用 `#[cfg(target_env = "ohos")]` 门起，消除非 OHOS 的 2 次文件探测。**必须同时** `#[cfg(target_env = "ohos")]` 函数定义本身（`libc.rs:289`）及其内部 `regex!`，否则非 OHOS 上函数体变死代码触发 `dead_code` 警告。建议同笔做。
- **验证**：`cargo check -p uv-platform-tags -p uv-platform`；`cargo fmt --check`；新增单测：OHOS build 断言 musllinux 标签序列含 Ohos（`#[cfg(target_env="ohos")]` 测），非 OHOS build 该测 cfg 掉。

### C14 — `fix(python): scope musl version fallback to OHOS`
- **文件**：`crates/uv-python/python/get_interpreter_info.py`（新增 monkey-patch wrapper，**不改** `packaging/_musllinux.py`）
- **判据（实测确认）**：OHOS 上 `sys.platform == "linux"`（**不能**用它！），`sysconfig.get_platform() == "harmonyos-HongMeng Kernel 1.12.0-aarch64"`，`platform.system() == "HarmonyOS"`。与 `get_interpreter_info.py:459-460` 一致用 `sysconfig.get_platform()`。
- **改动（monkey-patch wrapper，不改 vendored 源）**：**C9 对 `packaging/_musllinux.py` 的 hunk 不回合**（避免改 vendored 自 pypa/packaging 的文件、避免 re-vendor 漂移）；改为在 uv 侧加 wrapper 调用 packaging 原函数，失败且 OHOS 时走 fallback：
  ```python
  # uv 侧 wrapper（uv 自己的文件，非 vendored）
  def _get_musl_version_ohos_aware(executable):
      # 先调 packaging 原函数（上游行为：loader 直接调用 + 解析）
      version = packaging._musllinux._get_musl_version(executable)
      if version is not None:
          return version
      # 仅 OHOS 启用 fallback
      import sysconfig
      if sysconfig.get_platform().startswith(("ohos", "harmonyos")):
          # Fallback 1: OHOS 版本文件
          # Fallback 2: regex 扫 loader
          # Last resort: 默认 1.2
          ...
          return _MuslVersion(major=1, minor=2)  # 或上面命中
      return None  # 非 OHOS 保持上游原行为（loader 失败即 None）
  ```
  C9 的 `get_interpreter_info.py` 改动（uv 自己的文件）照常回合。
- **效果**：非 OHOS 回到上游行为，零外溢；vendored `_musllinux.py` 不动。
- **测试前置（硬性）**：wrapper 与 `detect_ohos_musl_version` 现为**硬编码路径**（`libc.rs:295-296`，wrapper 内版本文件路径），无法直接测。**必须先重构**两者接受可选 path 参数（或 env override），才能在 `crates/uv-python` 集成测里 tempdir 造假版本文件、断言 OHOS 守卫下走 fallback / 非 OHOS 返回 None。此重构是 C14 的一部分，非可选。

### C15 — `fix(virtualenv): copy fallback when symlink denied (F1)`
- **文件**：`crates/uv-fs/src/lib.rs`、`crates/uv-virtualenv/src/virtualenv.rs`
- **根因**：`replace_symlink`（`uv-fs/src/lib.rs:209-226`）只处理 `AlreadyExists`，对 `EPERM/EACCES` 直接 `Err`；`virtualenv.rs` 7 处 python 链接 + lib64 链接无条件调用。
- **设计（审计后重做）**：**不在 `replace_symlink` 内透明回退**（unix 块内 7 处 `replace_symlink`，其中 6 处 `src="python"` 是相对符号名，`copy("python", dst)` 会 `NotFound`）。改为在 `virtualenv.rs` 侧 `#[cfg(target_env = "ohos")]` 分支统一走 copy 模式：
  - **python 链接**（`virtualenv.rs:273-310`，7 处）：OHOS 下对所有 7 个目标名（`python`、`python3`、`python3.12` 及 gil_disabled/pypy/graalpy 变体）统一调 `replace_symlink_or_copy(executable_target, dst, true)`——**先试 symlink；`AlreadyExists` 走 temp-file+rename（原 `replace_symlink` 语义，幂等重建兼容）；仅 `EPERM/EACCES` 回退 `fs_err::copy(executable_target, dst)`**。用 `executable_target`（真实解释器路径）作 src，避免相对名 `NotFound`。copy-mode venv，`pyvenv.cfg` 的 `home=`（`virtualenv.rs:~523`）指向原解释器，CPython 可识别。
  - **lib64 链接**（`virtualenv.rs:587-599`，用 `fs_err::os::unix::fs::symlink` 直调，不经 `replace_symlink`）：OHOS 下若 symlink 失败（EPERM/EACCES），**跳过并 warn**（lib64 为 multilib 可选，aarch64 通常不需要）；如需严格可改 `create_dir_all`+copy lib 内容。
  - **uv-fs 侧**：抽可测函数 `replace_symlink_or_copy(src: &Path, dst: &Path, allow_copy: bool)`——`allow_copy=true` 时先 symlink 失败再 `fs_err::copy(src, dst)`；`allow_copy=false` 走原 `replace_symlink` 语义。OHOS 分支与单测共用此函数（单一可测路径）。非 OHOS 不编译 OHOS 分支，行为不变。
- **效果**：symlink 受限 fs 上 venv 仍可用；非 OHOS 不编译 OHOS 分支，零影响。
- **测试**：单测 `replace_symlink_or_copy`——tempdir + 普通文件 src，`allow_copy=true` 断言 dst 是副本（绕过 symlink 失败模拟）；`insta` snapshot 测 `pyvenv.cfg` 含 `home=`。`cfg!` 守卫的 OHOS 分支在非 OHOS host 不可达，故可测逻辑必须抽到 `allow_copy` 参数的纯函数里（满足 AGENTS.md 测试要求）。
- **验证**：`cargo check -p uv-fs -p uv-virtualenv`；`cargo test -p uv-fs -p uv-virtualenv`。
- **本设备 F1 不触发**：root+hmdfs 下 symlink 可用；C15 为其它受限 fs/域的防御性修复，有效性靠单测保证。

### C16 — `style: cargo fmt --all`
- **文件**：`crates/uv/src/commands/project/run.rs`（C6 的 7 处超长行折行）等 fmt 落差。
- **效果**：`cargo fmt --all --check` 通过。

> C13/C14/C15 全部 cfg/平台守卫，非 OHOS host 零行为影响；每笔 host `cargo check` + `cargo fmt --check` 必过。C14/C15 含测试计划（AGENTS.md 合规）。

---

## 三、上游回合 PR 序列（7 笔，按依赖顺序）

每个 PR 自洽可独立 review。合入顺序 PR-1 → PR-2 → PR-3 → PR-4 → PR-5 → PR-6 → PR-7。

### PR-1 — OHOS 平台标签
- **含提交**：C1 + C2 + C13(cfg) + C3（+ C4 的 cfg 门，若同笔做）
- **文件**：`platform_tag.rs`、`tags.rs`、`prioritized_distribution.rs`、`libc.rs`（C4 cfg 门，可选）
- **测试**：`uv-platform-tags` 单测——`ohos_aarch64` 解析、implied markers；OHOS build 断言含 Ohos 标签
- **非 OHOS 影响**：无（C13 守卫后 push 编译期消除；C4 cfg 门消除文件探测）
- **风险**：C3 implied marker = `sys_platform=="linux"`，使 ohos wheel 对 linux host 理论可见；依赖 C13 在平台标签兼容性过滤阶段剔除 ohos wheel。需在 PR 描述说明，并确认 uv 的 wheel 选择管线先按 platform tag 过滤再求 marker。

### PR-2 — OHOS musl libc 检测
- **含提交**：C4 + C9 + C14(platform)
- **文件**：`libc.rs`、`get_interpreter_info.py`（+ C14 wrapper，**不改** `_musllinux.py`）
- **非 OHOS 影响**：无（C14 守卫后非 OHOS 回上游行为）
- **注**：`_musllinux.py` 是 vendored 文件——**PR-2 用 monkey-patch wrapper（见 C14），不改 vendored 源**；无需向 pypa/packaging 提 PR。C9 的 `get_interpreter_info.py` 改动（uv 自己的文件）照常回合。
- **测试**：集成测造假日志版本文件，验证 OHOS 守卫下走 fallback、非 OHOS 返回 None

### PR-3 — 统一 Python 子进程启动 + PEP517 桩
- **含提交**：C5 + C6(含 C16 fmt) + C7
- **文件**：`interpreter.rs`、`run.rs`、`compile.rs`、`uv-build-frontend/src/lib.rs`
- **非 OHOS 影响**：无（helper 等价 `Command::new`，已核实；stub 空串字节一致，已核实）

### PR-4 — OHOS 运行时环境重定向
- **含提交**：C8
- **文件**：`crates/uv/src/lib.rs`
- **非 OHOS 影响**：无（纯 cfg）
- **风险**：C8 复用上游既有的 `pub unsafe fn main` + `#[allow(unsafe_code)]`（上游已有，**非 C8 引入**），在其中加两处 `unsafe { set_var }` + SAFETY 注释（已有）。`#[allow]`→`#[expect]` 属上游既有清理项，**不属 C8 回合范围**；C8 自身的 unsafe 落在已声明 unsafe 的入口且有 SAFETY，可接受。

### PR-5 — venv symlink copy 回退（F1）
- **含提交**：C15
- **文件**：`uv-fs/src/lib.rs`、`virtualenv.rs`
- **非 OHOS 影响**：无（cfg 守卫；可测逻辑抽 `allow_copy` 参数）
- **独立**：不依赖 C1–C9
- **测试**：`replace_symlink_or_copy` 单测 + `pyvenv.cfg` snapshot

### PR-6 — Python 下载元数据
- **含提交**：C10 改写（**不直接 cherry-pick 原版**）
- **文件**：`crates/uv-python/download-metadata.json`（+ 可能 `build.rs`）
- **问题（版本解析泄漏）**：上游 `b7fdec6` 的 `download-metadata.json` **不含** `cpython-3.12.9-linux-aarch64-musl` 键（aarch64-musl 只到 3.12.11/12/13），故无「同键冲突」。真问题是：若把 OHOS 条目追加进上游全表，非 OHOS 的 aarch64-musl host 上 `uv python install 3.12.9` 会命中这条 OHOS 镜像 URL（条目 `os=linux/libc=musl/arch=aarch64` 对非 OHOS host 同样匹配）→ 误装 OHOS 专属构建。
- **推荐方案（c）**：**C10 不回合上游**；OHOS 用户通过 `UV_PYTHON_DOWNLOADS_JSON_URL` 环境变量指向 fork 自建的 OHOS metadata URL（fork 维护 `download-metadata-ohos.json`）。零侵入上游。**注**：该 env var 是**整体替换**内置表（`downloads.rs:1038-1056` 为 if-else 非 merge），OHOS 设备将失去其它平台 cpython 下载能力——对 OHOS 单用途设备可接受。
- **备选（b）**：保留上游全表 + 新增 `download-metadata-ohos.json`（OHOS 专属键如 `cpython-3.12.9-linux-aarch64-musl-ohos`），`build.rs` 在 `#[cfg(target_env="ohos")]` 下 merge。需扩展键解析器识别 build 后缀。
- **建议**：上游用（c）；fork 自用可继续（b）或原 C10。

### PR-7 — 文档
- **含提交**：C12
- **文件**：`ohos/OHOS-SOURCE-ADAPTATIONS.md`（或并入 PR-1）

---

## 四、不进上游 main（留 fork ohos-release 分支）

| 内容 | 理由 |
|---|---|
| C0 + C11（ohos-build.yml CI） | 依赖私有 self-hosted runner/代理/`D:\ohos\sdk`；要回合需参数化（secrets/vars）+ 默认 disabled |
| ohos-release.yml、签名 `ohos-self-sign.p12` | 发版产物；p12 是 sb-fy-sb 自签，无公信力 |
| install-uv-ohos.sh、setup-uv-ohos.sh、test_uv_ohos.py、run_test.sh | fork 特定；如上游要官方支持，单独 PR 到 `scripts/ohos/`，先过 ruff+prettier |

---

## 五、操作顺序

1. 在 `ljy9812/uv` main 上依次提交 C13 → C14 → C15 → C16，每笔 `cargo check` + `cargo fmt --check` + `cargo test`。
2. clone `Eulogizethesun/uv`，从 `main`（`b7fdec6`）按序开 7 个主题分支。
3. 每个 PR cherry-pick 对应提交（PR-1: C1→C2→C13→C3；PR-2: C4→C9→C14；PR-3: C5→C6→C16→C7；PR-4: C8；PR-5: C15；PR-6: 方案 c 不 cherry-pick，文档说明用 `UV_PYTHON_DOWNLOADS_JSON_URL`；PR-7: C12）。
4. 每 PR 跑上游 CI（fmt/clippy/test）+ OHOS 交叉编译验证。
5. 发版工程留 fork `ohos-release`，不回合 main。

---

## 六、风险

| 风险 | 处理 |
|---|---|
| C10 外部镜像依赖（sb-fy-sb.github.io）+ 版本解析泄漏 | 上游用方案（c）`UV_PYTHON_DOWNLOADS_JSON_URL`；fork 自建镜像 |
| 自签证书 `ohos-self-sign.p12` | 不回合 main；fork 自用 |
| self-hosted runner 公仓安全 | C0 已加 fork-PR 守卫；回合时保留并默认维护者触发 |
| 非 cfg 行为外溢（C2/C9） | C13/C14 消除 |
| C3 implied marker = linux | 依赖 C13 平台标签过滤剔除 ohos wheel；PR-1 需说明并验证选择管线 |
| C4 微弱外溢（2 次文件探测） | C13 同笔 `#[cfg]` 门起 `detect_ohos_musl_version` 调用 |
| C8 unsafe / `#[allow]` | C8 复用上游既有 unsafe fn + allow（非新增）；`allow→expect` 属上游清理项，非 C8 范围 |
| C9 vendored `_musllinux.py` | PR-2 用 monkey-patch wrapper（C14），不改 vendored 源 |
| fmt/lint 红 | C16 清理；ohos 脚本回合时过 ruff+prettier |
| F1 本设备不触发 | C15 有效性靠单测（`allow_copy` 抽函数）保证 |

---

## 附录：审计修订记录

- **R1 审计**发现 3 阻塞 + 3 应修 + 若干建议，已全部并入本版：
  1. 🔴 C14 判据错（`sys.platform` 实测为 `"linux"`）→ 改 `sysconfig.get_platform()`（实测 `"harmonyos-..."`）。
  2. 🔴 C10 同键冲突 → 上游改方案（c）`UV_PYTHON_DOWNLOADS_JSON_URL`。
  3. 🔴 C15 copy 回退对 4/5 处 `src="python"` 会 `NotFound` → 重设计为 `virtualenv.rs` 侧 OHOS 分支 copy `executable_target` 到各名。
  4. 🟠 C15 lib64 不经 `replace_symlink` → 单独处理（跳过+warn）。
  5. 🟠 C15 `AlreadyExists` 分支 OHOS 下仍炸 → OHOS 分支整体 copy，绕过 AlreadyExists 逻辑。
  6. 🟠 C14/C15 缺测试 → 抽 `replace_symlink_or_copy(allow_copy)` 可测函数 + 集成测。
  7. 🟠 C8 unsafe 违反 AGENTS.md → PR-4 风险标注，改 `#[expect]`。
  8. 🟡 C3「死代码」表述错 → 改为「FromStr 可达、runtime 被 C13 阻断」。
  9. 🟡 C4「零外溢」→ 改「微弱外溢」，C13 同笔 cfg 门起。
  10. 🟡 C9 vendored patch → PR-2 说明。
  11. 🟡 行号修正（`home=` ~523，lib64 ~587-599）。

- **R2 审计**：无阻塞，3 🟠 + 6 🟡，已全部并入：
  1. 🟠 C10「同键冲突」事实错（上游无 3.12.9-aarch64-musl 键）→ 改「版本解析泄漏」；方案 c 仍推荐。
  2. 🟠 C15 OHOS 分支「直接 copy」vs「调 `replace_symlink_or_copy(..,true)`」矛盾 → 统一为对所有 7 名调 `replace_symlink_or_copy(executable_target, dst, true)`。
  3. 🟠 C8 `#[allow(unsafe_code)]` 归因偏重（上游既有，非 C8 引入）→ 改「复用上游 unsafe fn，allow→expect 属上游清理项」。
  4. 🟡 C14 测试：硬编码路径不可测 → 把「重构接受可选 path 参数」列为 C14 **硬前置**。
  5. 🟡 C13 C4 cfg 门：函数定义须一并 cfg（否则 dead_code）→ 已补。
  6. 🟡 C14 伪代码省略 loader 调用段 → 已补 `subprocess.run([ld])` + `_parse_musl_version`。
  7. 🟡 C14 vendored：选定 monkey-patch 包装层（避免 vendor 漂移）。
  8. 🟡 C15 计数「5 处中 4 处」→ 「7 处中 6 处用相对名 `"python"`」。
  9. 🟡 C2 行号 633 → 631。
  10. 🟡 PR-6 补注 env var 整体替换内置表，OHOS 设备失去其它平台下载。

- **R3 审计**：无 🔴，2 🟠 + 3 🟡，已全部并入：
  1. 🟠 C10 PR-6 删除残留的「键冲突问题」旧错误段，并入「版本解析泄漏」单一叙述。
  2. 🟠 C14 伪代码改写为 monkey-patch wrapper 形态（uv 侧 `_get_musl_version_ohos_aware`），明确 C9 的 `_musllinux.py` hunk 不回合、由 C14 wrapper 取代。
  3. 🟡 C15 根因「5 处」→「7 处 python 链接」。
  4. 🟡 C15 `replace_symlink_or_copy` 语义明确：`AlreadyExists` 走 temp-file+rename（原语义），仅 `EPERM/EACCES` 回退 copy。
  5. 🟡 PR-2/风险栏同步 monkey-patch 选定（不改 vendored 源，无需提 pypa PR）。

- **R4 审计**：**可定稿入库**。无 🟠/🔴。仅 2 处 🟡 字段残留（C14 文件字段、PR-2 文件列表仍写 `_musllinux.py`），已修正为 wrapper 实际文件（`get_interpreter_info.py` + 新 wrapper，不改 vendored 源）。R1–R3 全部阻塞与应修项已落实，无自相矛盾、无新引入技术问题。
