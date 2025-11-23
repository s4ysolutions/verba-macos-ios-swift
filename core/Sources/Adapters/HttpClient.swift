import Foundation

public protocol HttpClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HttpClient {}
