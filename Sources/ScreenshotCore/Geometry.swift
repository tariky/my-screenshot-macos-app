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
    public var scale: CGFloat { fatalError("TODO") }

    /// Where the image is drawn in view coordinates (centered).
    public var imageRect: CGRect { fatalError("TODO") }

    public func toImage(_ viewPoint: CGPoint) -> CGPoint { fatalError("TODO") }

    public func toView(_ imagePoint: CGPoint) -> CGPoint { fatalError("TODO") }
}

public enum ArrowRules {
    /// Drags shorter than this many VIEW points are ignored (treated as a click).
    public static let minimumDragLength: CGFloat = 5

    public static func isTooShort(from start: CGPoint, to end: CGPoint) -> Bool {
        fatalError("TODO")
    }
}
