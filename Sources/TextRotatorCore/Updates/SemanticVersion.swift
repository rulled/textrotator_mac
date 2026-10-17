import Foundation

/// Semantic Version representation conforming to SemVer 2.0.0
public struct SemanticVersion: Comparable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public var description: String {
        if let prerelease, !prerelease.isEmpty {
            return "\(major).\(minor).\(patch)-\(prerelease)"
        }
        return "\(major).\(minor).\(patch)"
    }

    public init?(string: String) {
        var cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("v") {
            cleaned.removeFirst()
        }
        guard !cleaned.isEmpty else { return nil }

        let parts = cleaned.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        guard let firstPart = parts.first else { return nil }
        let versionCore = String(firstPart)
        self.prerelease = parts.count > 1 ? String(parts[1]) : nil

        let digits = versionCore.split(separator: ".").compactMap { Int($0) }
        guard digits.count >= 2 else { return nil }

        self.major = digits[0]
        self.minor = digits[1]
        self.patch = digits.count > 2 ? digits[2] : 0
    }

    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // A version without a pre-release is strictly higher than one with a pre-release for identical X.Y.Z
        if lhs.prerelease == nil && rhs.prerelease != nil { return false }
        if lhs.prerelease != nil && rhs.prerelease == nil { return true }
        if let lp = lhs.prerelease, let rp = rhs.prerelease {
            return lp.localizedStandardCompare(rp) == .orderedAscending
        }
        return false
    }
}
