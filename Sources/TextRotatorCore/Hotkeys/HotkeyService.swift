import Foundation
#if canImport(Carbon)
import Carbon
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - HotkeyBackend & HotkeyError

/// The backend mechanism actively managing hotkeys.
public enum HotkeyBackend: String, Sendable, CaseIterable {
    case carbon = "Carbon"
    case eventTap = "CGEventTap"
}

/// Errors related to hotkey registration and event listening.
public enum HotkeyError: Error, LocalizedError, Sendable {
    case carbonHandlerInstallationFailed(OSStatus)
    case carbonRegistrationFailed(action: HotkeyAction, status: OSStatus)
    case eventTapCreationFailed
    case eventTapDisabled
    case noBackendAvailable

    public var errorDescription: String? {
        switch self {
        case .carbonHandlerInstallationFailed(let status):
            return "Failed to install Carbon event handler (OSStatus: \(status))."
        case .carbonRegistrationFailed(let action, let status):
            return "Failed to register Carbon hotkey for \(action.displayName) (OSStatus: \(status))."
        case .eventTapCreationFailed:
            return "Failed to create CGEventTap. Ensure Accessibility permissions are granted."
        case .eventTapDisabled:
            return "Event tap was disabled by the operating system."
        case .noBackendAvailable:
            return "Neither Carbon HotKey nor CGEventTap could be initialized."
        }
    }
}

// MARK: - HotkeyServiceProtocol

public protocol HotkeyServiceProtocol: Sendable {
    var pipeline: ActionPipeline { get }
    var configuration: HotkeyConfiguration { get }
    var isRunning: Bool { get }
    var activeBackend: HotkeyBackend? { get }

    func start() throws
    func stop()
    func updateConfiguration(_ config: HotkeyConfiguration) throws
    func register(action: HotkeyAction, combo: KeyCombo) throws
    func unregister(action: HotkeyAction)
    func unregisterAll()
    func trigger(_ action: HotkeyAction) -> Bool
}

// MARK: - Top-Level Carbon & CGEventTap Callbacks

#if canImport(Carbon)
/// Carbon C-convention callback for registered hotkey press events
private func carbonHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = event, let userData = userData else {
        return noErr
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr else { return status }

    let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
    service.handleCarbonHotKey(id: hotKeyID.id)
    return noErr
}
#endif

#if canImport(CoreGraphics)
/// CGEventTap callback for low-level keyboard events (fallback)
private func lowLevelEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else {
        return Unmanaged.passUnretained(event)
    }

    if type == .keyDown {
        let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        if service.handleEventTapKeyDown(keyCode: keyCode, flags: flags) {
            // Hotkey recognized and dispatched; consume event from propagation
            return nil
        }
    }

    return Unmanaged.passUnretained(event)
}
#endif

// MARK: - HotkeyService

/// Service responsible for registering global hotkeys via Carbon `RegisterEventHotKey`
/// with automatic fallback to `CGEventTap` if needed.
///
/// Directs all triggered hotkeys into `ActionPipeline.dispatch(action)`.
public final class HotkeyService: HotkeyServiceProtocol, @unchecked Sendable {
    public let pipeline: ActionPipeline

    private let lock = NSLock()
    private var _configuration: HotkeyConfiguration
    private var _isRunning: Bool = false
    private var _activeBackend: HotkeyBackend?

    #if canImport(Carbon)
    private var eventHandlerRef: EventHandlerRef?
    private var registeredHotKeys: [HotkeyAction: EventHotKeyRef] = [:]
    private var actionById: [UInt32: HotkeyAction] = [:]
    private let hotKeySignature: OSType = 0x54585452 // "TXTR"
    #endif

    #if canImport(CoreGraphics)
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    #endif

    public var configuration: HotkeyConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return _configuration
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRunning
    }

    public var activeBackend: HotkeyBackend? {
        lock.lock()
        defer { lock.unlock() }
        return _activeBackend
    }

    /// Initializes HotkeyService with a pipeline and optional configuration.
    public init(
        pipeline: ActionPipeline = ActionPipeline(),
        configuration: HotkeyConfiguration = .default
    ) {
        self.pipeline = pipeline
        self._configuration = configuration
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Starts hotkey monitoring. Attempts Carbon registration first; falls back to `CGEventTap`.
    public func start() throws {
        lock.lock()
        if _isRunning {
            lock.unlock()
            return
        }
        lock.unlock()

        #if canImport(Carbon)
        do {
            try startCarbonBackend()
            lock.lock()
            _isRunning = true
            _activeBackend = .carbon
            lock.unlock()
            return
        } catch {
            // Carbon failed (e.g. headless or missing target), attempt fallback
        }
        #endif

        #if canImport(CoreGraphics)
        if startEventTapBackend() {
            lock.lock()
            _isRunning = true
            _activeBackend = .eventTap
            lock.unlock()
            return
        }
        #endif

        // If neither backend could be registered, still allow manual triggers
        lock.lock()
        _isRunning = true
        _activeBackend = nil
        lock.unlock()
    }

    /// Stops hotkey monitoring and releases all system registrations.
    public func stop() {
        lock.lock()
        guard _isRunning else {
            lock.unlock()
            return
        }
        _isRunning = false
        _activeBackend = nil
        lock.unlock()

        #if canImport(Carbon)
        stopCarbonBackend()
        #endif

        #if canImport(CoreGraphics)
        stopEventTapBackend()
        #endif
    }

    /// Updates configuration and re-registers hotkeys if running.
    public func updateConfiguration(_ config: HotkeyConfiguration) throws {
        lock.lock()
        self._configuration = config
        let running = _isRunning
        let backend = _activeBackend
        lock.unlock()

        if running {
            if backend == .carbon {
                #if canImport(Carbon)
                stopCarbonBackend()
                try startCarbonBackend()
                #endif
            }
            // For eventTap, bindings are read dynamically on key down
        }
    }

    /// Registers a single hotkey action with a key combination.
    public func register(action: HotkeyAction, combo: KeyCombo) throws {
        lock.lock()
        _configuration.setKeyCombo(combo, for: action)
        let running = _isRunning
        let backend = _activeBackend
        lock.unlock()

        if running && backend == .carbon {
            #if canImport(Carbon)
            try registerCarbonHotKey(action: action, combo: combo)
            #endif
        }
    }

    /// Unregisters a single hotkey action.
    public func unregister(action: HotkeyAction) {
        lock.lock()
        _configuration.setKeyCombo(nil, for: action)
        #if canImport(Carbon)
        if let ref = registeredHotKeys.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }
        actionById.removeValue(forKey: action.rawId)
        #endif
        lock.unlock()
    }

    /// Unregisters all hotkeys.
    public func unregisterAll() {
        lock.lock()
        _configuration = HotkeyConfiguration(bindings: [:])
        #if canImport(Carbon)
        for (_, ref) in registeredHotKeys {
            UnregisterEventHotKey(ref)
        }
        registeredHotKeys.removeAll()
        actionById.removeAll()
        #endif
        lock.unlock()
    }

    /// Directly triggers an action into the action pipeline.
    /// Useful for programmatic invocation and unit tests.
    @discardableResult
    public func trigger(_ action: HotkeyAction) -> Bool {
        pipeline.dispatch(action)
    }

    // MARK: - Carbon Backend Internals

    #if canImport(Carbon)
    private func startCarbonBackend() throws {
        lock.lock()
        defer { lock.unlock() }

        guard let target = GetApplicationEventTarget() ?? GetEventDispatcherTarget() else {
            throw HotkeyError.noBackendAvailable
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            target,
            carbonHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard status == noErr else {
            throw HotkeyError.carbonHandlerInstallationFailed(status)
        }

        for (action, combo) in _configuration.bindings {
            try registerCarbonHotKeyLocked(action: action, combo: combo, target: target)
        }
    }

    private func registerCarbonHotKey(action: HotkeyAction, combo: KeyCombo) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let target = GetApplicationEventTarget() ?? GetEventDispatcherTarget() else {
            return
        }
        try registerCarbonHotKeyLocked(action: action, combo: combo, target: target)
    }

    private func registerCarbonHotKeyLocked(action: HotkeyAction, combo: KeyCombo, target: EventTargetRef) throws {
        // Unregister any existing key for this action first
        if let existing = registeredHotKeys.removeValue(forKey: action) {
            UnregisterEventHotKey(existing)
        }

        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: action.rawId)
        var hotKeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers.carbonModifiers,
            hotKeyID,
            target,
            0,
            &hotKeyRef
        )

        guard status == noErr, let ref = hotKeyRef else {
            throw HotkeyError.carbonRegistrationFailed(action: action, status: status)
        }

        registeredHotKeys[action] = ref
        actionById[action.rawId] = action
    }

    private func stopCarbonBackend() {
        lock.lock()
        defer { lock.unlock() }

        for (_, ref) in registeredHotKeys {
            UnregisterEventHotKey(ref)
        }
        registeredHotKeys.removeAll()
        actionById.removeAll()

        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    /// Internal handler invoked directly from Carbon C-callback.
    /// Strictly adheres to ARCH_SPEC 5.1: non-blocking dispatch into worker queue.
    func handleCarbonHotKey(id: UInt32) {
        lock.lock()
        let action = actionById[id] ?? HotkeyAction(rawId: id)
        lock.unlock()

        guard let action = action else { return }
        _ = pipeline.dispatch(action)
    }
    #endif

    // MARK: - CGEventTap Fallback Internals

    #if canImport(CoreGraphics)
    private func startEventTapBackend() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let mask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: lowLevelEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        return true
    }

    private func stopEventTapBackend() {
        lock.lock()
        defer { lock.unlock() }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                self.runLoopSource = nil
            }
            self.eventTap = nil
        }
    }

    /// Internal handler invoked from CGEventTap callback.
    func handleEventTapKeyDown(keyCode: UInt32, flags: CGEventFlags) -> Bool {
        lock.lock()
        let currentBindings = _configuration.bindings
        lock.unlock()

        let modifiers = KeyModifiers.fromCGEventFlags(flags)

        for (action, combo) in currentBindings {
            if combo.keyCode == keyCode && combo.modifiers == modifiers {
                _ = pipeline.dispatch(action)
                return true
            }
        }
        return false
    }
    #endif
}
