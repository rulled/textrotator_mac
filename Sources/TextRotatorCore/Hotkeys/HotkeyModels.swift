import Foundation
#if canImport(Carbon)
import Carbon
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - HotkeyAction

/// Actions that can be triggered via global hotkeys in TextRotator.
public enum HotkeyAction: String, Sendable, Hashable, Codable, CaseIterable {
    case quickSnippetsOverlay        // Default: F3
    case instantTranslateAndReplace  // Default: F1
    case translatorOverlay           // Default: F4
    case cursorTranslateToggle       // Default: F2

    public var displayName: String {
        switch self {
        case .quickSnippetsOverlay:
            return "Quick Snippets Overlay"
        case .instantTranslateAndReplace:
            return "Instant Translate & Replace"
        case .translatorOverlay:
            return "Translator Overlay"
        case .cursorTranslateToggle:
            return "Cursor Translate Toggle"
        }
    }

    public var defaultKeyString: String {
        switch self {
        case .quickSnippetsOverlay:
            return AppSettings.defaultRotationHotkey // F3
        case .instantTranslateAndReplace:
            return AppSettings.defaultInstantHotkey // F1
        case .translatorOverlay:
            return AppSettings.defaultTranslationHotkey // F4
        case .cursorTranslateToggle:
            return AppSettings.defaultCursorHotkey // F2
        }
    }

    public var rawId: UInt32 {
        switch self {
        case .instantTranslateAndReplace: return 1
        case .cursorTranslateToggle: return 2
        case .quickSnippetsOverlay: return 3
        case .translatorOverlay: return 4
        }
    }

    public init?(rawId: UInt32) {
        switch rawId {
        case 1: self = .instantTranslateAndReplace
        case 2: self = .cursorTranslateToggle
        case 3: self = .quickSnippetsOverlay
        case 4: self = .translatorOverlay
        default: return nil
        }
    }
}

// MARK: - KeyCode Constants

/// Virtual Key Codes (macOS Carbon / HIToolbox standard layout)
public enum KeyCode {
    // Function keys
    public static let f1: UInt32 = 0x7A // 122
    public static let f2: UInt32 = 0x78 // 120
    public static let f3: UInt32 = 0x63 // 99
    public static let f4: UInt32 = 0x76 // 118
    public static let f5: UInt32 = 0x60 // 96
    public static let f6: UInt32 = 0x61 // 97
    public static let f7: UInt32 = 0x62 // 98
    public static let f8: UInt32 = 0x64 // 100
    public static let f9: UInt32 = 0x65 // 101
    public static let f10: UInt32 = 0x6D // 109
    public static let f11: UInt32 = 0x67 // 103
    public static let f12: UInt32 = 0x6F // 111

    // Whitespace / Control keys
    public static let space: UInt32 = 0x31 // 49
    public static let returnKey: UInt32 = 0x24 // 36
    public static let tab: UInt32 = 0x30 // 48
    public static let escape: UInt32 = 0x35 // 53
    public static let delete: UInt32 = 0x33 // 51

    // Letter keys
    public static let a: UInt32 = 0x00
    public static let s: UInt32 = 0x01
    public static let d: UInt32 = 0x02
    public static let f: UInt32 = 0x03
    public static let h: UInt32 = 0x04
    public static let g: UInt32 = 0x05
    public static let z: UInt32 = 0x06
    public static let x: UInt32 = 0x07
    public static let c: UInt32 = 0x08
    public static let v: UInt32 = 0x09
    public static let b: UInt32 = 0x0B
    public static let q: UInt32 = 0x0C
    public static let w: UInt32 = 0x0D
    public static let e: UInt32 = 0x0E
    public static let r: UInt32 = 0x0F
    public static let y: UInt32 = 0x10
    public static let t: UInt32 = 0x11
    public static let o: UInt32 = 0x1F
    public static let u: UInt32 = 0x20
    public static let i: UInt32 = 0x22
    public static let p: UInt32 = 0x23
    public static let l: UInt32 = 0x25
    public static let j: UInt32 = 0x26
    public static let k: UInt32 = 0x28
    public static let n: UInt32 = 0x2D
    public static let m: UInt32 = 0x2E

    /// Parse a string name into a virtual key code
    public static func from(string: String) -> UInt32? {
        let lower = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lower {
        case "f1": return KeyCode.f1
        case "f2": return KeyCode.f2
        case "f3": return KeyCode.f3
        case "f4": return KeyCode.f4
        case "f5": return KeyCode.f5
        case "f6": return KeyCode.f6
        case "f7": return KeyCode.f7
        case "f8": return KeyCode.f8
        case "f9": return KeyCode.f9
        case "f10": return KeyCode.f10
        case "f11": return KeyCode.f11
        case "f12": return KeyCode.f12
        case "space": return KeyCode.space
        case "return", "enter": return KeyCode.returnKey
        case "tab": return KeyCode.tab
        case "escape", "esc": return KeyCode.escape
        case "delete", "backspace": return KeyCode.delete
        case "a": return KeyCode.a
        case "b": return KeyCode.b
        case "c": return KeyCode.c
        case "d": return KeyCode.d
        case "e": return KeyCode.e
        case "f": return KeyCode.f
        case "g": return KeyCode.g
        case "h": return KeyCode.h
        case "i": return KeyCode.i
        case "j": return KeyCode.j
        case "k": return KeyCode.k
        case "l": return KeyCode.l
        case "m": return KeyCode.m
        case "n": return KeyCode.n
        case "o": return KeyCode.o
        case "p": return KeyCode.p
        case "q": return KeyCode.q
        case "r": return KeyCode.r
        case "s": return KeyCode.s
        case "t": return KeyCode.t
        case "u": return KeyCode.u
        case "v": return KeyCode.v
        case "w": return KeyCode.w
        case "x": return KeyCode.x
        case "y": return KeyCode.y
        case "z": return KeyCode.z
        default: return nil
        }
    }

    /// Readable name for virtual key code
    public static func name(for keyCode: UInt32) -> String {
        switch keyCode {
        case KeyCode.f1: return "F1"
        case KeyCode.f2: return "F2"
        case KeyCode.f3: return "F3"
        case KeyCode.f4: return "F4"
        case KeyCode.f5: return "F5"
        case KeyCode.f6: return "F6"
        case KeyCode.f7: return "F7"
        case KeyCode.f8: return "F8"
        case KeyCode.f9: return "F9"
        case KeyCode.f10: return "F10"
        case KeyCode.f11: return "F11"
        case KeyCode.f12: return "F12"
        case KeyCode.space: return "Space"
        case KeyCode.returnKey: return "Return"
        case KeyCode.tab: return "Tab"
        case KeyCode.escape: return "Esc"
        case KeyCode.delete: return "Delete"
        case KeyCode.a: return "A"
        case KeyCode.b: return "B"
        case KeyCode.c: return "C"
        case KeyCode.d: return "D"
        case KeyCode.e: return "E"
        case KeyCode.f: return "F"
        case KeyCode.g: return "G"
        case KeyCode.h: return "H"
        case KeyCode.i: return "I"
        case KeyCode.j: return "J"
        case KeyCode.k: return "K"
        case KeyCode.l: return "L"
        case KeyCode.m: return "M"
        case KeyCode.n: return "N"
        case KeyCode.o: return "O"
        case KeyCode.p: return "P"
        case KeyCode.q: return "Q"
        case KeyCode.r: return "R"
        case KeyCode.s: return "S"
        case KeyCode.t: return "T"
        case KeyCode.u: return "U"
        case KeyCode.v: return "V"
        case KeyCode.w: return "W"
        case KeyCode.x: return "X"
        case KeyCode.y: return "Y"
        case KeyCode.z: return "Z"
        default: return "Key(\(keyCode))"
        }
    }
}

// MARK: - KeyModifiers

/// Modifier keys (Command, Shift, Option, Control)
public struct KeyModifiers: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift   = KeyModifiers(rawValue: 1 << 1)
    public static let option  = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)

    /// Carbon modifier mask for `RegisterEventHotKey`
    public var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if contains(.command) { carbon |= 0x0100 /* cmdKey */ }
        if contains(.shift)   { carbon |= 0x0200 /* shiftKey */ }
        if contains(.option)  { carbon |= 0x0800 /* optionKey */ }
        if contains(.control) { carbon |= 0x1000 /* controlKey */ }
        return carbon
    }

    /// Construct `KeyModifiers` from Carbon modifier bitmask
    public static func fromCarbonModifiers(_ carbon: UInt32) -> KeyModifiers {
        var mods: KeyModifiers = []
        if (carbon & 0x0100) != 0 { mods.insert(.command) }
        if (carbon & 0x0200) != 0 { mods.insert(.shift) }
        if (carbon & 0x0800) != 0 { mods.insert(.option) }
        if (carbon & 0x1000) != 0 { mods.insert(.control) }
        return mods
    }

    #if canImport(CoreGraphics)
    /// Construct `KeyModifiers` from `CGEventFlags`
    public static func fromCGEventFlags(_ flags: CGEventFlags) -> KeyModifiers {
        var mods: KeyModifiers = []
        if flags.contains(.maskCommand) { mods.insert(.command) }
        if flags.contains(.maskShift) { mods.insert(.shift) }
        if flags.contains(.maskAlternate) { mods.insert(.option) }
        if flags.contains(.maskControl) { mods.insert(.control) }
        return mods
    }
    #endif
}

// MARK: - KeyCombo

/// A key combination representing a key code and modifier flags
public struct KeyCombo: Codable, Sendable, Hashable, Equatable {
    public var keyCode: UInt32
    public var modifiers: KeyModifiers

    public init(keyCode: UInt32, modifiers: KeyModifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Parse key combo from textual representation like "F1", "Cmd+Shift+V", "⌥Space"
    public init?(string: String) {
        let normalized = string
            .replacingOccurrences(of: "⌘", with: "cmd ")
            .replacingOccurrences(of: "⇧", with: "shift ")
            .replacingOccurrences(of: "⌥", with: "option ")
            .replacingOccurrences(of: "⌃", with: "control ")

        let parts = normalized.split(whereSeparator: { $0 == "+" || $0 == "-" || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return nil }

        var parsedModifiers: KeyModifiers = []
        var parsedKeyCode: UInt32?

        for part in parts {
            switch part {
            case "cmd", "command":
                parsedModifiers.insert(.command)
            case "shift":
                parsedModifiers.insert(.shift)
            case "opt", "option", "alt":
                parsedModifiers.insert(.option)
            case "ctrl", "control":
                parsedModifiers.insert(.control)
            default:
                if let code = KeyCode.from(string: part) {
                    parsedKeyCode = code
                }
            }
        }

        guard let code = parsedKeyCode else { return nil }
        self.keyCode = code
        self.modifiers = parsedModifiers
    }

    /// User-friendly display string, e.g. "⌘⇧V", "F1", "⌥Space"
    public var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option)  { result += "⌥" }
        if modifiers.contains(.shift)   { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += KeyCode.name(for: keyCode)
        return result
    }
}

// MARK: - HotkeyBinding & HotkeyConfiguration

/// A single hotkey binding linking an action to a key combination
public struct HotkeyBinding: Codable, Sendable, Hashable, Equatable {
    public var action: HotkeyAction
    public var keyCombo: KeyCombo
    public var isEnabled: Bool

    public init(action: HotkeyAction, keyCombo: KeyCombo, isEnabled: Bool = true) {
        self.action = action
        self.keyCombo = keyCombo
        self.isEnabled = isEnabled
    }
}

/// Hotkey configuration storing bindings for all actions
public struct HotkeyConfiguration: Codable, Sendable, Hashable, Equatable {
    public var bindings: [HotkeyAction: KeyCombo]

    public init(bindings: [HotkeyAction: KeyCombo] = [:]) {
        self.bindings = bindings
    }

    /// Default hotkey configuration based on AppSettings and ARCH_SPEC
    public static var `default`: HotkeyConfiguration {
        HotkeyConfiguration(bindings: [
            .instantTranslateAndReplace: KeyCombo(keyCode: KeyCode.f1),
            .cursorTranslateToggle: KeyCombo(keyCode: KeyCode.f2),
            .quickSnippetsOverlay: KeyCombo(keyCode: KeyCode.f3),
            .translatorOverlay: KeyCombo(keyCode: KeyCode.f4)
        ])
    }

    /// Initializer from hotkey string settings
    public init(
        rotation: String = AppSettings.defaultRotationHotkey,
        translation: String = AppSettings.defaultTranslationHotkey,
        instant: String = AppSettings.defaultInstantHotkey,
        cursor: String = AppSettings.defaultCursorHotkey
    ) {
        var map: [HotkeyAction: KeyCombo] = [:]
        map[.quickSnippetsOverlay] = KeyCombo(string: rotation) ?? KeyCombo(keyCode: KeyCode.f3)
        map[.translatorOverlay] = KeyCombo(string: translation) ?? KeyCombo(keyCode: KeyCode.f4)
        map[.instantTranslateAndReplace] = KeyCombo(string: instant) ?? KeyCombo(keyCode: KeyCode.f1)
        map[.cursorTranslateToggle] = KeyCombo(string: cursor) ?? KeyCombo(keyCode: KeyCode.f2)
        self.bindings = map
    }

    public func keyCombo(for action: HotkeyAction) -> KeyCombo? {
        bindings[action]
    }

    public mutating func setKeyCombo(_ combo: KeyCombo?, for action: HotkeyAction) {
        bindings[action] = combo
    }
}
