import Foundation

public final class TranslationRouter: TranslationRouterProtocol, @unchecked Sendable {
    public let yandexProvider: TranslationProvider
    public let googleProvider: TranslationProvider

    public init(
        yandexProvider: TranslationProvider = YandexProvider(),
        googleProvider: TranslationProvider = GoogleProvider()
    ) {
        self.yandexProvider = yandexProvider
        self.googleProvider = googleProvider
    }

    public func translate(
        request: TranslationRequest,
        preferredProvider: String? = nil
    ) async throws -> TranslationResult {
        let preferred = preferredProvider ?? "Yandex"
        if preferred.caseInsensitiveCompare("Google") == .orderedSame {
            return try await googleProvider.translate(request: request)
        } else {
            return try await yandexProvider.translate(request: request)
        }
    }

    public func translateWithFallback(request: TranslationRequest) async throws -> TranslationResult {
        do {
            return try await yandexProvider.translate(request: request)
        } catch {
            do {
                return try await googleProvider.translate(request: request)
            } catch {
                throw TranslationError.allProvidersFailed
            }
        }
    }
}
