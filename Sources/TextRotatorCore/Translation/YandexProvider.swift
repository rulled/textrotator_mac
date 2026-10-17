import Foundation

public final class YandexProvider: TranslationProvider, @unchecked Sendable {
    public let name: String = "Yandex"
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func translate(request: TranslationRequest) async throws -> TranslationResult {
        let startTime = DispatchTime.now()

        let source = request.sourceLanguage == "auto" ? "en" : request.sourceLanguage
        let target = request.targetLanguage
        let urlString = "https://browser.translate.yandex.net/api/v1/tr.json/translate?srv=browser_video_translation&lang=\(source)-\(target)"

        guard let url = URL(string: urlString) else {
            throw TranslationError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36 YaBrowser/24.7.1.0", forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        urlRequest.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")

        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "text", value: request.text)]
        urlRequest.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: urlRequest)

        let endTime = DispatchTime.now()
        let elapsedNanoseconds = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let latencyMs = Int(elapsedNanoseconds / 1_000_000)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Status code \(httpResponse.statusCode)"
            throw TranslationError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        struct YandexResponse: Decodable {
            let code: Int
            let lang: String
            let text: [String]
        }

        let decoded: YandexResponse
        do {
            decoded = try JSONDecoder().decode(YandexResponse.self, from: data)
        } catch {
            throw TranslationError.parsingError("Yandex JSON decoding failed: \(error.localizedDescription)")
        }

        guard let translatedText = decoded.text.first else {
            throw TranslationError.parsingError("Yandex response contained no text array elements")
        }

        let langParts = decoded.lang.split(separator: "-")
        let detectedSource = langParts.first.map(String.init) ?? source
        let detectedTarget = langParts.count > 1 ? String(langParts[1]) : target

        return TranslationResult(
            translatedText: translatedText,
            detectedSourceLanguage: detectedSource,
            targetLanguage: detectedTarget,
            providerName: name,
            latencyMs: latencyMs
        )
    }
}
