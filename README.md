# DeskStickers 桌面贴纸

一款 macOS 桌面便签应用：把彩色贴纸钉在桌面上，随时记录、随手缩放。

纯 Swift + AppKit 实现，零第三方依赖，SwiftPM 构建。

## 功能

- **8 种手绘风格**：便利贴、笔记本、手写、极简、复古、黑板、可爱、等宽——每种自带纸张纹理、阴影与配色变体
- **自由摆放**：拖动贴纸到任意位置，悬浮于普通窗口之上，跨 Space 常驻
- **两种缩放**：
  - 右下角手柄 = 等比缩放，宽高、字号、内边距同步变化（0.4×–2.5×）
  - 纸面左右边缘 = 仅调整宽度，文字自动重排
- **字体调整**：右键菜单可切换字体族（苹方/宋体/楷体/圆体/黑体/等宽）与字号
- **就地编辑**：双击或点工具栏进入编辑，Esc 结束；高度随内容自适应
- **状态栏控制**：新建、全部隐藏/显示、退出

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
    UI/             贴纸窗口、画布、交互层、缩放手柄、工具栏、风格选择器
    Rendering/      风格绘制、文字引擎、离屏预览渲染
    Support/        自动化桥、屏幕几何、日志
    AppController.swift
  DeskStickers/     可执行入口
  DeskStickersSelfTest/  自建测试运行器
Scripts/
  make-app.sh       打包 .app
  run-tests.sh      自测
  verify-e2e.sh     e2e 回归
  verification/     e2e 脚本与验证工具源码
```

### 设计要点

- **一贴纸一窗口**：每个贴纸是一个无边框 `NSPanel`（floating 层），可以独立压在
  任意应用窗口之上；拖动与命中测试逻辑因此保持极简
- **风格 = 值类型 + 绘制闭包**：`StickerStyle` 描述全部排版度量与绘制方式，
  等比缩放（`scaled(by:)`）只做一次乘法，装饰按纸面相对坐标自然跟随
- **effectiveStyle 派生链**：贴纸的 `scale` / 字体覆盖与基础风格合成出实际生效
  风格，渲染、排版、窗口尺寸全部走同一条链，不会出现"文字变了纸没变"
- **状态文件向后兼容**：JSON 解码用 `decodeIfPresent`，新增字段对旧状态文件透明

## 自动化接口

以 `--automation` 启动后监听 `com.deskstickers.automation.<action>` 分布式通知，
支持 create / move / resize / setStyle / setText / setScale / setFont / delete /
snapshot / dump 等动作，供 e2e 与调试工具（`Scripts/verification/dnctl.swift`）使用。

## 许可

个人项目，仅供学习交流。
