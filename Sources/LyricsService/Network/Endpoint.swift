import Foundation

struct Endpoint: Sendable {
    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
    }

    var scheme: String = "https"
    var host: String
    var path: String
    var queryItems: [URLQueryItem] = []
    var method: Method = .get
    var headers: [String: String] = [:]
    var body: Data?
    var cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    var timeoutInterval: TimeInterval = Endpoint.defaultTimeoutInterval

    /// URLSession's 60 s default outlives a caller's whole search (Lirico gives
    /// up after 15 s), so a stalled host would never be reported as failed.
    static let defaultTimeoutInterval: TimeInterval = 10

    func buildRequest() throws -> URLRequest {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw LyricsProviderError.invalidURL(urlString: "\(scheme)://\(host)\(path)")
        }
        var request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval)
        request.httpMethod = method.rawValue
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
}

extension Endpoint {
    /// Allowed schemes for `Endpoint.absolute`. Restricted to HTTP(S) so that
    /// caller-supplied URL strings cannot be coerced into `file://`,
    /// `data:`, `javascript:`, or other unintended transports (SSRF defense).
    static let allowedAbsoluteSchemes: Set<String> = ["http", "https"]

    static func absolute(
        _ urlString: String,
        method: Method = .get,
        headers: [String: String] = [:],
        body: Data? = nil
    ) throws -> URLRequest {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              allowedAbsoluteSchemes.contains(scheme),
              let host = url.host,
              !host.isEmpty
        else {
            throw LyricsProviderError.invalidURL(urlString: urlString)
        }
        var request = URLRequest(url: url, timeoutInterval: defaultTimeoutInterval)
        request.httpMethod = method.rawValue
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
}
