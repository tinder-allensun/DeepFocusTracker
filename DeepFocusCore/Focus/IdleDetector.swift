import Foundation
import CoreGraphics

/// Reports when the user goes idle (no keyboard/mouse input) past a threshold,
/// so away time isn't attributed to whatever app happens to be frontmost.
@MainActor
final class IdleDetector {
    private let threshold: TimeInterval
    private let pollInterval: TimeInterval
    private var timer: Timer?
    private var onChange: ((Bool) -> Void)?

    private(set) var isIdle = false

    init(threshold: TimeInterval, pollInterval: TimeInterval = 2) {
        self.threshold = threshold
        self.pollInterval = pollInterval
    }

    func start(onChange: @escaping (Bool) -> Void) {
        stop()
        self.onChange = onChange
        isIdle = false
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onChange = nil
        isIdle = false
    }

    /// Seconds since the last user input event of any kind.
    /// (`.max` maps to `kCGAnyInputEventType` — a valid `CGEventType` raw value.)
    static func secondsSinceInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: .max)!)
    }

    private func poll() {
        let idleNow = Self.secondsSinceInput() >= threshold
        guard idleNow != isIdle else { return }
        isIdle = idleNow
        onChange?(idleNow)
    }
}
