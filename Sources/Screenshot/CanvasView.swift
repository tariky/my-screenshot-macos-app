import AppKit
import ScreenshotCore

/// Draws the screenshot aspect-fit plus arrows (including the one being dragged).
/// Flipped, so view coordinates are top-left based like `ImageFit` and `Arrow`.
final class CanvasView: NSView {
    var arrows: [Arrow] = [] {
        didSet { needsDisplay = true }
    }
    var onArrowAdded: ((Arrow) -> Void)?
    /// Called with `true` when an arrow drag starts moving and `false` when it ends.
    var onDragStateChanged: ((Bool) -> Void)?

    private let image: CGImage
    private let pixelSize: CGSize
    /// In-progress drag, in view coordinates.
    private var dragStart: CGPoint?
    private var dragEnd: CGPoint?
    private var isDragging = false {
        didSet { if isDragging != oldValue { onDragStateChanged?(isDragging) } }
    }

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

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(fit.imageRect, cursor: .crosshair)
    }

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

        // Arrows: view coords are already top-left, so no flip here.
        context.saveGState()
        context.clip(to: rect)
        let lineWidth = ArrowRenderer.lineWidth(for: pixelSize) * fit.scale
        for arrow in arrows {
            let viewArrow = Arrow(start: fit.toView(arrow.start), end: fit.toView(arrow.end))
            ArrowRenderer.draw(viewArrow, lineWidth: lineWidth, in: context)
        }
        if let start = dragStart, let end = dragEnd, !ArrowRules.isTooShort(from: start, to: end) {
            ArrowRenderer.draw(Arrow(start: start, end: end), lineWidth: lineWidth, in: context)
        }
        context.restoreGState()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = clampedPoint(for: event)
        dragStart = point
        dragEnd = point
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
}
