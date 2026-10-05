import Foundation
import Synchronization
@testable import LyricsService

final class MockHTTPClient: HTTPClient {
    enum StubResponse {
        case data(Data, statusCode: Int = 200, headers: [String: String] = [:])
        case error(Error)
    }

    struct Stub {
        let matches: @Sendable (URLRequest) -> Bool
        let response: StubResponse
    }

    private struct State {
        var stubs: [Stub] = []
        var recorded: [URLRequest] = []
    }

    private let state = Mutex(State())

    var recorded: [URLRequest] {
        state.withLock { $0.recorded }
    }

    func reset() {
        state.withLock { $0 = State() }
    }

    func stub(matching: @escaping @Sendable (URLRequest) -> Bool, response: StubResponse) {
        state.withLock { $0.stubs.append(Stub(matches: matching, response: response)) }
    }

    func stub(path: String, response: StubResponse) {
        stub(matching: { $0.url?.path == path }, response: response)
    }

    func stub(host: String, response: StubResponse) {
        stub(matching: { $0.url?.host == host }, response: response)
    }

    func stub(hostContains substring: String, response: StubResponse) {
        stub(matching: { $0.url?.host?.contains(substring) == true }, response: response)
    }

    func stubAny(_ response: StubResponse) {
        stub(matching: { _ in true }, response: response)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let stub = state.withLock { state in
            state.recorded.append(request)
            return state.stubs.first { $0.matches(request) }
        }
        guard let stub else {
            let path = request.url?.path ?? "<no url>"
            throw URLError(.unsupportedURL, userInfo: [
                NSLocalizedDescriptionKey: "MockHTTPClient: no stub matched \(path)",
            ])
        }
        switch stub.response {
        case .error(let error):
            throw error
        case .data(let data, let statusCode, let headers):
            let url = request.url ?? URL(string: "http://localhost/")!
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            return (data, response)
        }
    }
}
