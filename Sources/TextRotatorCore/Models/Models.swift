import Foundation

public struct FolderSummary: Identifiable, Codable, Sendable, Equatable {
    public let id: Int64
    public var name: String
    public var position: Int64
    public var snippetCount: Int64

    public init(id: Int64, name: String, position: Int64, snippetCount: Int64 = 0) {
        self.id = id
        self.name = name
        self.position = position
        self.snippetCount = snippetCount
    }
}

public struct SnippetItem: Identifiable, Codable, Sendable, Equatable {
    public let id: Int64
    public var folderId: Int64
    public var content: String
    public var position: Int64
    public var createdAt: String?

    public init(id: Int64, folderId: Int64, content: String, position: Int64, createdAt: String? = nil) {
        self.id = id
        self.folderId = folderId
        self.content = content
        self.position = position
        self.createdAt = createdAt
    }
}

public struct FolderWithSnippets: Identifiable, Codable, Sendable, Equatable {
    public let id: Int64
    public var name: String
    public var position: Int64
    public var snippets: [SnippetItem]

    public init(id: Int64, name: String, position: Int64, snippets: [SnippetItem] = []) {
        self.id = id
        self.name = name
        self.position = position
        self.snippets = snippets
    }
}

public struct SnippetSearchResult: Identifiable, Codable, Sendable, Equatable {
    public let id: Int64
    public let folderId: Int64
    public let folderName: String
    public let content: String
    public let position: Int64

    public init(id: Int64, folderId: Int64, folderName: String, content: String, position: Int64) {
        self.id = id
        self.folderId = folderId
        self.folderName = folderName
        self.content = content
        self.position = position
    }
}

public struct AppSettings: Codable, Sendable {
    public static let defaultPrimaryProvider = "Yandex"
    public static let defaultRotationHotkey = "F3"
    public static let defaultTranslationHotkey = "F4"
    public static let defaultInstantHotkey = "F1"
    public static let defaultCursorHotkey = "F2"
}
