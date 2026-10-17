import Foundation

/// Non-blocking action pipeline that processes hotkey events with debouncing and concurrency guarding.
///
/// Dispatches work to a dedicated high-priority background queue (`com.textrotator.hotkeys.worker`)
/// and prevents re-entrant text captures or UI freezes.
public final class ActionPipeline: @unchecked Sendable {
    /// Non-blocking worker queue with userInteractive QoS
    public let workerQueue: DispatchQueue

    /// Debounce interval per action type (default: 180 ms = 0.180 s)
    public var debounceInterval: TimeInterval

    /// Whether `isOperationInProgress` should automatically reset to `false` when handler finishes
    public var autoResetOperationInProgress: Bool

    /// Callback types for handlers
    public typealias ActionHandler = @Sendable (HotkeyAction) -> Void
    public typealias AsyncActionHandler = @Sendable (HotkeyAction) async -> Void

    private let lock = NSLock()
    private var _isOperationInProgress: Bool = false
    private var lastActionTimes: [HotkeyAction: Date] = [:]
    private var subscribers: [UUID: ActionHandler] = [:]
    private var asyncHandler: AsyncActionHandler?

    /// Atomic/thread-safe flag indicating if a text capture or translation operation is currently running.
    public var isOperationInProgress: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isOperationInProgress
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isOperationInProgress = newValue
        }
    }

    /// Creates an ActionPipeline instance.
    /// - Parameters:
    ///   - workerQueue: Dedicated queue for hotkey execution. Defaults to `com.textrotator.hotkeys.worker`.
    ///   - debounceInterval: Minimum interval between identical actions in seconds. Defaults to 0.180 (180ms).
    ///   - autoResetOperationInProgress: When true, resets `isOperationInProgress` to false after handler runs.
    public init(
        workerQueue: DispatchQueue = DispatchQueue(label: "com.textrotator.hotkeys.worker", qos: .userInteractive),
        debounceInterval: TimeInterval = 0.180,
        autoResetOperationInProgress: Bool = true
    ) {
        self.workerQueue = workerQueue
        self.debounceInterval = debounceInterval
        self.autoResetOperationInProgress = autoResetOperationInProgress
    }

    /// Thread-safe update for `isOperationInProgress`.
    public func setOperationInProgress(_ inProgress: Bool) {
        self.isOperationInProgress = inProgress
    }

    /// Attempts to manually acquire the operation lock. Returns true if acquired.
    public func beginOperation() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _isOperationInProgress {
            return false
        }
        _isOperationInProgress = true
        return true
    }

    /// Manually releases the operation lock.
    public func endOperation() {
        setOperationInProgress(false)
    }

    // MARK: - Subscriptions

    /// Subscribes a handler callback to hotkey actions.
    /// - Parameter handler: Closure executed on the worker queue when an action is accepted.
    /// - Returns: A unique identifier for unsubscribing.
    @discardableResult
    public func subscribe(_ handler: @escaping ActionHandler) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let id = UUID()
        subscribers[id] = handler
        return id
    }

    /// Removes a previously registered subscriber.
    public func unsubscribe(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        subscribers.removeValue(forKey: id)
    }

    /// Replaces all subscribers with a single synchronous handler.
    public func setHandler(_ handler: @escaping ActionHandler) {
        lock.lock()
        defer { lock.unlock() }
        subscribers.removeAll()
        let id = UUID()
        subscribers[id] = handler
        asyncHandler = nil
    }

    /// Configures an asynchronous handler. When set, `isOperationInProgress` remains true
    /// until the async handler completes.
    public func setAsyncHandler(_ handler: @escaping AsyncActionHandler) {
        lock.lock()
        defer { lock.unlock() }
        self.asyncHandler = handler
    }

    /// Removes all subscribers and asynchronous handlers.
    public func removeAllHandlers() {
        lock.lock()
        defer { lock.unlock() }
        subscribers.removeAll()
        asyncHandler = nil
    }

    // MARK: - Dispatching

    /// Dispatches a hotkey action through the pipeline.
    ///
    /// 1. Checks 180 ms debounce for the specific action type.
    /// 2. Checks `isOperationInProgress` concurrency guard.
    /// 3. If accepted, marks operation in progress and posts work non-blockingly to `workerQueue`.
    ///
    /// - Parameter action: The hotkey action to trigger.
    /// - Returns: `true` if the action was accepted and scheduled; `false` if rejected due to debounce or active operation.
    @discardableResult
    public func dispatch(_ action: HotkeyAction) -> Bool {
        lock.lock()
        let now = Date()

        // 1. Debounce check per action type
        if let lastTime = lastActionTimes[action] {
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed < debounceInterval {
                lock.unlock()
                return false
            }
        }

        // 2. Concurrency guard: isOperationInProgress
        if _isOperationInProgress {
            lock.unlock()
            return false
        }

        // Accept action: update debounce timestamp and set operation flag
        lastActionTimes[action] = now
        _isOperationInProgress = true

        let activeSubscribers = Array(subscribers.values)
        let activeAsyncHandler = asyncHandler
        let shouldAutoReset = autoResetOperationInProgress
        lock.unlock()

        // 3. Non-blocking dispatch to worker queue
        workerQueue.async { [weak self] in
            guard let self = self else { return }

            if let asyncHandler = activeAsyncHandler {
                Task {
                    await asyncHandler(action)
                    if shouldAutoReset {
                        self.setOperationInProgress(false)
                    }
                }
            } else {
                for subscriber in activeSubscribers {
                    subscriber(action)
                }
                if shouldAutoReset {
                    self.setOperationInProgress(false)
                }
            }
        }

        return true
    }

    // MARK: - Testing & Inspection Helpers

    /// Resets debounce timestamp for a specific action or all actions.
    public func resetDebounce(for action: HotkeyAction? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let action = action {
            lastActionTimes.removeValue(forKey: action)
        } else {
            lastActionTimes.removeAll()
        }
    }

    /// Returns the last dispatch timestamp for an action, if any.
    public func lastDispatchTime(for action: HotkeyAction) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return lastActionTimes[action]
    }
}
