#!/bin/bash
# 运行单元测试（自建测试执行器，适用于无 XCTest 的 Apple CLT 环境）。
set -euo pipefail
cd "$(dirname "$0")/.."
exec swift run DeskStickersSelfTest
