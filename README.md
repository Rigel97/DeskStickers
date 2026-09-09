# DeskStickers

A macOS desktop sticky-notes app: pin colorful stickers to your desktop, jot things down anytime, resize on a whim.

Pure Swift + AppKit, zero third-party dependencies, built with SwiftPM.

## Features

- **8 hand-drawn styles** — memo pad, notebook, handwriting, minimalist, retro, chalkboard, kawaii, and monospace — each with its own paper texture, shadow, and color variants
- **Free placement** — drag stickers anywhere; they float above normal windows and stay put across Spaces
- **Drag snapping** — stickers auto-align to the edges/centerlines of other stickers and to screen edges while dragging (blue guides; hold ⌘ while dragging to temporarily disable)
- **Per-sticker hide** — right-click → Hide Sticker to tuck one away temporarily; recall it individually from the status-bar sticker list, or use Show All to bring everything back
- **Global shortcuts** (usable from any app): ⌥⌘N new sticker · ⌥⌘V instant sticker from clipboard · ⌥⌘Z undo · ⌥⌘\ show/hide all · ⌥⌘P click-through
- **Pin to desktop** — a one-click layer switch that sinks stickers to the desktop layer so they stop covering the windows you're working in
- **Click-through** — stickers stay visible while clicks pass through to the windows underneath (⌥⌘P)
- **Flexible resizing**:
  - Bottom-right handle = uniform scaling; the font size follows the paper along the diagonal ratio (0.4×–2.5×)
  - Hold ⌥ and drag the bottom-right handle = change only the paper's width/height, keeping the font size (like moving to a bigger sheet and re-flowing)
  - Left/right edges = width only; text re-wraps automatically
  - Bottom edge = height only (fixed-height mode; a scrollbar appears once text overflows; the right-click menu restores auto height)
- **Font options** — switch font family (PingFang / Songti / Kaiti / Yuanti / Heiti / monospace) and size from the right-click menu
- **Inline editing** — double-click or use the toolbar to start editing, Esc / ⌘↩ to finish; height adapts to the content; a newly created empty sticker goes straight into input mode
- **Undo support** — delete / create / duplicate are all undoable (⌥⌘Z works from any app; while editing text, ⌘Z stays as text undo; the status-bar menu has an undo item too)
- **Sticker management** — the status-bar sticker list gives an overview of every sticker (hidden ones marked); click one to jump to it — off-screen stickers are pulled back on screen and flash; an empty list guides you straight to creating one
- **Hover toolbar** — Edit / Style / Duplicate / Delete, the four most frequent actions, appear on hover; buttons highlight on hover, and Delete turns red to signal danger
- **Micro-feedback** — new stickers fade in, stickers lift slightly while being dragged, and a brief hint appears over the toolbar and resize handle right after first creation (for discoverability)
- **Creator memory** — remembers your last style/color choice and the window position (auto-recenters when the external display is unplugged)
- **Menu-bar resident** — takes no Dock slot (LSUIElement); the lifecycle is owned by the status-bar icon

## Build

Requires macOS 13+ and the Swift 6 toolchain.

```bash
swift build            # debug build
bash Scripts/make-app.sh   # package build/DeskStickers.app (icon + ad-hoc signing)
```

Install to /Applications:

```bash
cp -R build/DeskStickers.app /Applications/
```

## Testing

The local CLT environment lacks XCTest, so a custom test runner is used instead:

```bash
bash Scripts/run-tests.sh    # unit/model self-tests (Swift)
bash Scripts/verify-e2e.sh   # end-to-end regression (Python + distributed-notification automation)
```

The e2e suite drives a real app instance via `DistributedNotificationCenter` to verify creation, dragging, resizing, style switching, pixel-level color assertions, and more — no XCUITest or Accessibility permissions involved.

## Project structure

```
Sources/
  DeskStickersCore/
    Model/          Sticker / StickerStyle / StickerStore (persistence)
    UI/             sticker windows, canvas, interaction layer, resize handles, toolbar, style picker, creator
    Rendering/      style drawing, text engine, offscreen preview rendering
    Support/        automation bridge, screen geometry, global hotkeys (Carbon), drag-snap engine, logging
    AppController.swift
  DeskStickers/     executable entry point
  DeskStickersSelfTest/  custom test runner (248 assertions)
Scripts/
  make-app.sh       package the .app (icon + ad-hoc signing + LSUIElement)
  run-tests.sh      self-tests
  verify-e2e.sh     e2e regression (61 assertions)
  verification/     e2e scripts and verification tool sources
```

### Design notes

- **One window per sticker** — every sticker is a borderless `NSPanel` (on the floating layer by default, switchable to the desktop layer via "pin to desktop") that can independently sit above any app window; this keeps the dragging and hit-testing logic minimal
- **App-level undo uses explicit grouping** — `NSUndoManager`'s runloop auto-grouping is unreliable in notification-driven scenarios (multiple operations end up in one unclosed group), so each operation opens its own group explicitly, guaranteeing that one ⌘Z undoes exactly one step
- **Global hotkeys = Carbon + one source of truth for menus** — `GlobalHotkeyCenter` wraps `RegisterEventHotKey` (no Accessibility permission needed; triggers even when the app is inactive); shortcut definitions are centralized in `AppHotkeys`, and menu key-equivalent display and hotkey registration share the same definitions, so they can never drift apart
- **Snapping = pure-function engine + live guides** — `SnapEngine` does nothing but geometry (unit-testable); `applyDragSnap` unifies the coordinate systems (window frame ↔ paper frame) and rebases the drag anchor; guides are separate transparent windows that never take part in events
- **Styles = value types + draw closures** — `StickerStyle` describes all typographic metrics and how to draw them; uniform scaling (`scaled(by:)`) is a single multiplication, and decorations follow along naturally via paper-relative coordinates
- **effectiveStyle derivation chain** — a sticker's `scale` / font overrides compose with the base style into the actually-effective style; rendering, layout, and window sizing all flow through the same chain, so "the text changed but the paper didn't" can never happen
- **Backward-compatible state files** — JSON decoding uses `decodeIfPresent`, so new fields (scale / hidden / clickThrough, …) are transparent to old state files

## Automation interface

When launched with `--automation`, the app listens for `com.deskstickers.automation.<action>` distributed notifications. Supported actions include create / move / resize / setHeight / setStyle / setText / setScale / setFont / delete / undo / setPinned / setClickThrough / setHidden / reveal / snapshot / dump / gripDrag (including target=catcher move-drag paths) — used by the e2e suite and the debug tool (`Scripts/verification/dnctl.swift`). Global hotkeys are not registered in automation mode so test sessions stay undisturbed.

## License

Personal project, for learning and exchange purposes only.
