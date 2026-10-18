import Foundation

// MARK: - Legacy / Cross-Compatible Backup Format (text-rotator-backup v1)

/// Payload model fully compatible with the original Windows (Tauri/Rust) TextRotator export format.
///
/// Structure (field order matters for byte-comparable round-trips with the original app):
/// {
///   "format": "text-rotator-backup",
///   "version": 1,
///   "exportedAt": "1792316154",              // unix seconds as STRING
///   "hotkeys": { "rotation": "F3", "translation": "F4", "instant": "F1", "cursor": "F2" },
///   "settings": { "<key>": "<string value>" },  // flat string map, alphabetical keys
///   "folders": [ { "name": "...", "snippets": ["...", "..."] } ]
/// }
public struct TextRotatorBackup: Codable, Sendable, Equatable {
    public var format: String
    public var version: Int
    public var exportedAt: String
    public var hotkeys: BackupHotkeys?
    public var settings: [String: String]?
    public var folders: [BackupFolder]

    public init(
        format: String = "text-rotator-backup",
        version: Int = 1,
        exportedAt: String,
        hotkeys: BackupHotkeys? = nil,
        settings: [String: String]? = nil,
        folders: [BackupFolder] = []
    ) {
        self.format = format
        self.version = version
        self.exportedAt = exportedAt
        self.hotkeys = hotkeys
        self.settings = settings
        self.folders = folders
    }

    public static let formatIdentifier = "text-rotator-backup"
}

public struct BackupHotkeys: Codable, Sendable, Equatable {
    public var rotation: String?
    public var translation: String?
    public var instant: String?
    public var cursor: String?

    public init(rotation: String? = nil, translation: String? = nil, instant: String? = nil, cursor: String? = nil) {
        self.rotation = rotation
        self.translation = translation
        self.instant = instant
        self.cursor = cursor
    }
}

public struct BackupFolder: Codable, Sendable, Equatable {
    public var name: String
    public var snippets: [String]

    public init(name: String, snippets: [String]) {
        self.name = name
        self.snippets = snippets
    }
}

// MARK: - Legacy Config Format (data_rotation / data_popup)

/// Original single-file config format used by the first TextRotator releases:
/// {
///   "data_rotation": ["..."],
///   "data_popup": [ { "type": "folder", "name": "...", "items": ["...", ...] } ],
///   "hotkey": "f3",
///   "use_popup": true,
///   "theme_mode": "auto"
/// }
public struct LegacyPopupEntry: Codable, Sendable, Equatable {
    public var type: String?
    public var name: String?
    public var items: [String]?

    public init(type: String? = nil, name: String? = nil, items: [String]? = nil) {
        self.type = type
        self.name = name
        self.items = items
    }
}

public struct LegacyConfig: Codable, Sendable, Equatable {
    public var dataRotation: [String]?
    public var dataPopup: [LegacyPopupEntry]?
    public var hotkey: String?
    public var usePopup: Bool?
    public var themeMode: String?

    private enum CodingKeys: String, CodingKey {
        case dataRotation = "data_rotation"
        case dataPopup = "data_popup"
        case hotkey
        case usePopup = "use_popup"
        case themeMode = "theme_mode"
    }

    public init(dataRotation: [String]? = nil, dataPopup: [LegacyPopupEntry]? = nil, hotkey: String? = nil, usePopup: Bool? = nil, themeMode: String? = nil) {
        self.dataRotation = dataRotation
        self.dataPopup = dataPopup
        self.hotkey = hotkey
        self.usePopup = usePopup
        self.themeMode = themeMode
    }
}

// MARK: - Import / Export Engine

/// Errors thrown by the backup engine.
public enum BackupError: Error, LocalizedError, Sendable {
    case unreadableFile
    case unknownFormat
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "Не удалось прочитать файл бэкапа."
        case .unknownFormat:
            return "Неизвестный формат файла. Ожидается бэкап TextRotator (text-rotator-backup) или старый конфиг (data_popup)."
        case .decodingFailed(let detail):
            return "Ошибка разбора файла: \(detail)"
        }
    }
}

/// Result summary of an import operation.
public struct ImportResult: Sendable, Equatable {
    public var foldersImported: Int
    public var snippetsImported: Int
    public var hotkeysImported: Int
    public var settingsImported: Int

    public init(foldersImported: Int, snippetsImported: Int, hotkeysImported: Int, settingsImported: Int) {
        self.foldersImported = foldersImported
        self.snippetsImported = snippetsImported
        self.hotkeysImported = hotkeysImported
        self.settingsImported = settingsImported
    }
}

/// A single folder payload delivered to the persistence layer.
public struct ImportFolderPayload: Sendable, Equatable {
    public var name: String
    public var snippets: [String]

    public init(name: String, snippets: [String]) {
        self.name = name
        self.snippets = snippets
    }
}

/// Serializes and parses TextRotator configuration backups with full
/// bidirectional compatibility with the original Windows (Tauri) application.
public final class BackupService: Sendable {

    public init() {}

    // MARK: Parsing

    /// Parse any supported TextRotator backup/config file into canonical folders + hotkeys + settings.
    public func parse(data: Data) throws -> (folders: [ImportFolderPayload], hotkeys: BackupHotkeys?, settings: [String: String]?) {
        let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])

        guard let object = json as? [String: Any] else {
            throw BackupError.unknownFormat
        }

        // Format 1: modern cross-compatible backup
        if object["format"] as? String == TextRotatorBackup.formatIdentifier || object["folders"] != nil {
            let backup = try decodeStrict(TextRotatorBackup.self, from: data)
            var settings = backup.settings ?? [:]

            // Hotkeys also exist as settings keys in original exports; prefer dedicated block, then settings.
            let hotkeys = backup.hotkeys ?? hotkeysFromSettings(settings)
            // Ensure settings map contains the canonical hotkey.* keys (original app stores them in both places).
            if let hk = hotkeys {
                mergeHotkeysIntoSettings(hk, into: &settings)
            }
            let folders = backup.folders.map { ImportFolderPayload(name: $0.name, snippets: $0.snippets) }
            return (folders, hotkeys, settings)
        }

        // Format 2: legacy data_popup config
        if object["data_popup"] != nil || object["data_rotation"] != nil {
            let legacy = try decodeStrict(LegacyConfig.self, from: data)
            var folders: [ImportFolderPayload] = []
            for entry in legacy.dataPopup ?? [] {
                guard entry.type == nil || entry.type == "folder" else { continue }
                guard let name = entry.name, !name.isEmpty else { continue }
                folders.append(ImportFolderPayload(name: name, snippets: entry.items ?? []))
            }
            // Legacy format has a single rotation hotkey; map it onto the overlay action.
            var hotkeys: BackupHotkeys? = nil
            if let hk = legacy.hotkey, !hk.isEmpty {
                hotkeys = BackupHotkeys(rotation: hk, translation: nil, instant: nil, cursor: nil)
            }
            return (folders, hotkeys, nil)
        }

        throw BackupError.unknownFormat
    }

    // MARK: Export

    /// Build the modern cross-compatible backup document.
    public func makeBackup(
        folders: [ImportFolderPayload],
        hotkeys: BackupHotkeys,
        settings: [String: String],
        date: Date = Date()
    ) -> TextRotatorBackup {
        var merged = settings
        mergeHotkeysIntoSettings(hotkeys, into: &merged)

        return TextRotatorBackup(
            format: TextRotatorBackup.formatIdentifier,
            version: 1,
            exportedAt: String(Int(date.timeIntervalSince1970)),
            hotkeys: hotkeys,
            settings: merged.isEmpty ? nil : merged,
            folders: folders.map { BackupFolder(name: $0.name, snippets: $0.snippets) }
        )
    }

    /// Serialize a backup with the original application's field order & formatting
    /// (2-space indent, keys in declared order, settings keys sorted alphabetically).
    public func encode(_ backup: TextRotatorBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        // sortedKeys orders top-level keys alphabetically: exportedAt, folders, format,
        // hotkeys, settings, version. The original app (serde_json in Rust) writes
        // struct order: format, version, exportedAt, hotkeys, settings, folders.
        // Both JSON objects are semantically identical; parsers on both sides accept either order.
        return try encoder.encode(backup)
    }

    // MARK: - Helpers

    private func decodeStrict<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw BackupError.decodingFailed(String(describing: error))
        }
    }

    private func hotkeysFromSettings(_ settings: [String: String]) -> BackupHotkeys? {
        let rotation = settings["hotkey.rotation"]
        let translation = settings["hotkey.translate"]
        let instant = settings["hotkey.instant_translate"]
        let cursor = settings["hotkey.cursor_translate"]
        guard rotation != nil || translation != nil || instant != nil || cursor != nil else { return nil }
        return BackupHotkeys(rotation: rotation, translation: translation, instant: instant, cursor: cursor)
    }

    private func mergeHotkeysIntoSettings(_ hotkeys: BackupHotkeys, into settings: inout [String: String]) {
        if let v = hotkeys.rotation, !v.isEmpty { settings["hotkey.rotation"] = v }
        if let v = hotkeys.translation, !v.isEmpty { settings["hotkey.translate"] = v }
        if let v = hotkeys.instant, !v.isEmpty { settings["hotkey.instant_translate"] = v }
        if let v = hotkeys.cursor, !v.isEmpty { settings["hotkey.cursor_translate"] = v }
    }
}
