import CoreGraphics

/// A text annotation. `origin` = top-left of the text's layout box, in image pixels,
/// top-left image origin (y down) — same convention as Arrow. `fontSize` in image pixels.
public struct TextLabel: Equatable {
    public var origin: CGPoint
    public var text: String
    public var fontSize: CGFloat

    public init(origin: CGPoint, text: String, fontSize: CGFloat) {
        self.origin = origin
        self.text = text
        self.fontSize = fontSize
    }
}

/// Everything the user can draw, in drawing (and undo) order.
public enum Annotation: Equatable {
    case arrow(Arrow)
    case text(TextLabel)
}
