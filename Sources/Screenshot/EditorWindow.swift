import AppKit
import Carbon.HIToolbox
import ScreenshotCore
import UniformTypeIdentifiers

/// Arrow editor. Every change re-renders the full-resolution image and writes it to the clipboard.
final class EditorWindow: NSWindow, NSWindowDelegate {
    var onClose: (() -> Void)?

    private static let toolbarHeight: CGFloat = 44

    private let baseImage: CGImage
    private let createdAt = Date()
    private var arrows: [Arrow] = []
    private let canvas: CanvasView
    private let undoButton = NSButton(title: "Undo", target: nil, action: nil)

    init(image: CGImage) {
        baseImage = image
        canvas = CanvasView(image: image)
        let screen = NSScreen.withMouse ?? NSScreen.screens.first
        let contentSize = Self.initialContentSize(for: image, on: screen)
        super.init(contentRect: NSRect(origin: .zero, size: contentSize),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                   backing: .buffered, defer: false)
        title = "Screenshot"
        isReleasedWhenClosed = false
        delegate = self
        contentMinSize = NSSize(width: 320, height: Self.toolbarHeight + 120)
        buildContent()
        updateUndoButton()

        if let visible = screen?.visibleFrame {
            let size = frame.size
            setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
        } else {
            center()
        }
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(canvas)
    }

    private static func initialContentSize(for image: CGImage, on screen: NSScreen?) -> NSSize {
        let scale = screen?.backingScaleFactor ?? 2
        let visible = screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        var size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let maxWidth = visible.width * 0.9
        let maxHeight = visible.height * 0.9 - toolbarHeight
        let shrink = min(1, maxWidth / max(size.width, 1), maxHeight / max(size.height, 1))
        size.width = max((size.width * shrink).rounded(), 320)
        size.height = max((size.height * shrink).rounded(), 120)
        return NSSize(width: size.width, height: size.height + toolbarHeight)
    }

    private func buildContent() {
        let content = NSView()

        undoButton.target = self
        undoButton.action = #selector(undoArrow(_:))
        let saveButton = NSButton(title: "Save…", target: self, action: #selector(saveImage(_:)))
        let doneButton = NSButton(title: "Done", target: self, action: #selector(done(_:)))
        for button in [undoButton, saveButton, doneButton] {
            button.bezelStyle = .rounded
            button.refusesFirstResponder = true
        }

        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        toolbar.setViews([undoButton], in: .leading)
        toolbar.setViews([saveButton, doneButton], in: .trailing)

        let separator = NSBox()
        separator.boxType = .separator

        canvas.onArrowAdded = { [weak self] arrow in
            self?.arrows.append(arrow)
            self?.arrowsChanged()
        }

        for view in [toolbar, separator, canvas] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: Self.toolbarHeight - 1),

            separator.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            canvas.topAnchor.constraint(equalTo: separator.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        contentView = content
    }

    // MARK: - State

    private var renderedImage: CGImage {
        arrows.isEmpty ? baseImage : ArrowRenderer.render(base: baseImage, arrows: arrows)
    }

    private func arrowsChanged() {
        canvas.arrows = arrows
        updateUndoButton()
        Clipboard.write(renderedImage)
    }

    private func updateUndoButton() {
        undoButton.isEnabled = !arrows.isEmpty
    }

    // MARK: - Actions

    @objc func undoArrow(_ sender: Any?) {
        guard !arrows.isEmpty else { return }
        arrows.removeLast()
        arrowsChanged()
    }

    @objc func saveImage(_ sender: Any?) {
        guard attachedSheet == nil else { return }
        let image = renderedImage
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.nameFieldStringValue = Self.defaultFileName(for: createdAt)
        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try ArrowRenderer.pngData(image).write(to: url, options: .atomic)
            } catch {
                guard let self else { return }
                NSAlert(error: error).beginSheetModal(for: self)
            }
        }
    }

    @objc private func done(_ sender: Any?) {
        close()
    }

    private static func defaultFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: date)).png"
    }

    // MARK: - Keys
    // Handled here directly (not only via NSApp.mainMenu) so they work reliably in an
    // LSUIElement/accessory app. The key window gets performKeyEquivalent before the main menu.

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, attachedSheet == nil else {
            return super.performKeyEquivalent(with: event)
        }
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if mods == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "z": undoArrow(nil); return true
            case "s": saveImage(nil); return true
            case "w": close(); return true
            default: break
            }
        }
        if mods.isEmpty, event.keyCode == UInt16(kVK_Escape) {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            close()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        let callback = onClose
        onClose = nil
        callback?()
    }
}
