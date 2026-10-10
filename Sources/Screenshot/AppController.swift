import AppKit
import Carbon.HIToolbox
import ScreenshotCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var grantItem: NSMenuItem?
    private var hotKey: HotKey?
    private let thumbnail = ThumbnailPanel()
    private var editors: [EditorWindow] = []
    private var isCapturing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        installStatusItem()

        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }

        do {
            hotKey = try HotKey(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
                MainActor.assumeIsolated { self?.takeScreenshot() }
            }
        } catch {
            let status = (error as? HotKeyError)?.status ?? 0
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Couldn't register ⌘⇧2"
            alert.informativeText = "The shortcut is probably used by another app (error \(status)). "
                + "You can still take screenshots from the menu bar icon."
            alert.runModal()
        }
    }

    // MARK: - Menus

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screenshot")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.delegate = self

        let take = NSMenuItem(title: "Take Screenshot", action: #selector(takeScreenshotFromMenu(_:)), keyEquivalent: "2")
        take.keyEquivalentModifierMask = [.command, .shift]
        take.target = self
        menu.addItem(take)

        let grant = NSMenuItem(title: "Grant Screen Recording…", action: #selector(openScreenRecordingSettings(_:)), keyEquivalent: "")
        grant.target = self
        grant.isHidden = CGPreflightScreenCaptureAccess()
        menu.addItem(grant)
        grantItem = grant

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    /// Accessory apps show no menu bar, but `NSApp.mainMenu` still routes key equivalents.
    /// The editor window handles ⌘Z/⌘S/⌘W/Esc itself; this menu adds Quit and the standard
    /// text-editing commands (e.g. for the Save panel's name field).
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Screenshot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Save…", action: #selector(EditorWindow.saveImage(_:)), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        grantItem?.isHidden = CGPreflightScreenCaptureAccess()
    }

    @objc private func takeScreenshotFromMenu(_ sender: Any?) {
        // Let the status menu finish closing before the selector appears.
        DispatchQueue.main.async { [weak self] in self?.takeScreenshot() }
    }

    @objc private func openScreenRecordingSettings(_ sender: Any?) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Flow

    func takeScreenshot() {
        guard !isCapturing else { return }
        isCapturing = true
        // Remove the previous thumbnail right away so it doesn't end up in the new screenshot.
        thumbnail.dismiss()

        Task { @MainActor [weak self] in
            let image = await Capturer.capture()
            guard let self else { return }
            self.isCapturing = false
            guard let image else { return }
            Clipboard.write(image)
            self.thumbnail.show(image: image, onOpen: { [weak self] in
                self?.openEditor(image: image)
            }, onExpire: {})
        }
    }

    private func openEditor(image: CGImage) {
        let editor = EditorWindow(image: image)
        editor.onClose = { [weak self, weak editor] in
            guard let self, let editor else { return }
            self.editors.removeAll { $0 === editor }
        }
        editors.append(editor)
        editor.present()
    }
}

extension NSScreen {
    /// The screen currently containing the mouse pointer.
    static var withMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main
    }
}
