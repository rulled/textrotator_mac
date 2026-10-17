import Foundation
import TextRotatorCore

public struct GitHubRelease: Codable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let publishedAt: String?
    public let htmlUrl: URL
    public let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case publishedAt = "published_at"
        case htmlUrl = "html_url"
        case assets
    }

    public var semanticVersion: SemanticVersion? {
        SemanticVersion(string: tagName)
    }

    public var zipAsset: GitHubReleaseAsset? {
        // Priority 1: Exact TextRotator.zip
        if let exact = assets.first(where: { $0.name == "TextRotator.zip" }) {
            return exact
        }
        // Priority 2: TextRotator-*.zip
        if let prefixed = assets.first(where: { $0.name.hasPrefix("TextRotator") && $0.name.hasSuffix(".zip") }) {
            return prefixed
        }
        // Priority 3: Any zip content type
        return assets.first(where: { $0.contentType == "application/zip" || $0.name.hasSuffix(".zip") })
    }
}

public struct GitHubReleaseAsset: Codable, Sendable {
    public let name: String
    public let contentType: String
    public let size: Int64
    public let browserDownloadUrl: URL

    enum CodingKeys: String, CodingKey {
        case name
        case contentType = "content_type"
        case size
        case browserDownloadUrl = "browser_download_url"
    }
}

public struct UpdateInfo: Sendable, Identifiable, Equatable {
    public var id: String { version.description }
    public let version: SemanticVersion
    public let currentVersion: SemanticVersion
    public let releaseNotes: String
    public let downloadURL: URL
    public let zipSize: Int64
    public let htmlURL: URL

    public static func == (lhs: UpdateInfo, rhs: UpdateInfo) -> Bool {
        lhs.id == rhs.id
    }
}
