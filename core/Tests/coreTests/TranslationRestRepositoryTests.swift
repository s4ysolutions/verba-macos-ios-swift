import Foundation
import Testing
@testable import core // Adjust module name if different

// NOTE: This MockHttpClient must match the production `HttpClient` protocol used by TranslationRestRepository.
// If `HttpClient` is public and available to tests, this will compile. If not, make `HttpClient` public or move the mock accordingly.
struct MockHttpClient: HttpClient {
    var result: Result<(Data, URLResponse), Error>

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        switch result {
        case .success(let pair):
            return pair
        case .failure(let error):
            throw error
        }
    }
}

/// Stub token provider that returns a fixed dummy token so `executeRequest` tests are
/// isolated from real RSA operations.
struct StubTokenProvider: BearerTokenProvider {
    func makeToken(payload: String) async throws -> String {
        return "stub.aGFzaA==.2024-01-01T00:00:00Z.1.c2ln"
    }
}

private func httpResponse(url: URL = URL(string: "https://example.com")!, status: Int) -> HTTPURLResponse {
    return HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
}

@Suite("TranslationRestRepository.executeRequest")
struct TranslationRestRepositoryExecuteRequestTests {

    // Helper to build a repository with a given mock result
    func makeRepo(with result: Result<(Data, URLResponse), Error>) -> TranslationRestRepository {
        let mock = MockHttpClient(result: result)
        return TranslationRestRepository(tokenProvider: StubTokenProvider(), httpClient: mock)
    }

    @Test("200 OK -> parser success")
    func ok_parses_success() async throws {
        let data = Data("hello".utf8)
        let response = httpResponse(status: 200)
        let repo = makeRepo(with: .success((data, response)))

        let res: Result<String, ApiError> = await withUnsafeContinuation { continuation in
            Task {
                let r: Result<String, ApiError> = await repo.executeRequest(URLRequest(url: URL(string: "https://example.com")!)) { data in
                    let s = String(data: data, encoding: .utf8) ?? ""
                    return .success("parsed: \(s)")
                }
                continuation.resume(returning: r)
            }
        }

        switch res {
        case .success(let value):
            #expect(value == "parsed: hello")
        default:
            Issue.record("Expected success, got \(res)")
        }
    }

    @Test("401 -> invalidKey")
    func unauthorized_maps_to_invalidKey() async throws {
        let data = Data()
        let response = httpResponse(status: 401)
        let repo = makeRepo(with: .success((data, response)))

        let res: Result<String, ApiError> = await repo.executeRequest(URLRequest(url: URL(string: "https://example.com")!)) { _ in
            return .success("should not be called")
        }

        switch res {
        case .failure(.invalidKey): break
        default: Issue.record("Expected .invalidKey, got \(res)")
        }
    }

    @Test("403 -> invalidKey")
    func forbidden_maps_to_invalidKey() async throws {
        let data = Data()
        let response = httpResponse(status: 403)
        let repo = makeRepo(with: .success((data, response)))

        let res: Result<String, ApiError> = await repo.executeRequest(URLRequest(url: URL(string: "https://example.com")!)) { _ in
            return .success("should not be called")
        }

        switch res {
        case .failure(.invalidKey): break
        default: Issue.record("Expected .invalidKey, got \(res)")
        }
    }

    @Test("429 -> rateLimitExceeded")
    func tooManyRequests_maps_to_rateLimitExceeded() async throws {
        let data = Data()
        let response = httpResponse(status: 429)
        let repo = makeRepo(with: .success((data, response)))

        let res: Result<String, ApiError> = await repo.executeRequest(URLRequest(url: URL(string: "https://example.com")!)) { _ in
            return .success("should not be called")
        }

        switch res {
        case .failure(.rateLimitExceeded): break
        default: Issue.record("Expected .rateLimitExceeded, got \(res)")
        }
    }

    @Test("500 with plain text body -> http error with body")
    func serverError_with_plain_text_body() async throws {
        let data = Data("Internal error happened".utf8)
        let response = httpResponse(status: 500)
        let repo = makeRepo(with: .success((data, response)))

        let res: Result<String, ApiError> = await repo.executeRequest(URLRequest(url: URL(string: "https://example.com")!)) { _ in
            return .success("should not be called")
        }

        switch res {
        case .failure(let err):
            switch err {
            case .http(let code, let message):
                #expect(code == 500)
                let msg = message ?? ""
                #expect(msg == "Internal error happened" || msg == "500: Internal error happened")
            default:
                Issue.record("Expected .http, got \(err)")
            }
        default:
            Issue.record("Expected failure, got \(res)")
        }
    }

    @Test("500 with HTML body -> extracts <body> content")
    func serverError_with_html_body_extracts_body() async throws {
        let html = """
        <html>
          <head><title>Error</title></head>
          <body>Something bad happened</body>
        </html>
        """
        let data = Data(html.utf8)
        let response = httpResponse(status: 500)
        let repo = makeRepo(with: .success((data, response)))

        let res: Result<String, ApiError> = await repo.executeRequest(URLRequest(url: URL(string: "https://example.com")!)) { _ in
            return .success("should not be called")
        }

        switch res {
        case .failure(let err):
            switch err {
            case .http(let code, let message):
                #expect(code == 500)
                #expect((message ?? "").contains("Something bad happened"))
            default:
                Issue.record("Expected .http, got \(err)")
            }
        default:
            Issue.record("Expected failure, got \(res)")
        }
    }

    @Test("Non-HTTP response -> unexpected")
    func non_http_response_maps_to_unexpected() async throws {
        let data = Data()
        let url = URL(string: "https://example.com")!
        let response = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        let repo = makeRepo(with: .success((data, response)))

        let res: Result<String, ApiError> = await repo.executeRequest(URLRequest(url: url)) { _ in
            return .success("should not be called")
        }

        switch res {
        case .failure(.unexpected): break
        default: Issue.record("Expected .unexpected, got \(res)")
        }
    }

    @Test("Networking error -> networking")
    func networking_error_is_mapped() async throws {
        enum Dummy: Error { case boom }
        let repo = makeRepo(with: .failure(Dummy.boom))

        let res: Result<String, ApiError> = await repo.executeRequest(URLRequest(url: URL(string: "https://example.com")!)) { _ in
            return .success("should not be called")
        }

        switch res {
        case .failure(.networking): break
        default: Issue.record("Expected .networking, got \(res)")
        }
    }
}

