#!/bin/sh
# 在鸿蒙 PC 上跑 uv 全量测试（前台，输出由 hdc shell 流回 host）
#
# NOTE: 不要用 `uv run test_uv_ohos.py` 跑测试脚本。
# 父 `uv run` 进程会全程持有 cache 锁，导致测试内的 `uv cache prune` / `cache clean`
# (F1/F2) 阻塞在 "Cache is currently in-use, waiting for other uv processes
# to finish"，等到测试 60s 超时被杀 → 误判 FAIL。0.11.31 的 cache 操作遇锁会等待，
# 旧版 uv 无此阻塞故 sb-fy-sb 未暴露。
# 测试脚本只用标准库，用裸 python3 跑即可；子进程 uv 不会继承/持有父锁。
cd /data/local/tmp
export PATH=/data/local/tmp/uvinstdir/cpython-3.12.13-linux-aarch64-musl/bin:/data/local/tmp:$PATH
export HOME=/data/local/tmp
python3 test_uv_ohos.py "$@"
