import Foundation

/// Unified search item representing either a matching Folder or a Snippet.
public enum SmartSearchItem: Identifiable, Equatable, Sendable {
    case folder(folder: FolderWithSnippets, score: Double)
    case snippet(snippet: SnippetItem, folderName: String, folderId: Int64, score: Double)

    public var id: String {
        switch self {
        case .folder(let f, _):
            return "f_\(f.id)"
        case .snippet(let s, _, _, _):
            return "s_\(s.id)"
        }
    }

    public var score: Double {
        switch self {
        case .folder(_, let s):
            return s
        case .snippet(_, _, _, let s):
            return s
        }
    }

    public var isFolder: Bool {
        switch self {
        case .folder: return true
        case .snippet: return false
        }
    }
}

/// Battle-tested search engine combining:
/// 1. Bi-directional QWERTY ↔ ЙЦУКЕН keyboard layout inversion.
/// 2. Russian 'ё' ↔ 'е' normalization and case folding.
/// 3. Subsequence fuzzy scoring with word-boundary, prefix, and consecutive bonuses (fzy algorithm).
/// 4. Damerau-Levenshtein typo tolerance (adjacent transpositions, insertions, deletions, substitutions).
public struct SmartSearchEngine: Sendable {

    public init() {}

    // MARK: - QWERTY ↔ ЙЦУКЕН Layout Maps

    private static let enToRuMap: [Character: Character] = [
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з", "[": "х", "]": "ъ",
        "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л", "l": "д", ";": "ж", "'": "э",
        "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь", ",": "б", ".": "ю",
        "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е", "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З", "{": "Х", "}": "Ъ",
        "A": "Ф", "S": "Ы", "D": "В", "F": "А", "G": "П", "H": "Р", "J": "О", "K": "Л", "L": "Д", ":": "Ж", "\"": "Э",
        "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И", "N": "Т", "M": "Ь", "<": "Б", ">": "Ю",
        "`": "ё", "~": "Ё", "@": "\"", "#": "№", "$": ";", "^": ":", "&": "?"
    ]

    private static let ruToEnMap: [Character: Character] = {
        var map = [Character: Character]()
        for (en, ru) in enToRuMap {
            map[ru] = en
        }
        return map
    }()

    /// Inverts the keyboard layout of a string (EN -> RU or RU -> EN).
    public static func invertKeyboardLayout(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = ""
        result.reserveCapacity(text.count)

        for char in text {
            if let ru = enToRuMap[char] {
                result.append(ru)
            } else if let en = ruToEnMap[char] {
                result.append(en)
            } else {
                result.append(char)
            }
        }
        return result
    }

    /// Normalizes text for matching:
    /// - Lowercases
    /// - Replaces 'ё' with 'е'
    /// - Trims whitespaces
    public static func normalize(_ text: String) -> String {
        return text
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Core Matching & Scoring

    /// Computes a match score between query and candidate string.
    /// Returns 0.0 if there is no match.
    public static func calculateScore(query: String, candidate: String) -> Double {
        let normCandidate = normalize(candidate)
        let normQuery = normalize(query)

        guard !normQuery.isEmpty, !normCandidate.isEmpty else { return 0.0 }

        // Test with original query
        let score1 = scoreSingleQuery(normQuery: normQuery, normCandidate: normCandidate)

        // Test with keyboard inverted query
        let invertedQuery = normalize(invertKeyboardLayout(query))
        let score2: Double
        if invertedQuery != normQuery {
            score2 = scoreSingleQuery(normQuery: invertedQuery, normCandidate: normCandidate)
        } else {
            score2 = 0.0
        }

        return max(score1, score2)
    }

    private static func scoreSingleQuery(normQuery: String, normCandidate: String) -> Double {
        // 1. Exact match
        if normCandidate == normQuery {
            return 1000.0
        }

        // 2. Prefix match
        if normCandidate.hasPrefix(normQuery) {
            let lengthPenalty = Double(normCandidate.count - normQuery.count) * 0.1
            return max(700.0 - lengthPenalty, 500.0)
        }

        // 3. Word boundary match (e.g. candidate contains word starting with query)
        let words = normCandidate.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { !$0.isEmpty }

        for (index, word) in words.enumerated() {
            if word == normQuery {
                return max(600.0 - Double(index) * 10.0, 450.0)
            }
            if word.hasPrefix(normQuery) {
                return max(500.0 - Double(index) * 10.0, 350.0)
            }
        }

        // 4. Substring match
        if let range = normCandidate.range(of: normQuery) {
            let distance = normCandidate.distance(from: normCandidate.startIndex, to: range.lowerBound)
            let score = 400.0 - Double(distance) * 2.0
            return max(score, 250.0)
        }

        // 5. fzy Fuzzy Subsequence Match
        if let fzyScore = calculateFzyScore(query: normQuery, candidate: normCandidate) {
            return fzyScore
        }

        // 6. Typo Tolerance via Damerau-Levenshtein
        if let typoScore = calculateTypoScore(query: normQuery, candidateWords: words) {
            return typoScore
        }

        return 0.0
    }

    // MARK: - fzy Fuzzy Subsequence Scoring

    private static func calculateFzyScore(query: String, candidate: String) -> Double? {
        let qChars = Array(query)
        let cChars = Array(candidate)

        guard qChars.count <= cChars.count else { return nil }

        var qIdx = 0
        var cIdx = 0
        var consecutiveMatches = 0
        var score: Double = 150.0
        var lastMatchedIdx = -1

        while qIdx < qChars.count && cIdx < cChars.count {
            if qChars[qIdx] == cChars[cIdx] {
                // Consecutive match bonus
                if lastMatchedIdx == cIdx - 1 {
                    consecutiveMatches += 1
                    score += 15.0 * Double(consecutiveMatches)
                } else {
                    consecutiveMatches = 0
                    if lastMatchedIdx != -1 {
                        // Gap penalty
                        score -= Double(cIdx - lastMatchedIdx - 1) * 2.0
                    }
                }

                // Word boundary bonus
                if cIdx == 0 {
                    score += 25.0
                } else {
                    let prevChar = cChars[cIdx - 1]
                    if prevChar.isWhitespace || prevChar.isPunctuation || prevChar == "-" || prevChar == "_" || prevChar == "/" {
                        score += 20.0
                    }
                }

                lastMatchedIdx = cIdx
                qIdx += 1
            }
            cIdx += 1
        }

        // If not all query characters were matched, it's not a subsequence
        guard qIdx == qChars.count else { return nil }

        // Penalize overall length to favor shorter/cleaner matches
        score -= Double(cChars.count - qChars.count) * 0.2
        return max(score, 50.0)
    }

    // MARK: - Damerau-Levenshtein Typo Distance

    private static func calculateTypoScore(query: String, candidateWords: [String]) -> Double? {
        guard query.count >= 3 else { return nil }
        let maxAllowedDistance = (query.count >= 7) ? 2 : 1

        var bestDistance = Int.max
        for word in candidateWords {
            guard abs(word.count - query.count) <= maxAllowedDistance else { continue }
            let dist = damerauLevenshteinDistance(query, word)
            if dist <= maxAllowedDistance && dist < bestDistance {
                bestDistance = dist
            }
        }

        guard bestDistance <= maxAllowedDistance else { return nil }
        // Typo score sits below exact/fuzzy, but above threshold
        return 90.0 - Double(bestDistance) * 25.0
    }

    /// Computes Damerau-Levenshtein distance with adjacent transpositions.
    public static func damerauLevenshteinDistance(_ source: String, _ target: String) -> Int {
        let s = Array(source)
        let t = Array(target)
        let n = s.count
        let m = t.count

        guard n > 0 else { return m }
        guard m > 0 else { return n }

        var d = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)

        for i in 0...n { d[i][0] = i }
        for j in 0...m { d[0][j] = j }

        for i in 1...n {
            for j in 1...m {
                let cost = (s[i - 1] == t[j - 1]) ? 0 : 1

                d[i][j] = min(
                    d[i - 1][j] + 1,       // deletion
                    d[i][j - 1] + 1,       // insertion
                    d[i - 1][j - 1] + cost // substitution
                )

                // Transposition
                if i > 1 && j > 1 && s[i - 1] == t[j - 2] && s[i - 2] == t[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }

        return d[n][m]
    }

    // MARK: - Unified Search API

    /// Performs unified search across folders and snippets.
    /// - If `query` is empty: returns all folders in position order (score: 0.0).
    /// - If `query` is non-empty: returns matching folders and snippets ranked by score.
    public static func search(query: String, in folders: [FolderWithSnippets]) -> [SmartSearchItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            return folders.map { .folder(folder: $0, score: 0.0) }
        }

        var results: [SmartSearchItem] = []

        // 1. Search folders
        for folder in folders {
            let score = calculateScore(query: trimmedQuery, candidate: folder.name)
            if score > 0 {
                // Boost folder score slightly when user specifically searches folder name
                results.append(.folder(folder: folder, score: score + 15.0))
            }
        }

        // 2. Search snippets
        for folder in folders {
            for snippet in folder.snippets {
                let score = calculateScore(query: trimmedQuery, candidate: snippet.content)
                if score > 0 {
                    results.append(.snippet(
                        snippet: snippet,
                        folderName: folder.name,
                        folderId: folder.id,
                        score: score
                    ))
                }
            }
        }

        // 3. Sort by score descending
        return results.sorted { $0.score > $1.score }
    }
}
