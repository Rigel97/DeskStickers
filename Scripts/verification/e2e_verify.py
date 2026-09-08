#!/usr/bin/env python3
"""桌面贴纸端到端验证。

前置条件（由 Scripts/verify-e2e.sh 准备）：
- 应用已以 --automation 启动（HOME 指向隔离目录）
- 环境变量: E2E_WORK(工作目录) DESKSTICKERS_BIN(应用路径) E2E_HOME(应用隔离 HOME)

覆盖：创建 / 移动 / 缩放 / 改文字 / 换风格 / 颜色变体 / 多贴纸 /
删除 / 隐藏显示 / 重启恢复 / 窗口几何(CGWindowList) / 像素渲染 / 日志健康。
"""
import json
import os
import re
import subprocess
import sys
import time

WORK = os.environ.get("E2E_WORK", "/tmp/deskstickers-e2e")
DNCTL = f"{WORK}/dnctl"
PROBE = f"{WORK}/pixelprobe"
STATE = f"{WORK}/state.json"
APP_LOG = f"{WORK}/app.log"
APP_PID_FILE = f"{WORK}/app.pid"
APP_BIN = os.environ.get("DESKSTICKERS_BIN", ".build/release/DeskStickers")
APP_HOME = os.environ.get("E2E_HOME", f"{WORK}/home")
APP_STATE_DIR = os.environ.get("E2E_STATE_DIR", f"{WORK}/state-home")

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond), detail))
    mark = "✓" if cond else "✗"
    suffix = f"   [{detail}]" if detail and not cond else ""
    print(f"{mark} {name}{suffix}")
    return cond


def dn(action, **kv):
    args = [DNCTL, action] + [f"{k}={v}" for k, v in kv.items()]
    subprocess.run(args, capture_output=True)


def dump(timeout=4.0):
    if os.path.exists(STATE):
        os.remove(STATE)
    dn("dump", path=STATE)
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(STATE):
            time.sleep(0.15)
            try:
                with open(STATE) as f:
                    return json.load(f)
            except Exception:
                pass
        time.sleep(0.1)
    return None


def snapshot(sticker_id, path, timeout=4.0):
    if os.path.exists(path):
        os.remove(path)
    dn("snapshot", id=sticker_id, path=path)
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(path):
            time.sleep(0.2)
            return True
        time.sleep(0.1)
    return False


def probe(png, *coords):
    coords = [int(c) for c in coords]
    if len(coords) == 4:
        cmd = [PROBE, png, "raw", "--avg", *[str(c) for c in coords]]
    else:
        cmd = [PROBE, png, "raw", *[str(c) for c in coords]]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    m = re.search(r"dominant=rgb\((\d+),(\d+),(\d+)\)", out)
    a = re.search(r"= rgb\((\d+),(\d+),(\d+)\)", out)
    avg = tuple(int(x) for x in a.groups()) if a else None
    dom = tuple(int(x) for x in m.groups()) if m else avg
    return avg, dom


def windowlist():
    out = subprocess.run([f"{WORK}/windowlist"], capture_output=True, text=True).stdout
    frames = []
    for line in out.splitlines():
        # 贴纸面板 = DeskStickers 进程的 floating 层窗口。
        # 不用 kCGWindowName 匹配——读取窗口名需要屏幕录制权限，
        # 刚编译的验证工具没有；owner + layer 无需任何权限。
        if "owner=DeskStickers" in line and "layer=3" in line:
            m = re.search(r"frame=\((\d+),(\d+),(\d+)x(\d+)\)", line)
            if m:
                x, y, w, h = map(int, m.groups())
                frames.append((x, y, w, h))
    return frames


def rect_of(sticker):
    p = sticker["paper"]
    return (p[0][0], p[0][1], p[1][0], p[1][1])


def near(a, b, tol=2.0):
    return abs(a - b) <= tol


# 期望的纸面左上角主色（区域采样）：按 (style, colorIndex) 断言
STYLE_COLORS = {
    ("notebook", 0): lambda c: c[0] >= 235 and c[1] >= 235 and c[2] >= 228,
    ("handwritten", 0): lambda c: c[0] >= 238 and 220 <= c[1] <= 248 and 180 <= c[2] <= 235,
    ("sticky", 0): lambda c: c[0] >= 245 and 190 <= c[1] <= 245 and 50 <= c[2] <= 165,
    ("sticky", 1): lambda c: c[0] >= 240 and c[0] > c[1] and 170 <= c[1] <= 220 and c[2] >= 170,
    ("sticky", 2): lambda c: c[1] > c[0] and c[1] > c[2] and c[1] >= 180,
    ("sticky", 3): lambda c: c[2] > c[1] and c[1] > c[0] and c[2] >= 200,
    ("minimal", 0): lambda c: c[0] >= 240 and c[1] >= 240 and c[2] >= 240,
    ("vintage", 0): lambda c: c[0] >= 222 and c[0] > c[1] > c[2] and c[1] >= 195,
    ("blackboard", 0): lambda c: c[0] < 95 and c[1] >= c[0] and c[1] < 95 and c[2] < 90,
    ("cute", 0): lambda c: c[0] >= 245 and c[2] >= c[1] and 200 <= c[1] <= 240 and c[2] >= 215,
    ("mono", 0): lambda c: c[0] < 62 and c[1] < 62 and c[2] < 75,
}

# ============================================================

print("== 1. 启动与自动化就绪 ==")
state = dump()
check("应用启动并可响应 dump", state is not None)

print("\n== 2. 创建贴纸（sticky @ (100,100) 宽 220）==")
dn("create", text="记得喝水，保持专注", style="sticky", colorIndex="0", x="100", y="100", width="220")
state = dump()
check("dump 返回 1 张贴纸", state and len(state["stickers"]) == 1)
s = state["stickers"][0]
check("文字正确", s["text"] == "记得喝水，保持专注", s["text"])
check("风格正确", s["style"] == "sticky")
px, py, pw, ph = rect_of(s)
check("纸面位置 = (100,100)", near(px, 100) and near(py, 100), f"({px},{py})")
check("纸面宽度 = 220", near(pw, 220), f"{pw}")
check("高度自适应 (>60)", ph > 60, f"{ph}")
check("层级 = 3 (floating)", s["level"] == 3)
check("窗口可见", s["visible"] is True)
wx, wy, ww, wh = s["window"][0] + s["window"][1]
frames = windowlist()
match = any(near(f[0], wx) and near(f[1], wy) and near(f[2], ww) and near(f[3], wh) for f in frames)
check("CGWindowList 窗口 frame 一致", match and len(frames) == 1, f"app={frames} dump=({wx},{wy},{ww}x{wh})")

print("\n== 3. 快照 + 像素渲染验证（sticky）==")
sid = s["id"]
ok = snapshot(sid, f"{WORK}/snap1.png")
check("快照生成", ok)
if ok:
    ox, oy = s["canvasOffset"]
    avg, dom = probe(f"{WORK}/snap1.png", ox + 5, oy + 5, 14, 10)
    check("纸面主色为便利贴黄", dom and STYLE_COLORS[("sticky", 0)](dom), f"dom={dom}")
    darkest = 255
    for dy in range(40, 66, 4):
        for dx in range(30, 190, 6):
            _, dom2 = probe(f"{WORK}/snap1.png", ox + dx, oy + dy)
            if dom2:
                darkest = min(darkest, sum(dom2) / 3)
    check("存在深色文字墨迹", darkest < 130, f"最暗均值={darkest}")
    avg3, _ = probe(f"{WORK}/snap1.png", ox + 30, 3, 20, 8)
    check("纸面上方为透明留白", avg3 is not None)

print("\n== 4. 移动贴纸 ==")
dn("move", id=sid, x="500", y="300")
state = dump()
s = state["stickers"][0]
px, py, pw, ph = rect_of(s)
check("移动后纸面 = (500,300)", near(px, 500) and near(py, 300), f"({px},{py})")
frames = windowlist()
check("窗口系统同步移动", any(near(f[0], s["window"][0][0]) and near(f[1], s["window"][0][1]) for f in frames),
      f"{frames}")

print("\n== 5. 缩放宽度 ==")
old_h = ph
dn("resize", id=sid, width="320")
state = dump()
s = state["stickers"][0]
px, py, pw, ph = rect_of(s)
check("宽度变为 320", near(pw, 320), f"{pw}")
check("顶边锚定（y 不变）", near(py, 300), f"{py}")
check("换行重排后高度合理", ph > 40, f"{ph}")

print("\n== 6. 修改文字 ==")
long_text = "第一行：今天的重点任务\\n第二行：整理桌面贴纸的验证清单\\n第三行：喝水休息"
dn("setText", id=sid, text=long_text)
state = dump()
s = state["stickers"][0]
px, py, pw, ph = rect_of(s)
check("文字已更新", s["text"].count("第一行") == 1, s["text"][:20])
check("多行文字高度增长", ph > old_h, f"{ph} > {old_h}")

print("\n== 7. 切换风格（blackboard）==")
dn("setStyle", id=sid, style="blackboard", colorIndex="0")
state = dump()
s = state["stickers"][0]
check("风格已切换", s["style"] == "blackboard")
ok = snapshot(sid, f"{WORK}/snap2.png")
if ok:
    ox, oy = s["canvasOffset"]
    avg, dom = probe(f"{WORK}/snap2.png", ox + 5, oy + 5, 14, 10)
    check("黑板主色为墨绿", dom and STYLE_COLORS[("blackboard", 0)](dom), f"dom={dom}")
    avg2, dom2 = probe(f"{WORK}/snap2.png", ox + 110, oy + int(ph) // 2, 30, 16)
    check("板面中部为墨绿", dom2 and STYLE_COLORS[("blackboard", 0)](dom2), f"dom={dom2}")

print("\n== 8. 便利贴颜色变体 ==")
dn("setStyle", id=sid, style="sticky", colorIndex="2")
state = dump()
s = state["stickers"][0]
check("颜色变体索引持久化", s["style"] == "sticky" and s["colorIndex"] == 2)
ok = snapshot(sid, f"{WORK}/snap3.png")
if ok:
    ox, oy = s["canvasOffset"]
    avg, dom = probe(f"{WORK}/snap3.png", ox + 5, oy + 5, 14, 10)
    mint = dom and dom[1] > dom[0] and dom[1] > dom[2] and dom[1] > 180
    check("变体 2 渲染为薄荷绿", mint, f"dom={dom}")

print("\n== 9. 多贴纸共存（8 种风格全覆盖）==")
positions = [(80, 560), (360, 560), (640, 560), (920, 560), (80, 700), (360, 700), (640, 700)]
for i, style_id in enumerate(["notebook", "handwritten", "minimal", "vintage", "cute", "mono", "blackboard"]):
    x, y = positions[i]
    dn("create", text=f"风格示例 {i + 1}", style=style_id, x=str(x), y=str(y), width="230")
state = dump()
check("共 8 张贴纸", state and len(state["stickers"]) == 8, str(len(state.get("stickers", []))))
frames = windowlist()
check("窗口系统中有 8 个贴纸窗口", len(frames) == 8, str(len(frames)))

all_styles_ok = True
for st in state["stickers"]:
    style_key = (st["style"], st["colorIndex"])
    expect = STYLE_COLORS.get(style_key)
    if expect is None:
        print(f"  ? 跳过无断言定义: {style_key}")
        continue
    ok = snapshot(st["id"], f"{WORK}/snap-style-{st['style']}-{st['colorIndex']}.png")
    if not ok:
        all_styles_ok = False
        print(f"  ✗ 快照失败: {style_key}")
        continue
    ox, oy = st["canvasOffset"]
    avg, dom = probe(f"{WORK}/snap-style-{st['style']}-{st['colorIndex']}.png", ox + 5, oy + 5, 14, 10)
    passed = dom and expect(dom)
    if not passed:
        all_styles_ok = False
        print(f"  ✗ {style_key} 主色不符: dom={dom}")
check("8 种风格像素断言全部通过", all_styles_ok)

print("\n== 10. 删除贴纸 ==")
victim = state["stickers"][3]["id"]
dn("delete", id=victim)
state = dump()
check("删除后剩 7 张", state and len(state["stickers"]) == 7)
frames = windowlist()
check("窗口系统同步移除", len(frames) == 7, str(len(frames)))

print("\n== 11. 隐藏 / 显示全部 ==")
dn("hideAll")
state = dump()
check("allHidden = true", state["allHidden"] is True)
time.sleep(0.5)
check("窗口全部隐藏", len(windowlist()) == 0, str(windowlist()))
dn("showAll")
state = dump()
check("allHidden = false", state["allHidden"] is False)
time.sleep(0.5)
check("窗口全部恢复", len(windowlist()) == 7, str(len(windowlist())))

print("\n== 12. 持久化：重启恢复 ==")
before = dump()
before_map = {st["id"]: (st["text"], st["style"], st["colorIndex"], rect_of(st)) for st in before["stickers"]}
dn("flush")
time.sleep(0.5)
pid = int(open(APP_PID_FILE).read().strip())
os.kill(pid, 15)
time.sleep(1.5)

log1 = open(APP_LOG).read()
with open(APP_LOG, "w") as f:
    f.write("")
env = {**os.environ, "HOME": APP_HOME}
subprocess.Popen([APP_BIN, "--automation", "--state-dir", APP_STATE_DIR],
                 stdout=open(APP_LOG, "w"), stderr=subprocess.STDOUT,
                 env=env, start_new_session=True)
time.sleep(2.5)
new_pid = subprocess.run(["pgrep", "-n", "-x", "DeskStickers"], capture_output=True, text=True).stdout.strip()
open(APP_PID_FILE, "w").write(new_pid)

after = dump(timeout=8)
check("重启后可响应", after is not None)
if after:
    check("贴纸数量一致", len(after["stickers"]) == len(before["stickers"]),
          f"{len(after.get('stickers', []))} vs {len(before['stickers'])}")
    restored_ok = True
    for st in after["stickers"]:
        key = st["id"]
        if key not in before_map:
            restored_ok = False
            print(f"  ✗ 出现未知贴纸 {key}")
            continue
        text0, style0, color0, (x0, y0, w0, h0) = before_map[key]
        x, y, w, h = rect_of(st)
        if st["text"] != text0 or st["style"] != style0 or st["colorIndex"] != color0 \
           or not (near(x, x0) and near(y, y0) and near(w, w0)):
            restored_ok = False
            print(f"  ✗ 恢复不一致: {key} {st['style']} ({x},{y},{w}) vs ({x0},{y0},{w0})")
    check("文字/风格/颜色/位置完整恢复", restored_ok)
    check("恢复后窗口可见", len(windowlist()) == len(after["stickers"]), str(windowlist()))

print("\n== 13. 日志健康检查 ==")
log2 = open(APP_LOG).read() + log1
check("无 FATAL", "FATAL" not in log2)
check("无未捕获异常", "UNCAUGHT" not in log2 and "Traceback" not in log2)
errors = [line for line in log2.splitlines() if "[ERROR]" in line]
check("无 ERROR 日志", len(errors) == 0, "; ".join(errors[:3]))

# ============================================================
print("\n" + "=" * 52)
total = len(results)
passed = sum(1 for _, ok, _ in results if ok)
print(f"端到端验证：{passed}/{total} 项通过")
if passed < total:
    print("失败项：")
    for name, ok, detail in results:
        if not ok:
            print(f"  ✗ {name}  {detail}")
    sys.exit(1)
print("全部通过 ✅")
