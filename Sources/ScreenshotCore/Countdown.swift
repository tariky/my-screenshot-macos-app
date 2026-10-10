import Foundation

/// Pure countdown logic for the thumbnail. Time is injected so it can be tested.
public struct Countdown {
    public let duration: TimeInterval
    public private(set) var isPaused: Bool = false

    public init(duration: TimeInterval = 5, startedAt: Date) {
        fatalError("TODO")
    }

    public mutating func pause(at now: Date) { fatalError("TODO") }

    public mutating func resume(at now: Date) { fatalError("TODO") }

    /// Seconds left, clamped to 0...duration. Frozen while paused.
    public func remaining(at now: Date) -> TimeInterval { fatalError("TODO") }

    /// remaining / duration, 1 → 0. Drives the progress bar.
    public func fraction(at now: Date) -> Double { fatalError("TODO") }

    public func isExpired(at now: Date) -> Bool { fatalError("TODO") }
}
