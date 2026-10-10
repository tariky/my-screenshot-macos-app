import CoreGraphics

/// An arrow in image pixel coordinates, origin at the TOP-LEFT of the image (y grows downward).
/// `end` is the arrowhead tip.
public struct Arrow: Equatable {
    public var start: CGPoint
    public var end: CGPoint

    public init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
    }
}
