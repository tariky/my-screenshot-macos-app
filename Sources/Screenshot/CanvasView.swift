import AppKit
import ScreenshotCore

enum EditorTool {
    case arrow, text
}

/// Outcome of a text edit, reported to the window which owns the annotation list.
enum TextEditResult {
    case added(TextLabel)
    case replaced(index: Int, with: TextLabel)
    case removed(index: Int)
}

/// Draws the screenshot aspect-fit plus annotations (including the arrow being dragged and the
/// label being typed). Flipped, so view coordinates are top-left based like `ImageFit`, `Arrow`
/// and `TextLabel`.
///
/// Text editing: the label is always drawn by `ArrowRenderer.draw(_:in:)` in image-pixel space
/// (so it matches the final render exactly). A transparent `NSTextView` laid out with the same
/// font, in the same image-pixel space (its bounds are scaled), sits on top only to provide the
/// caret, selection and all the usual text editing behaviour.
final class CanvasView: NSView, NSTextViewDelegate {
    var annotations: [Annotation] = [] {
        didSet { needsDisplay = true }
    }
    var tool: EditorTool = .arrow {
        didSet {
            guard tool != oldValue else { return }
            if tool != .text { commitEditing() }
            window?.invalidateCursorRects(for: self)
        }
    }
    var onArrowAdded: ((Arrow) -> Void)?
    /// Called with `true` when an arrow drag starts moving and `false` when it ends.
    var onDragStateChanged: ((Bool) -> Void)?
    var onTextEdited: ((TextEditResult) -> Void)?

    private let image: CGImage
    private let pixelSize: CGSize
    /// In-progress drag, in view coordinates.
    private var dragStart: CGPoint?
    private var dragEnd: CGPoint?
    private var isDragging = false {
        didSet { if isDragging != oldValue { onDragStateChanged?(isDragging) } }
    }

    /// The label being edited (image pixels) and, when editing an existing one, its index.
    private var editingLabel: TextLabel?
    private var editingIndex: Int?
    private var textView: LabelTextView?
    /// Per-edit undo stack, so typing undo never leaks into the window once the edit ends.
    private var textUndoManager: UndoManager?

    var isEditingText: Bool { editingLabel != nil }

    init(image: CGImage) {
        self.image = image
        self.pixelSize = CGSize(width: image.width, height: image.height)
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var fit: ImageFit {
        ImageFit(imageSize: pixelSize, viewSize: bounds.size)
    }

    private var defaultFontSize: CGFloat {
        ArrowRenderer.fontSize(for: pixelSize)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutTextView()
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(fit.imageRect, cursor: tool == .text ? .iBeam : .crosshair)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        EditorWindow.backdropColor.setFill()
        dirtyRect.fill()

        guard let context = NSGraphicsContext.current?.cgContext,
              bounds.width > 0, bounds.height > 0 else { return }
        let fit = self.fit
        let rect = fit.imageRect

        // Draw the CGImage upright inside the flipped view with a local flip.
        context.saveGState()
        context.interpolationQuality = .high
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()

        // Annotations: view coords are already top-left, so no flip here.
        context.saveGState()
        context.clip(to: rect)
        let lineWidth = ArrowRenderer.lineWidth(for: pixelSize) * fit.scale
        for (index, annotation) in annotations.enumerated() {
            switch annotation {
            case .arrow(let arrow):
                let viewArrow = Arrow(start: fit.toView(arrow.start), end: fit.toView(arrow.end))
                ArrowRenderer.draw(viewArrow, lineWidth: lineWidth, in: context)
            case .text(let label):
                if index == editingIndex { continue }
                drawLabel(label, fit: fit, in: context)
            }
        }
        if let label = editingLabel {
            drawLabel(label, fit: fit, in: context)
        }
        if let start = dragStart, let end = dragEnd, !ArrowRules.isTooShort(from: start, to: end) {
            ArrowRenderer.draw(Arrow(start: start, end: end), lineWidth: lineWidth, in: context)
        }
        context.restoreGState()

        if let label = editingLabel {
            drawEditingFrame(around: label, fit: fit)
        }
    }

    /// Labels are drawn in image-pixel space (scaled), exactly as `ArrowRenderer.render` lays them out.
    private func drawLabel(_ label: TextLabel, fit: ImageFit, in context: CGContext) {
        let rect = fit.imageRect
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: fit.scale, y: fit.scale)
        ArrowRenderer.draw(label, in: context)
        context.restoreGState()
    }

    /// Dashed box around the label being edited, so an empty or light label is still findable.
    private func drawEditingFrame(around label: TextLabel, fit: ImageFit) {
        let box = viewRect(for: label, fit: fit).insetBy(dx: -3, dy: -3)
        let path = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
        path.lineWidth = 1
        NSColor(white: 0, alpha: 0.45).setStroke()
        path.stroke()
        path.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.white.setStroke()
        path.stroke()
    }

    /// The label's layout box in view coordinates.
    private func viewRect(for label: TextLabel, fit: ImageFit) -> CGRect {
        let size = ArrowRenderer.textSize(label)
        let origin = fit.toView(label.origin)
        return CGRect(x: origin.x, y: origin.y, width: size.width * fit.scale, height: size.height * fit.scale)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        // A click outside the text view while editing commits that edit first.
        commitEditing()
        switch tool {
        case .arrow:
            let point = clampedPoint(for: event)
            dragStart = point
            dragEnd = point
        case .text:
            let viewPoint = convert(event.locationInWindow, from: nil)
            let fit = self.fit
            guard fit.imageRect.contains(viewPoint) else { return }
            let imagePoint = fit.toImage(viewPoint)
            if let index = labelIndex(at: imagePoint), case .text(let label) = annotations[index] {
                beginEditing(label, index: index)
            } else {
                beginEditing(newLabelAt: imagePoint)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragEnd = clampedPoint(for: event)
        isDragging = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart else { return }
        let end = clampedPoint(for: event)
        dragStart = nil
        dragEnd = nil
        isDragging = false
        needsDisplay = true
        guard !ArrowRules.isTooShort(from: start, to: end) else { return }
        let fit = self.fit
        onArrowAdded?(Arrow(start: fit.toImage(start), end: fit.toImage(end)))
    }

    /// Mouse location in view coordinates, clamped to the drawn image so arrowheads stay visible.
    private func clampedPoint(for event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let r = fit.imageRect
        return CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
    }

    /// Topmost text label whose layout box contains `imagePoint`.
    private func labelIndex(at imagePoint: CGPoint) -> Int? {
        annotations.indices.reversed().first { index in
            guard case .text(let label) = annotations[index] else { return false }
            return CGRect(origin: label.origin, size: ArrowRenderer.textSize(label)).contains(imagePoint)
        }
    }

    // MARK: - Text editing

    /// Starts a new, empty label whose first line is vertically centred on `imagePoint`
    /// with the caret right at the click.
    func beginEditing(newLabelAt imagePoint: CGPoint) {
        var label = TextLabel(origin: .zero, text: "", fontSize: defaultFontSize)
        let empty = ArrowRenderer.textSize(label)
        label.origin = CGPoint(x: max(0, imagePoint.x - empty.width / 2),
                               y: max(0, imagePoint.y - empty.height / 2))
        beginEditing(label, index: nil)
    }

    private func beginEditing(_ label: TextLabel, index: Int?) {
        commitEditing()
        editingLabel = label
        editingIndex = index

        let textView = LabelTextView(fontSize: label.fontSize)
        textUndoManager = UndoManager()
        textView.delegate = self
        textView.string = label.text
        textView.textStorage?.setAttributes(textView.typingAttributes,
                                            range: NSRange(location: 0, length: (label.text as NSString).length))
        textView.onCommit = { [weak self] in self?.commitEditing() }
        textView.onCancel = { [weak self] in self?.cancelEditing() }
        addSubview(textView)
        self.textView = textView
        layoutTextView()
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (label.text as NSString).length, length: 0))
        needsDisplay = true
    }

    /// Ends the current edit, reporting the result. Empty / whitespace-only text is discarded
    /// (an existing label edited down to nothing is removed). No-op when not editing.
    func commitEditing() {
        guard var label = editingLabel else { return }
        let index = editingIndex
        label.text = textView?.string ?? label.text
        endEditing()
        let isEmpty = label.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch (index, isEmpty) {
        case (nil, true): break
        case (nil, false): onTextEdited?(.added(label))
        case (let i?, true): onTextEdited?(.removed(index: i))
        case (let i?, false):
            if case .text(let original) = annotations[i], original == label { break }
            onTextEdited?(.replaced(index: i, with: label))
        }
    }

    /// Ends the current edit without changing anything.
    func cancelEditing() {
        guard isEditingText else { return }
        endEditing()
    }

    private func endEditing() {
        let hadFocus = window?.firstResponder === textView
        editingLabel = nil
        editingIndex = nil
        textView?.delegate = nil
        textView?.removeFromSuperview()
        textView = nil
        textUndoManager = nil
        if hadFocus { window?.makeFirstResponder(self) }
        needsDisplay = true
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        textUndoManager
    }

    func textDidChange(_ notification: Notification) {
        guard let textView, editingLabel != nil else { return }
        // ArrowRenderer only breaks lines on "\n"; normalise anything else the text view
        // would show as a line break (pasted CR/CRLF, U+2028/U+2029) so preview == render.
        let normalized = Self.normalizingLineBreaks(textView.string)
        if normalized != textView.string {
            textView.string = normalized
            textView.textStorage?.setAttributes(textView.typingAttributes,
                                                range: NSRange(location: 0, length: (normalized as NSString).length))
            textView.setSelectedRange(NSRange(location: (normalized as NSString).length, length: 0))
        }
        editingLabel?.text = textView.string
        layoutTextView()
        needsDisplay = true
    }

    static func normalizingLineBreaks(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
    }

    /// Places the text view over the label: frame in view points, bounds in image pixels,
    /// so its layout matches `ArrowRenderer`'s and it follows window resizes.
    private func layoutTextView() {
        guard let textView, let label = editingLabel else { return }
        let fit = self.fit
        var size = ArrowRenderer.textSize(label)
        // Room for the caret after the last character.
        size.width += label.fontSize
        let origin = fit.toView(label.origin)
        textView.frame = NSRect(x: origin.x, y: origin.y, width: size.width * fit.scale, height: size.height * fit.scale)
        textView.bounds = NSRect(origin: .zero, size: size)
    }
}

/// Transparent text view used only for caret, selection and editing; the canvas draws the text.
/// Return commits, Shift+Return inserts a newline, Esc cancels.
final class LabelTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    init(fontSize: CGFloat) {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                     height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)

        // Same font and metrics as ArrowRenderer: margin = max(2, 0.16·fs)/2,
        // line height = ascent + descent + leading.
        let font = unsafeBitCast(ArrowRenderer.labelFont(size: fontSize), to: NSFont.self)
        let margin = max(2, 0.16 * fontSize) / 2
        let lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineSpacing = 0
        typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.clear,
            .paragraphStyle: paragraph,
        ]
        defaultParagraphStyle = paragraph
        self.font = font
        textColor = .clear
        textContainerInset = NSSize(width: margin, height: margin)
        insertionPointColor = .controlAccentColor
        selectedTextAttributes = [.backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.3)]

        drawsBackground = false
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isHorizontallyResizable = false
        isVerticallyResizable = false
        usesFindBar = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextCompletionEnabled = false
        smartInsertDeleteEnabled = false
        focusRingType = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                insertNewlineIgnoringFieldEditor(nil)
            } else {
                onCommit?()
            }
        case #selector(insertLineBreak(_:)), #selector(insertParagraphSeparator(_:)):
            insertNewlineIgnoringFieldEditor(nil)
        case #selector(cancelOperation(_:)):
            onCancel?()
        default:
            super.doCommand(by: selector)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
