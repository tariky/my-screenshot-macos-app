import CoreGraphics

/// Aspect-fit mapping between a view and an image drawn centered inside it.
/// Both coordinate spaces use a TOP-LEFT origin (y down); use a flipped NSView.
public struct ImageFit: Equatable {
    /// Image size in pixels.
    public let imageSize: CGSize
    /// View bounds size in points.
    public let viewSize: CGSize

    public init(imageSize: CGSize, viewSize: CGSize) {
        self.imageSize = imageSize
        self.viewSize = viewSize
    }

    /// View points per image pixel (aspect-fit, may be < 1 or > 1).
    public var scale: CGFloat {
        guard isValid else { return 1 }
        return min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
    }

    /// Where the image is drawn in view coordinates (centered).
    /// Degenerate sizes (zero, negative, non-finite) yield `.zero` with scale 1, so the
    /// mappings degrade to identity instead of producing NaN.
    public var imageRect: CGRect {
        guard isValid else { return .zero }
        let s = scale
        let w = imageSize.width * s, h = imageSize.height * s
        return CGRect(x: (viewSize.width - w) / 2, y: (viewSize.height - h) / 2, width: w, height: h)
    }

    /// Not clamped: points outside the image map to coordinates outside 0..<size.
    public func toImage(_ viewPoint: CGPoint) -> CGPoint {
        let o = imageRect.origin, s = scale
        return CGPoint(x: (viewPoint.x - o.x) / s, y: (viewPoint.y - o.y) / s)
    }

    public func toView(_ imagePoint: CGPoint) -> CGPoint {
        let o = imageRect.origin, s = scale
        return CGPoint(x: imagePoint.x * s + o.x, y: imagePoint.y * s + o.y)
    }

    private var isValid: Bool {
        func ok(_ v: CGFloat) -> Bool { v.isFinite && v > 0 }
        return ok(imageSize.width) && ok(imageSize.height) && ok(viewSize.width) && ok(viewSize.height)
    }
}

public enum ArrowRules {
    /// Drags shorter than this many VIEW points are ignored (treated as a click).
    public static let minimumDragLength: CGFloat = 5

    public static func isTooShort(from start: CGPoint, to end: CGPoint) -> Bool {
        let dx = end.x - start.x, dy = end.y - start.y
        return (dx * dx + dy * dy).squareRoot() < minimumDragLength
    }
}
