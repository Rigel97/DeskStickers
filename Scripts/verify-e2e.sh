#!/bin/bash
# 一键端到端回归：隔离 HOME 启动应用 → 驱动完整业务流 → 断言窗口/像素/持久化。
# 用法: Scripts/verify-e2e.sh
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="/tmp/deskstickers-e2e"
BIN="$(pwd)/.build/release/DeskStickers"

echo "==> 构建 release"
swift build -c release

echo "==> 编译验证工具"
mkdir -p "$WORK"
swiftc -O Scripts/verification/dnctl.swift -o "$WORK/dnctl"
swiftc -O Scripts/verification/pixelprobe.swift -o "$WORK/pixelprobe"
swiftc -O Scripts/verification/windowlist.swift -o "$WORK/windowlist"

echo "==> 隔离状态目录启动应用 (--automation --state-dir)"
rm -rf "$WORK/home" "$WORK/state-home" "$WORK/app.log" "$WORK/state.json"
mkdir -p "$WORK/home"
HOME="$WORK/home" "$BIN" --automation --state-dir "$WORK/state-home" > "$WORK/app.log" 2>&1 &
echo $! > "$WORK/app.pid"
sleep 2

STATUS=0
E2E_WORK="$WORK" DESKSTICKERS_BIN="$BIN" E2E_HOME="$WORK/home" E2E_STATE_DIR="$WORK/state-home" \
    python3 Scripts/verification/e2e_verify.py || STATUS=$?

kill "$(cat "$WORK/app.pid")" 2>/dev/null || true
if [ $STATUS -eq 0 ]; then
    echo "端到端回归通过 ✅"
else
    echo "端到端回归失败 ❌（日志: $WORK/app.log）"
fi
exit $STATUS
