import AppKit
import Carbon.HIToolbox
import ScreenshotCore
import UniformTypeIdentifiers

/// Arrow editor. Every change re-renders the full-resolution image and writes it to the clipboard.
/// The image fills the whole content area; the controls live in a floating HUD pill at the bottom.
final class EditorWindow: NSWindow, NSWindowDelegate {
    var onClose: (() -> Void)?

    /// Dark neutral shown behind the image when it is letterboxed.
    static let backdropColor = NSColor(white: 0.11, alpha: 1)

    private let baseImage: CGImage
    private let createdAt = Date()
    private var annotations: [Annotation] = []
    private let canvas: CanvasView
    private let hud = EditorHUD()

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
        backgroundColor = Self.backdropColor
        contentMinSize = NSSize(width: 320, height: 160)
        contentAspectRatio = contentSize
        buildContent()
        updateUndoButton()

        if let visible = screen?.visibleFrame {
            let size = frame.size
            setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
        } else {
            center()
        }
    }

    /// Brings the editor up as the key window of the active app. The editor is opened from a
    /// non-activating thumbnail panel of an accessory (LSUIElement) app, so without an explicit
    /// activation the window would stay inactive and keyboard shortcuts would go elsewhere.
    func present() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        makeFirstResponder(canvas)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private static func initialContentSize(for image: CGImage, on screen: NSScreen?) -> NSSize {
        let scale = screen?.backingScaleFactor ?? 2
        let visible = screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        var size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let maxWidth = visible.width * 0.9
        let maxHeight = visible.height * 0.9
        let shrink = min(1, maxWidth / max(size.width, 1), maxHeight / max(size.height, 1))
        size.width = max((size.width * shrink).rounded(), 320)
        size.height = max((size.height * shrink).rounded(), 160)
        return size
    }

    private func buildContent() {
        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = Self.backdropColor.cgColor

        hud.undoButton.target = self
        hud.undoButton.action = #selector(undoArrow(_:))
        hud.saveButton.target = self
        hud.saveButton.action = #selector(saveImage(_:))
        hud.doneButton.target = self
        hud.doneButton.action = #selector(done(_:))

        hud.arrowToolButton.target = self
        hud.arrowToolButton.action = #selector(selectArrowTool(_:))
        hud.textToolButton.target = self
        hud.textToolButton.action = #selector(selectTextTool(_:))
        updateToolButtons()

        canvas.onArrowAdded = { [weak self] arrow in
            self?.annotations.append(.arrow(arrow))
            self?.annotationsChanged()
        }
        canvas.onTextEdited = { [weak self] result in
            guard let self else { return }
            switch result {
            case .added(let label): annotations.append(.text(label))
            case .replaced(let index, let label): annotations[index] = .text(label)
            case .removed(let index): annotations.remove(at: index)
            }
            annotationsChanged()
        }
        canvas.onDragStateChanged = { [weak self] dragging in
            self?.hud.setDimmed(dragging)
        }

        for view in [canvas, hud] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: content.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            hud.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            hud.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        contentView = content
    }

    // MARK: - State

    private var renderedImage: CGImage {
        annotations.isEmpty ? baseImage : ArrowRenderer.render(base: baseImage, annotations: annotations)
    }

    private func annotationsChanged() {
        canvas.annotations = annotations
        updateUndoButton()
        Clipboard.write(renderedImage)
    }

    private func updateUndoButton() {
        hud.undoButton.isEnabled = !annotations.isEmpty
    }

    private func updateToolButtons() {
        hud.arrowToolButton.isOn = canvas.tool == .arrow
        hud.textToolButton.isOn = canvas.tool == .text
    }

    private func setTool(_ tool: EditorTool) {
        canvas.commitEditing()
        canvas.tool = tool
        updateToolButtons()
        if firstResponder !== canvas { makeFirstResponder(canvas) }
    }

    /// The canvas's text field editor has focus: keys belong to it.
    private var isEditingText: Bool {
        canvas.isEditingText
    }

    // MARK: - Actions

    @objc func selectArrowTool(_ sender: Any?) {
        setTool(.arrow)
    }

    @objc func selectTextTool(_ sender: Any?) {
        setTool(.text)
    }

    /// Removes the last annotation (arrow or text). An open text edit is committed first,
    /// so the HUD Undo button undoes what the user sees.
    @objc func undoArrow(_ sender: Any?) {
        canvas.commitEditing()
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        annotationsChanged()
    }

    @objc func saveImage(_ sender: Any?) {
        guard attachedSheet == nil else { return }
        canvas.commitEditing()
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

    /// The clipboard already holds the latest render, so Done just closes.
    @objc private func done(_ sender: Any?) {
        close()
    }

    /// Commits any open text edit before the window goes away (also for programmatic close()).
    override func close() {
        canvas.commitEditing()
        super.close()
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
        let key = event.charactersIgnoringModifiers?.lowercased()
        if isEditingText {
            // The text view gets ⌘Z/⌘A/⌘C/… and Esc (cancel edit) via the normal path.
            // Save and close still work, committing the edit first (see saveImage / close).
            if mods == .command, key == "s" { saveImage(nil); return true }
            if mods == .command, key == "w" { close(); return true }
            return super.performKeyEquivalent(with: event)
        }
        if mods == .command, let key {
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
        if isEditingText {
            canvas.cancelEditing()
        } else {
            close()
        }
    }

    /// Unhandled keys from the canvas: Esc closes, A / T switch tools.
    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.keyCode == UInt16(kVK_Escape) {
            if isEditingText { canvas.cancelEditing() } else { close() }
            return
        }
        if !isEditingText, mods.isEmpty {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a": setTool(.arrow); return
            case "t": setTool(.text); return
            default: break
            }
        }
        super.keyDown(with: event)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        let callback = onClose
        onClose = nil
        callback?()
    }
}

// MARK: - HUD

/// Floating pill with Arrow / Text | Undo / Save | Done, overlaid on the canvas.
/// To add controls, put them in `items` (an `HUDSeparator` gets a little extra breathing room).
final class EditorHUD: NSView {
    static let height: CGFloat = 40

    let arrowToolButton = HUDButton.icon("arrow.up.right", toolTip: "Arrow (A)", label: "Arrow")
    let textToolButton = HUDButton.icon("textformat", toolTip: "Text (T)", label: "Text")
    let undoButton = HUDButton.icon("arrow.uturn.backward", toolTip: "Undo (⌘Z)", label: "Undo")
    let saveButton = HUDButton.icon("square.and.arrow.down", toolTip: "Save… (⌘S)", label: "Save")
    let doneButton = HUDButton(symbol: "checkmark", title: "Done", style: .prominent,
                               toolTip: "Done (Esc)", accessibilityLabel: "Done")

    private var items: [NSView] {
        [arrowToolButton, textToolButton, HUDSeparator(), undoButton, saveButton, HUDSeparator(), doneButton]
    }

    private let effect = NSVisualEffectView()

    init() {
        super.init(frame: .zero)
        // Always a dark HUD, like CleanShot: it reads well over any screenshot and looks the
        // same whether the system is in light or dark mode.
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        layer?.shadowColor = NSColor(white: 0, alpha: 0.35).cgColor

        effect.material = .hudWindow
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Self.height / 2
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor(white: 1, alpha: 0.16).cgColor

        let views = items
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        for (index, view) in views.enumerated() where view is HUDSeparator {
            stack.setCustomSpacing(8, after: view)
            if index > 0 { stack.setCustomSpacing(8, after: views[index - 1]) }
        }

        for view in [effect, stack] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(effect)
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            effect.topAnchor.constraint(equalTo: topAnchor),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor),
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Fades the HUD while an arrow is being dragged so it doesn't cover the annotation.
    func setDimmed(_ dimmed: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = dimmed ? 0.12 : 0.2
            animator().alphaValue = dimmed ? 0.15 : 1
        }
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: bounds.height / 2,
                                   cornerHeight: bounds.height / 2, transform: nil)
    }

    // Plain arrow cursor over the HUD (the canvas below uses a crosshair).
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    // Swallow clicks in the gaps between buttons so they don't start an arrow or move the window.
    override func mouseDown(with event: NSEvent) {}
    override var mouseDownCanMoveWindow: Bool { false }
}

/// Thin vertical hairline between groups of HUD controls.
final class HUDSeparator: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 1, height: 18) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.2).setFill()
        bounds.fill()
    }
}

/// Fully custom-drawn HUD button. It is an `NSControl`, not an `NSButton`, so no system bezel,
/// hover effect or focus ring is ever drawn, and it looks the same whether or not the window
/// is key. Hover is a subtle filled rounded rect; disabled buttons get no hover at all.
final class HUDButton: NSControl {
    enum Style { case icon, prominent }

    /// A 28×28 borderless icon button.
    static func icon(_ symbol: String, toolTip: String, label: String) -> HUDButton {
        HUDButton(symbol: symbol, title: nil, style: .icon, toolTip: toolTip, accessibilityLabel: label)
    }

    /// Selected look for toggle-style buttons (e.g. a tool switch).
    var isOn = false {
        didSet { if isOn != oldValue { needsDisplay = true } }
    }

    private let style: Style
    private let symbolName: String
    private let label: String?
    private var hoverArea: NSTrackingArea?
    private var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }
    private var isPressed = false {
        didSet { if isPressed != oldValue { needsDisplay = true } }
    }

    init(symbol: String, title: String?, style: Style, toolTip: String, accessibilityLabel: String) {
        self.style = style
        self.symbolName = symbol
        self.label = title
        super.init(frame: .zero)
        focusRingType = .none
        refusesFirstResponder = true
        self.toolTip = toolTip
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityLabel)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // NSControl keeps these in its cell; this control has no cell, so store them here.
    private var storedTarget: AnyObject?
    private var storedAction: Selector?
    private var storedEnabled = true

    override var target: AnyObject? {
        get { storedTarget }
        set { storedTarget = newValue }
    }

    override var action: Selector? {
        get { storedAction }
        set { storedAction = newValue }
    }

    override var isEnabled: Bool {
        get { storedEnabled }
        set {
            guard newValue != storedEnabled else { return }
            storedEnabled = newValue
            if !newValue { isPressed = false }
            setAccessibilityEnabled(newValue)
            needsDisplay = true
        }
    }

    private func press() {
        guard let action = storedAction else { return }
        NSApp.sendAction(action, to: storedTarget, from: self)
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        press()
        return true
    }

    // MARK: Metrics

    private static let side: CGFloat = 28
    private static let iconPointSize: CGFloat = 15
    private static let hoverRadius: CGFloat = 7
    private static let prominentFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let prominentPadding: CGFloat = 12
    private static let prominentGap: CGFloat = 5

    override var intrinsicContentSize: NSSize {
        switch style {
        case .icon:
            return NSSize(width: Self.side, height: Self.side)
        case .prominent:
            let symbolWidth = symbolImage(color: .white)?.size.width ?? 0
            let textWidth = labelString(color: .white).size().width
            let width = Self.prominentPadding * 2 + symbolWidth + Self.prominentGap + textWidth
            return NSSize(width: ceil(width), height: Self.side)
        }
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        isHovered = false
        isPressed = false
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        if inside { press() }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        switch style {
        case .icon: drawIcon()
        case .prominent: drawProminent()
        }
    }

    private func drawIcon() {
        let fillAlpha: CGFloat
        if !isEnabled { fillAlpha = 0 }
        else if isPressed { fillAlpha = 0.20 }
        else if isOn { fillAlpha = 0.16 }
        else if isHovered { fillAlpha = 0.10 }
        else { fillAlpha = 0 }
        if fillAlpha > 0 {
            NSColor.labelColor.withAlphaComponent(fillAlpha).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: Self.hoverRadius, yRadius: Self.hoverRadius).fill()
        }
        let color: NSColor = isEnabled ? .labelColor : .tertiaryLabelColor
        guard let image = symbolImage(color: color) else { return }
        image.draw(in: Self.centeredRect(for: image, in: bounds))
    }

    /// Centres a symbol by its alignment rect (optical centre), not its raw bounding box.
    private static func centeredRect(for image: NSImage, in box: NSRect) -> NSRect {
        let align = image.alignmentRect.isEmpty ? NSRect(origin: .zero, size: image.size) : image.alignmentRect
        let x = box.midX - align.midX
        let y = box.midY - align.midY
        return NSRect(x: x.rounded(), y: y.rounded(), width: image.size.width, height: image.size.height)
    }

    private func drawProminent() {
        var fill = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        if !isEnabled {
            fill = fill.withAlphaComponent(0.5)
        } else if isPressed {
            fill = fill.blended(withFraction: 0.18, of: .black) ?? fill
        } else if isHovered {
            fill = fill.blended(withFraction: 0.10, of: .white) ?? fill
        }
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()

        guard let image = symbolImage(color: .white) else { return }
        let text = labelString(color: .white)
        let textSize = text.size()
        let contentWidth = image.size.width + Self.prominentGap + textSize.width
        let x = ((bounds.width - contentWidth) / 2).rounded()
        let iconBox = NSRect(x: x, y: 0, width: image.size.width, height: bounds.height)
        image.draw(in: Self.centeredRect(for: image, in: iconBox))
        text.draw(at: NSPoint(x: x + image.size.width + Self.prominentGap,
                              y: ((bounds.height - textSize.height) / 2).rounded()))
    }

    private func symbolImage(color: NSColor) -> NSImage? {
        let base = style == .icon
            ? NSImage.SymbolConfiguration(pointSize: Self.iconPointSize, weight: .medium)
            : NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        let config = base.applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    private func labelString(color: NSColor) -> NSAttributedString {
        NSAttributedString(string: label ?? "", attributes: [
            .font: Self.prominentFont,
            .foregroundColor: color,
        ])
    }
}
