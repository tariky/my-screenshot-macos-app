import AppKit
import QuartzCore
import ScreenshotCore

/// Floating, non-activating thumbnail in the bottom-left corner with a 5 s countdown.
/// Hover pauses the countdown, a click opens the editor, expiry fades it out.
@MainActor
final class ThumbnailPanel {
    private static let maxSide: CGFloat = 200
    private static let margin: CGFloat = 16

    private var panel: NSPanel?
    private var view: ThumbnailView?
    private var countdown: Countdown?
    private var timer: Timer?
    private var onOpen: (() -> Void)?
    private var onExpire: (() -> Void)?
    /// Bumped on every show/dismiss so a stale fade-out completion does nothing.
    private var generation = 0

    func show(image: CGImage, onOpen: @escaping () -> Void, onExpire: @escaping () -> Void) {
        dismiss()
        self.onOpen = onOpen
        self.onExpire = onExpire

        let size = Self.size(for: image)
        let visible = (NSScreen.withMouse ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let frame = NSRect(x: visible.minX + Self.margin, y: visible.minY + Self.margin,
                           width: size.width, height: size.height)

        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let view = ThumbnailView(frame: NSRect(origin: .zero, size: size), image: image)
        view.onClick = { [weak self] in self?.open() }
        panel.contentView = view

        self.panel = panel
        self.view = view
        countdown = Countdown(startedAt: Date())

        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.invalidateShadow()

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    /// Removes the thumbnail immediately without calling any callback.
    func dismiss() {
        generation += 1
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        view = nil
        countdown = nil
        onOpen = nil
        onExpire = nil
    }

    private func open() {
        let callback = onOpen
        dismiss()
        callback?()
    }

    private func tick() {
        guard var countdown, let panel, let view else { return }
        let now = Date()

        // Hover detection by polling: works while the app is inactive and when the
        // thumbnail appears under an already-resting pointer.
        let hovering = NSMouseInRect(NSEvent.mouseLocation, panel.frame, false)
        if hovering && !countdown.isPaused {
            countdown.pause(at: now)
        } else if !hovering && countdown.isPaused {
            countdown.resume(at: now)
        }
        self.countdown = countdown

        view.progress = CGFloat(countdown.fraction(at: now))
        if countdown.isExpired(at: now) {
            expire()
        }
    }

    private func expire() {
        timer?.invalidate()
        timer = nil
        guard let panel else { return }
        let token = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                let callback = self.onExpire
                self.dismiss()
                callback?()
            }
        })
    }

    private static func size(for image: CGImage) -> CGSize {
        let w = max(CGFloat(image.width), 1)
        let h = max(CGFloat(image.height), 1)
        if w >= h {
            return CGSize(width: maxSide, height: max(maxSide * h / w, 24))
        } else {
            return CGSize(width: max(maxSide * w / h, 24), height: maxSide)
        }
    }
}

private final class ThumbnailView: NSView {
    var onClick: (() -> Void)?
    var progress: CGFloat = 1 {
        didSet { if progress != oldValue { layoutBar() } }
    }

    private let imageLayer = CALayer()
    private let trackLayer = CALayer()
    private let barLayer = CALayer()
    private static let barHeight: CGFloat = 3

    init(frame: NSRect, image: CGImage) {
        super.init(frame: frame)
        wantsLayer = true
        let root = layer!
        root.cornerRadius = 10
        root.masksToBounds = true
        root.backgroundColor = NSColor.black.cgColor
        root.borderWidth = 0.5
        root.borderColor = NSColor(white: 1, alpha: 0.35).cgColor

        imageLayer.contents = image
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.minificationFilter = .trilinear
        trackLayer.backgroundColor = NSColor(white: 0, alpha: 0.35).cgColor
        barLayer.backgroundColor = NSColor.controlAccentColor.cgColor

        root.addSublayer(imageLayer)
        root.addSublayer(trackLayer)
        trackLayer.addSublayer(barLayer)
        layoutLayers()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    private func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        // Unflipped view: layer y = 0 is the bottom edge.
        trackLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.barHeight)
        CATransaction.commit()
        layoutBar()
    }

    private func layoutBar() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let fraction = min(max(progress, 0), 1)
        barLayer.frame = CGRect(x: 0, y: 0, width: trackLayer.bounds.width * fraction, height: Self.barHeight)
        CATransaction.commit()
    }
}
