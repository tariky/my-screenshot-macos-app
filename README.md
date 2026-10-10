# my-screenshot-macos-app

A tiny macOS menu-bar screenshot tool.

- **⌘⇧2** — select an area (system `screencapture -i` selector; Esc cancels, Space picks a window)
- The screenshot goes straight to the clipboard and a thumbnail appears bottom-left for 5 s
  (hover pauses the timer)
- Click the thumbnail to open the editor:
  - **Arrow (A)** — click + drag to draw a red Skitch-style arrow
  - **Text (T)** — click to type; Return commits, Shift+Return adds a line, Esc cancels
  - **⌘Z** undo, **⌘S** save PNG, **Esc / Done** close
  - Every edit is copied to the clipboard immediately

Swift 5.10 + AppKit, Swift Package Manager — no Xcode project needed (Command Line Tools are enough).

## Build

```sh
scripts/make-signing-cert.sh   # once: stable local signing identity (keeps the Screen Recording grant across rebuilds)
./build-app.sh                 # builds ./Screenshot.app
./build-app.sh --install       # builds, copies to /Applications and relaunches
```

On first launch, allow **Screenshot** in System Settings → Privacy & Security → Screen & System Audio Recording,
then relaunch the app.

## Tests

XCTest isn't available with Command Line Tools only, so core logic is checked by a small executable:

```sh
swift run --scratch-path .build-core CoreChecks
```

## Layout

- `Sources/ScreenshotCore` — pure logic: arrow/text rendering, aspect-fit geometry, countdown
- `Sources/Screenshot` — AppKit app: hotkey, capture, clipboard, thumbnail, editor
- `Sources/CoreChecks` — checks for `ScreenshotCore`
- `scripts/make-icon.swift` — regenerates `Resources/AppIcon.icns`
