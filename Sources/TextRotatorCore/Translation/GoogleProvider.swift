import Foundation

public final class GoogleProvider: TranslationProvider, @unchecked Sendable {
    public let name: String = "Google"
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func translate(request: TranslationRequest) async throws -> TranslationResult {
        let startTime = DispatchTime.now()

        let source = request.sourceLanguage
        let target = request.targetLanguage

        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "dict-chrome-ex"),
            URLQueryItem(name: "sl", value: source),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "hl", value: "en"),
            URLQueryItem(name: "dt", value: "bd"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "dt", value: "ld"),
            URLQueryItem(name: "dt", value: "rm"),
            URLQueryItem(name: "q", value: request.text)
        ]

        guard let url = components?.url else {
            throw TranslationError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("https://translate.google.com/", forHTTPHeaderField: "Referer")

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

        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let rootArray = jsonObject as? [Any] else {
            throw TranslationError.parsingError("Google response is not a valid JSON array")
        }

        guard !rootArray.isEmpty, let sentencesArray = rootArray[0] as? [Any] else {
            throw TranslationError.parsingError("Google response missing sentences chunk array")
        }

        var translatedText = ""
        for item in sentencesArray {
            if let sentenceChunk = item as? [Any], !sentenceChunk.isEmpty, let chunkText = sentenceChunk[0] as? String {
                translatedText += chunkText
            }
        }

        guard !translatedText.isEmpty else {
            throw TranslationError.parsingError("Google translated text is empty")
        }

        var detectedSource = source
        if rootArray.count > 2, let detected = rootArray[2] as? String, !detected.isEmpty {
            detectedSource = detected
        } else if detectedSource == "auto" {
            detectedSource = (request.targetLanguage == "en") ? "ru" : "en"
        }

        return TranslationResult(
            translatedText: translatedText,
            detectedSourceLanguage: detectedSource,
            targetLanguage: target,
            providerName: name,
            latencyMs: latencyMs
        )
    }
}
