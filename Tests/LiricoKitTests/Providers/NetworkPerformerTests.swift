import Testing
import Foundation
@testable import LyricsService

struct NetworkPerformerTests {
    private struct TrackNotFound: Decodable {
        let code: Int
        let name: String
    }

    private let endpoint = Endpoint(host: "lrclib.net", path: "/api/get")

    @Test func non2xxStatusThrowsHTTPErrorEvenWhenTheBodyDecodes() async throws {
        let mock = MockHTTPClient()
        let body = #"{"code":404,"name":"TrackNotFound","message":"Failed to find specified track"}"#
        mock.stubAny(.data(Data(body.utf8), statusCode: 404))
        let performer = NetworkPerformer(httpClient: mock)

        let error = await #expect(throws: LyricsProviderError.self) {
            _ = try await performer.performJSON(endpoint, as: TrackNotFound.self)
        }
        guard case .httpError(statusCode: 404) = error else {
            Issue.record("Expected httpError(404), got \(String(describing: error))")
            return
        }
    }

    @Test func serverErrorFailsTheProviderInsteadOfLookingEmpty() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/search", response: .data(Data("[]".utf8), statusCode: 503))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)
        let request = LyricsSearchRequest(searchTerm: .keyword("test query"), duration: 200)

        let error = await #expect(throws: LyricsProviderError.self) {
            _ = try await collect(provider.lyrics(for: request))
        }
        guard case .httpError(statusCode: 503) = error else {
            Issue.record("Expected httpError(503), got \(String(describing: error))")
            return
        }
    }

    @Test func successStatusesDecode() async throws {
        let mock = MockHTTPClient()
        mock.stubAny(.data(Data(#"{"code":0,"name":"ok"}"#.utf8), statusCode: 203))
        let performer = NetworkPerformer(httpClient: mock)

        let decoded = try await performer.performJSON(endpoint, as: TrackNotFound.self)
        #expect(decoded.name == "ok")
    }
}
