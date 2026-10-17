import Foundation

public struct TranslationRequest: Sendable, Equatable {
    public let text: String
    public let sourceLanguage: String // e.g. "auto", "ru", "en"
    public let targetLanguage: String // e.g. "ru", "en"
    
    public init(text: String, sourceLanguage: String = "auto", targetLanguage: String? = nil) {
        self.text = text
        let isCyrillic = text.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil
        if sourceLanguage == "auto" {
            self.sourceLanguage = isCyrillic ? "ru" : "auto"
        } else {
            self.sourceLanguage = sourceLanguage
        }
        self.targetLanguage = targetLanguage ?? (isCyrillic ? "en" : "ru")
    }
}

public struct TranslationResult: Sendable, Equatable {
    public let translatedText: String
    public let detectedSourceLanguage: String
    public let targetLanguage: String
    public let providerName: String
    public let latencyMs: Int

    public init(
        translatedText: String,
        detectedSourceLanguage: String,
        targetLanguage: String,
        providerName: String,
        latencyMs: Int
    ) {
        self.translatedText = translatedText
        self.detectedSourceLanguage = detectedSourceLanguage
        self.targetLanguage = targetLanguage
        self.providerName = providerName
        self.latencyMs = latencyMs
    }
}

public enum TranslationError: Error, LocalizedError, Sendable, Equatable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case parsingError(String)
    case allProvidersFailed

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid translation request URL."
        case .invalidResponse:
            return "Received invalid response from translation server."
        case let .httpError(statusCode, message):
            return "Translation HTTP error \(statusCode): \(message)"
        case let .parsingError(message):
            return "Failed to parse translation response: \(message)"
        case .allProvidersFailed:
            return "All translation providers failed."
        }
    }
}

public protocol TranslationProvider: Sendable {
    var name: String { get }
    func translate(request: TranslationRequest) async throws -> TranslationResult
}

public protocol TranslationRouterProtocol: Sendable {
    func translate(request: TranslationRequest, preferredProvider: String?) async throws -> TranslationResult
    func translateWithFallback(request: TranslationRequest) async throws -> TranslationResult
}
