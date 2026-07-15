import Foundation
import AppKit

/// Tracks which app is frontmost during a focus block, building a timeline of
/// spans plus idle "Away" time. It records only — it makes no judgment about
/// whether an app counts as focus or distraction.
@MainActor
final class ActivityMonitor {
    private let idleDetector: IdleDetector
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []

    // Timeline state for the current block.
    private var completedSpans: [AppSpan] = []
    private var openBundleID: String?
    private var openAppName: String?
    private var openStart: Date?

    private var awaySeconds: TimeInterval = 0
    private var awayStart: Date?

    private(set) var switchCount = 0
    private var isRunning = false

    init(idleTimeout: TimeInterval) {
        self.idleDetector = IdleDetector(threshold: idleTimeout)
    }

    var currentAppName: String? { awayStart == nil ? openAppName : nil }

    // MARK: Lifecycle

    func start(now: Date = .now) {
        guard !isRunning else { return }
        isRunning = true
        completedSpans.removeAll()
        awaySeconds = 0
        awayStart = nil
        switchCount = 0
        openSpan(for: NSWorkspace.shared.frontmostApplication, at: now)
        subscribe()
        idleDetector.start { [weak self] idle in
            self?.handleIdleChange(idle)
        }
    }

    /// Stops tracking and returns the finalized timeline.
    @discardableResult
    func stop(now: Date = .now) -> (spans: [AppSpan], awaySeconds: TimeInterval, switchCount: Int) {
        guard isRunning else { return (completedSpans, awaySeconds, switchCount) }
        isRunning = false
        idleDetector.stop()
        unsubscribe()
        if awayStart != nil {
            closeAway(at: now)
        } else {
            closeOpenSpan(at: now)
        }
        return (completedSpans, awaySeconds, switchCount)
    }

    /// A live summary as of `now`, including the still-open span / away time.
    func snapshot(asOf now: Date) -> UsageSummary {
        var spans = completedSpans
        if let openBundleID, let openAppName, let openStart {
            spans.append(AppSpan(
                bundleID: openBundleID,
                appName: openAppName,
                start: openStart,
                duration: max(0, now.timeIntervalSince(openStart))
            ))
        }
        var away = awaySeconds
        if let awayStart { away += max(0, now.timeIntervalSince(awayStart)) }
        return UsageAggregator.summarize(spans: spans, awaySeconds: away, switchCount: switchCount)
    }

    // MARK: Span management

    private func openSpan(for app: NSRunningApplication?, at time: Date) {
        openBundleID = app?.bundleIdentifier ?? app?.localizedName ?? "unknown"
        openAppName = app?.localizedName ?? app?.bundleIdentifier ?? "Unknown"
        openStart = time
    }

    private func closeOpenSpan(at time: Date) {
        guard let openBundleID, let openAppName, let openStart else { return }
        let duration = max(0, time.timeIntervalSince(openStart))
        if duration > 0 {
            completedSpans.append(AppSpan(bundleID: openBundleID, appName: openAppName, start: openStart, duration: duration))
        }
        self.openBundleID = nil
        self.openAppName = nil
        self.openStart = nil
    }

    private func closeAway(at time: Date) {
        if let awayStart {
            awaySeconds += max(0, time.timeIntervalSince(awayStart))
        }
        awayStart = nil
    }

    // MARK: Events

    private func handleAppSwitch(to app: NSRunningApplication?, at time: Date = .now) {
        guard isRunning, awayStart == nil else { return }   // ignore switches while away
        let newID = app?.bundleIdentifier ?? app?.localizedName
        guard newID != openBundleID else { return }
        closeOpenSpan(at: time)
        openSpan(for: app, at: time)
        switchCount += 1
    }

    private func handleIdleChange(_ idle: Bool, at time: Date = .now) {
        guard isRunning else { return }
        if idle {
            guard awayStart == nil else { return }
            closeOpenSpan(at: time)
            awayStart = time
        } else {
            guard awayStart != nil else { return }
            closeAway(at: time)
            openSpan(for: NSWorkspace.shared.frontmostApplication, at: time)
        }
    }

    // MARK: Subscriptions

    private func subscribe() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { self?.handleAppSwitch(to: app) }
            },
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleIdleChange(true) }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleIdleChange(false) }
            },
        ]
        let distributed = DistributedNotificationCenter.default()
        lockObservers = [
            distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleIdleChange(true) }
            },
            distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleIdleChange(false) }
            },
        ]
    }

    private func unsubscribe() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { center.removeObserver($0) }
        workspaceObservers.removeAll()
        let distributed = DistributedNotificationCenter.default()
        lockObservers.forEach { distributed.removeObserver($0) }
        lockObservers.removeAll()
    }
}
