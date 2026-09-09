# DeskStickers 桌面贴纸

一款 macOS 桌面便签应用：把彩色贴纸钉在桌面上，随时记录、随手缩放。

纯 Swift + AppKit 实现，零第三方依赖，SwiftPM 构建。

## 功能

- **8 种手绘风格**：便利贴、笔记本、手写、极简、复古、黑板、可爱、等宽——每种自带纸张纹理、阴影与配色变体
- **自由摆放**：拖动贴纸到任意位置，悬浮于普通窗口之上，跨 Space 常驻
- **拖动吸附**：拖动时与其他贴纸边缘/中线、屏幕边缘自动对齐（蓝色参考线，按住 ⌘ 拖动临时禁用）
- **单贴纸隐藏**：右键「隐藏贴纸」暂时收起，状态栏贴纸列表可单独召回；「显示全部」一键找回所有
- **全局快捷键**（任何应用下可用）：⌥⌘N 新建 · ⌥⌘V 剪贴板秒建 · ⌥⌘Z 撤销 · ⌥⌘\\ 显示/隐藏全部 · ⌥⌘P 鼠标穿透
- **钉在桌面**：一键切换层级模式——贴纸沉到桌面层，不再遮挡正在使用的窗口
- **鼠标穿透**：贴纸保持可见，点击穿到下层窗口（⌥⌘P）
- **自由调整长宽**：
  - 右下角手柄 = 整体缩放，字号随纸面按对角线比例同步变化（0.4×–2.5×）
  - 按住 ⌥ 拖动右下角手柄 = 仅调整纸面宽高，字号不变（换个更大的纸重新排版）
  - 左右边缘 = 仅调整宽度，文字自动重排
  - 底部边缘 = 仅调整高度（进入固定高度模式，文字超出自动出现滚动条；右键菜单可恢复自动高度）
- **字体调整**：右键菜单可切换字体族（苹方/宋体/楷体/圆体/黑体/等宽）与字号
- **就地编辑**：双击或点工具栏进入编辑，Esc / ⌘↩ 结束；高度随内容自适应；新建空贴纸后直接进入输入
- **撤销支持**：删除 / 新建 / 复制均可撤销（⌥⌘Z 任何应用下可用；编辑文字时 ⌘Z 仍是文本撤销；状态栏菜单也有撤销项）
- **贴纸管理**：状态栏「贴纸列表」总览全部贴纸（隐藏的带标记），点击定位——屏幕外自动拉回并闪烁提示；空列表直接引导新建
- **悬停工具栏**：编辑 / 风格 / 复制 / 删除四个高频操作，悬停即现；按钮 hover 高亮，删除悬停变红提示危险
- **细节反馈**：新建淡入、拖动时贴纸轻微「抬起」、首次创建后工具栏与缩放手柄短暂提示（可发现性）
- **创建器记忆**：记住上次选择的风格/颜色与窗口位置（外接屏拔掉后自动回居中）
- **菜单栏常驻**：不占 Dock 位（LSUIElement），生命周期由状态栏图标接管

## 构建

要求 macOS 13+ 与 Swift 6 工具链。

```bash
swift build            # 调试构建
bash Scripts/make-app.sh   # 打包 build/DeskStickers.app（含图标 + ad-hoc 签名）
```

安装到 /Applications：

```bash
cp -R build/DeskStickers.app /Applications/
```

## 测试

本机 CLT 环境缺少 XCTest，因此采用自建测试执行器：

```bash
bash Scripts/run-tests.sh    # 单元/模型自测（Swift）
bash Scripts/verify-e2e.sh   # 端到端回归（Python + 分布式通知自动化）
```

e2e 通过 `DistributedNotificationCenter` 驱动真实 App 实例完成创建、拖动、缩放、
换风格、像素级颜色断言等验证，不依赖 XCUITest 与辅助功能权限。

## 项目结构

```
Sources/
  DeskStickersCore/
    Model/          Sticker / StickerStyle / StickerStore（持久化）
    UI/             贴纸窗口、画布、交互层、缩放手柄、工具栏、风格选择器、创建器
    Rendering/      风格绘制、文字引擎、离屏预览渲染
    Support/        自动化桥、屏幕几何、全局热键（Carbon）、拖动吸附引擎、日志
    AppController.swift
  DeskStickers/     可执行入口
  DeskStickersSelfTest/  自建测试运行器（248 项断言）
Scripts/
  make-app.sh       打包 .app（含图标 + ad-hoc 签名 + LSUIElement）
  run-tests.sh      自测
  verify-e2e.sh     e2e 回归（61 项断言）
  verification/     e2e 脚本与验证工具源码
```

### 设计要点

- **一贴纸一窗口**：每个贴纸是一个无边框 `NSPanel`（默认 floating 层，可切换到
  桌面层"钉在桌面"），可以独立压在任意应用窗口之上；拖动与命中测试逻辑因此保持极简
- **应用级撤销走显式分组**：`NSUndoManager` 的事件循环自动分组在通知驱动场景下
  不可靠（多个操作会落进同一个未关闭的分组），因此每个操作显式开组，
  保证一次 ⌘Z 恰好撤销一步
- **全局热键 = Carbon + 菜单展示同源**：`GlobalHotkeyCenter` 封装 `RegisterEventHotKey`
  （无需辅助功能权限，应用不激活也可触发），快捷键定义集中在 `AppHotkeys`，
  菜单等效键展示与热键注册共用同一份定义，不会漂移
- **吸附 = 纯函数引擎 + 实时参考线**：`SnapEngine` 只做几何计算（可单测），
  `applyDragSnap` 负责坐标系统一（窗口 frame ↔ 纸面 frame）与拖动基准 rebase，
  参考线是独立透明窗口，不参与事件
- **风格 = 值类型 + 绘制闭包**：`StickerStyle` 描述全部排版度量与绘制方式，
  等比缩放（`scaled(by:)`）只做一次乘法，装饰按纸面相对坐标自然跟随
- **effectiveStyle 派生链**：贴纸的 `scale` / 字体覆盖与基础风格合成出实际生效
  风格，渲染、排版、窗口尺寸全部走同一条链，不会出现"文字变了纸没变"
- **状态文件向后兼容**：JSON 解码用 `decodeIfPresent`，新增字段（scale / hidden /
  clickThrough 等）对旧状态文件透明

## 自动化接口

以 `--automation` 启动后监听 `com.deskstickers.automation.<action>` 分布式通知，
支持 create / move / resize / setHeight / setStyle / setText / setScale / setFont /
delete / undo / setPinned / setClickThrough / setHidden / reveal / snapshot / dump /
gripDrag（含 target=catcher 移动拖动路径）等动作，供 e2e 与调试工具
（`Scripts/verification/dnctl.swift`）使用。全局热键在自动化模式下不注册，
避免干扰测试会话。

## 许可

个人项目，仅供学习交流。
