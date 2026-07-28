# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "requests",
#   "chardet",
# ]
# ///
"""
OHOS uv 端到端功能验证脚本
通过 uv run 在设备上执行，验证 uv 的完整工具链是否正常工作。
"""

import sys
import os
import importlib
import platform
import subprocess
import tempfile

PASS = 0
FAIL = 0

def check(name: str, condition: bool, detail: str = ""):
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"  ✅ {name}")
    else:
        FAIL += 1
        print(f"  ❌ {name}" + (f" — {detail}" if detail else ""))


def section(title: str):
    print(f"\n{'='*50}")
    print(f"  {title}")
    print(f"{'='*50}")


# ====================================================================
# 1. Python 运行时验证
# ====================================================================
section("1. Python 运行时")

check("Python 可执行", True)
check(f"Python 版本 >= 3.12", sys.version_info >= (3, 12),
      f"当前: {sys.version}")
check("平台标识存在", len(sys.platform) > 0, f"platform={sys.platform}")
check(f"架构: {platform.machine()}", platform.machine() == "aarch64",
      f"期望 aarch64, 实际 {platform.machine()}")
check("解释器路径可读", os.path.exists(sys.executable),
      f"path={sys.executable}")

# 标准库验证
for mod in ["json", "pathlib", "urllib.request", "hashlib", "ssl", "sqlite3"]:
    try:
        importlib.import_module(mod)
        check(f"标准库 {mod}", True)
    except Exception as e:
        check(f"标准库 {mod}", False, str(e))

# ====================================================================
# 2. 第三方包验证（通过 PEP 723 内联依赖由 uv 自动安装）
# ====================================================================
section("2. 第三方包（uv 内联依赖注入）")

try:
    import requests
    check("import requests", True)
    check(f"requests 版本: {requests.__version__}", len(requests.__version__) > 0)
except Exception as e:
    check("import requests", False, str(e))

try:
    import chardet
    check("import chardet", True)
    check(f"chardet 版本: {chardet.__version__}", len(chardet.__version__) > 0)
except Exception as e:
    check("import chardet", False, str(e))

# 验证 requests 能实际发请求（使用国内镜像避免超时）
try:
    resp = requests.get("https://pypi.mirrors.ustc.edu.cn/simple/", timeout=10)
    check(f"HTTP 请求 pypi 镜像 (status={resp.status_code})", resp.status_code == 200)
except Exception as e:
    check("HTTP 请求 pypi 镜像", False, str(e)[:80])

# ====================================================================
# 3. 文件系统验证
# ====================================================================
section("3. 文件系统")

check("可写目录 /data/local/tmp 存在",
      os.path.isdir("/data/local/tmp"))

# 创建临时文件
try:
    fd, tmp_path = tempfile.mkstemp(dir="/data/local/tmp", prefix="uv_verify_")
    os.write(fd, b"hello from uv verify script")
    os.close(fd)
    content = open(tmp_path, "rb").read()
    os.unlink(tmp_path)
    check("临时文件读写", content == b"hello from uv verify script")
except Exception as e:
    check("临时文件读写", False, str(e)[:80])

# ====================================================================
# 4. SSL/TLS 验证
# ====================================================================
section("4. SSL/TLS")

try:
    import ssl
    check(f"SSL 模块可用", True)
    check(f"OpenSSL 版本: {ssl.OPENSSL_VERSION.split()[0]}",
          len(ssl.OPENSSL_VERSION) > 0)
except Exception as e:
    check("SSL 模块", False, str(e))

# ====================================================================
# 5. 子进程验证
# ====================================================================
section("5. 子进程")

try:
    result = subprocess.run(
        [sys.executable, "-c", "print('subprocess ok')"],
        capture_output=True, text=True, timeout=10
    )
    check("子进程执行", result.stdout.strip() == "subprocess ok",
          f"stdout={result.stdout.strip()!r}")
except Exception as e:
    check("子进程执行", False, str(e)[:80])

# ====================================================================
# 6. uv 自身验证
# ====================================================================
section("6. uv 工具链")

try:
    result = subprocess.run(
        ["uv", "--version"],
        capture_output=True, text=True, timeout=10
    )
    version = result.stdout.strip()
    check(f"uv 可用: {version}", "uv" in version)
except FileNotFoundError:
    # uv 可能不在 PATH 中，尝试常见路径
    for uv_path in ["/data/local/tmp/uv", "/data/local/tmp/.local/bin/uv"]:
        if os.path.exists(uv_path):
            try:
                result = subprocess.run(
                    [uv_path, "--version"],
                    capture_output=True, text=True, timeout=10
                )
                version = result.stdout.strip()
                check(f"uv 可用 ({uv_path}): {version}", "uv" in version)
                break
            except Exception:
                pass
    else:
        check("uv 可用", False, "uv 不在 PATH 且常见路径未找到")
except Exception as e:
    check("uv 可用", False, str(e)[:80])

# ====================================================================
# 总结
# ====================================================================
print(f"\n{'='*50}")
total = PASS + FAIL
print(f"  验证完成: {PASS}/{total} 通过")
if FAIL > 0:
    print(f"  ❌ {FAIL} 项失败")
    sys.exit(1)
else:
    print(f"  ✅ 全部通过！OHOS uv 工具链工作正常")
    sys.exit(0)
