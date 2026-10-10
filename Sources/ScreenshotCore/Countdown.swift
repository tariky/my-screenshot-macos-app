import Foundation

/// Pure countdown logic for the thumbnail. Time is injected so it can be tested.
public struct Countdown {
    public let duration: TimeInterval
    public private(set) var isPaused: Bool = false

    /// Time elapsed in running segments that have already ended (by pausing).
    private var elapsedBeforeSegment: TimeInterval = 0
    /// Start of the current running segment (meaningful only while not paused).
    private var segmentStart: Date

    public init(duration: TimeInterval = 5, startedAt: Date) {
        self.duration = max(0, duration)
        self.segmentStart = startedAt
    }

    public mutating func pause(at now: Date) {
        guard !isPaused else { return }
        elapsedBeforeSegment = elapsed(at: now)
        isPaused = true
    }

    public mutating func resume(at now: Date) {
        guard isPaused else { return }
        segmentStart = now
        isPaused = false
    }

    /// Seconds left, clamped to 0...duration. Frozen while paused.
    public func remaining(at now: Date) -> TimeInterval {
        min(duration, max(0, duration - elapsed(at: now)))
    }

    /// remaining / duration, 1 → 0. Drives the progress bar.
    public func fraction(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return remaining(at: now) / duration
    }

    public func isExpired(at now: Date) -> Bool {
        remaining(at: now) <= 0
    }

    private func elapsed(at now: Date) -> TimeInterval {
        if isPaused { return elapsedBeforeSegment }
        return elapsedBeforeSegment + now.timeIntervalSince(segmentStart)
    }
}
