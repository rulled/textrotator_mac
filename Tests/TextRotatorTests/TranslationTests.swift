import XCTest
@testable import TextRotatorCore

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            XCTFail("MockURLProtocol.requestHandler is not set.")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
private extension URLRequest {
    var bodyData: Data? {
        if let data = httpBody { return data }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 1024)
        var data = Data()
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }
}


final class TranslationTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testLanguageAutoDetectionCyrillic() {
        let requestRu = TranslationRequest(text: "Привет, мир!")
        XCTAssertEqual(requestRu.sourceLanguage, "ru")
        XCTAssertEqual(requestRu.targetLanguage, "en")

        let requestMixed = TranslationRequest(text: "Hello, мир!")
        XCTAssertEqual(requestMixed.sourceLanguage, "ru")
        XCTAssertEqual(requestMixed.targetLanguage, "en")
    }

    func testLanguageAutoDetectionNonCyrillic() {
        let requestEn = TranslationRequest(text: "Hello world!")
        XCTAssertEqual(requestEn.sourceLanguage, "auto")
        XCTAssertEqual(requestEn.targetLanguage, "ru")

        let requestNumbers = TranslationRequest(text: "12345 !@#$")
        XCTAssertEqual(requestNumbers.sourceLanguage, "auto")
        XCTAssertEqual(requestNumbers.targetLanguage, "ru")
    }

    func testExplicitLanguageOverride() {
        let request = TranslationRequest(text: "Привет", sourceLanguage: "ru", targetLanguage: "de")
        XCTAssertEqual(request.sourceLanguage, "ru")
        XCTAssertEqual(request.targetLanguage, "de")
    }

    func testYandexProviderRequestAndParsing() async throws {
        let session = makeMockSession()
        let provider = YandexProvider(session: session)

        let expectedTranslated = "Hello world"
        let mockJson = """
        {
            "code": 200,
            "lang": "ru-en",
            "text": ["\(expectedTranslated)"]
        }
        """

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36 YaBrowser/24.7.1.0")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://www.youtube.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://www.youtube.com/")

            let urlString = request.url?.absoluteString ?? ""
            XCTAssertTrue(urlString.contains("browser.translate.yandex.net"))
            XCTAssertTrue(urlString.contains("lang=ru-en"))

            let bodyString = request.bodyData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            XCTAssertTrue(bodyString.contains("text="))

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, mockJson.data(using: .utf8)!)
        }

        let request = TranslationRequest(text: "Привет мир")
        let result = try await provider.translate(request: request)

        XCTAssertEqual(result.translatedText, expectedTranslated)
        XCTAssertEqual(result.detectedSourceLanguage, "ru")
        XCTAssertEqual(result.targetLanguage, "en")
        XCTAssertEqual(result.providerName, "Yandex")
    }

    func testGoogleProviderRequestAndParsing() async throws {
        let session = makeMockSession()
        let provider = GoogleProvider(session: session)

        let mockJson = """
        [[["Привет мир","Hello world",null,null,1]],null,"en"]
        """

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://translate.google.com/")

            let url = request.url!
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            XCTAssertEqual(components?.host, "translate.googleapis.com")

            let items = components?.queryItems ?? []
            XCTAssertTrue(items.contains(where: { $0.name == "client" && $0.value == "dict-chrome-ex" }))
            XCTAssertTrue(items.contains(where: { $0.name == "sl" && $0.value == "auto" }))
            XCTAssertTrue(items.contains(where: { $0.name == "tl" && $0.value == "ru" }))
            XCTAssertTrue(items.contains(where: { $0.name == "q" && $0.value == "Hello world" }))

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, mockJson.data(using: .utf8)!)
        }

        let request = TranslationRequest(text: "Hello world")
        let result = try await provider.translate(request: request)

        XCTAssertEqual(result.translatedText, "Привет мир")
        XCTAssertEqual(result.detectedSourceLanguage, "en")
        XCTAssertEqual(result.targetLanguage, "ru")
        XCTAssertEqual(result.providerName, "Google")
    }

    func testTranslationRouterFallback() async throws {
        let session = makeMockSession()
        let yandex = YandexProvider(session: session)
        let google = GoogleProvider(session: session)
        let router = TranslationRouter(yandexProvider: yandex, googleProvider: google)

        MockURLProtocol.requestHandler = { request in
            let host = request.url?.host ?? ""
            if host.contains("yandex") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            } else {
                let mockJson = """
                [[["Успешный фоллбэк","Successful fallback",null,null,1]],null,"en"]
                """
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, mockJson.data(using: .utf8)!)
            }
        }

        let request = TranslationRequest(text: "Successful fallback")
        let result = try await router.translateWithFallback(request: request)

        XCTAssertEqual(result.providerName, "Google")
        XCTAssertEqual(result.translatedText, "Успешный фоллбэк")
    }
}
