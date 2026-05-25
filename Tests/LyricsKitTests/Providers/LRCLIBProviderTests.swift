import Testing
import Foundation
@testable import LyricsService

struct LRCLIBProviderTests {
    private let infoRequest = LyricsSearchRequest(
        searchTerm: .info(title: "Test Song", artist: "Test Artist"),
        duration: 200,
        limit: 5
    )
    private let keywordRequest = LyricsSearchRequest(
        searchTerm: .keyword("test query"),
        duration: 200,
        limit: 5
    )
    /// A complete request carrying album metadata; triggers the dual-path (search + exact).
    private let completeInfoRequest = LyricsSearchRequest(
        searchTerm: .info(title: "Test Song", artist: "Test Artist"),
        duration: 200,
        limit: 5,
        userInfo: [LyricsSearchRequest.UserInfoKey.albumName: "Test Album"]
    )

    // MARK: – Existing broad-path tests (must remain green)

    @Test func searchBuildsCorrectURLForInfo() async throws {
        let mock = MockHTTPClient()
        mock.stub(host: "lrclib.net", response: .data(try FixtureLoader.data(named: "LRCLIB/search.json")))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        _ = try await collect(provider.lyrics(for: infoRequest))

        let recorded = try #require(mock.recorded.first)
        #expect(recorded.url?.scheme == "https")
        #expect(recorded.url?.host == "lrclib.net")
        #expect(recorded.url?.path == "/api/search")
        let query = recorded.url?.query ?? ""
        #expect(query.contains("track_name=Test%20Song"))
        #expect(query.contains("artist_name=Test%20Artist"))
    }

    @Test func searchBuildsCorrectURLForKeyword() async throws {
        let mock = MockHTTPClient()
        mock.stub(host: "lrclib.net", response: .data(Data("[]".utf8)))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        _ = try await collect(provider.lyrics(for: keywordRequest))

        let query = mock.recorded.first?.url?.query ?? ""
        #expect(query.contains("q=test%20query"))
        #expect(!query.contains("track_name"))
    }

    @Test func successfullyYieldsLyricsFromSearchResults() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/search", response: .data(try FixtureLoader.data(named: "LRCLIB/search.json")))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        let lyrics = try await collect(provider.lyrics(for: infoRequest))
        // 1st token has syncedLyrics, 2nd does not -> 1st yields, 2nd path triggers fetch
        #expect(lyrics.count >= 1)
        let first = lyrics.first!
        #expect(first.idTags[.title] == "Test Song")
        #expect(first.idTags[.artist] == "Test Artist")
        #expect(first.idTags[.album] == "Test Album")
        #expect(first.metadata.serviceToken == "12345")
    }

    @Test func fallsBackToFetchForTokenWithoutSyncedLyrics() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/search", response: .data(try FixtureLoader.data(named: "LRCLIB/search.json")))
        mock.stub(matching: { $0.url?.path.hasPrefix("/api/get/") == true },
                  response: .data(try FixtureLoader.data(named: "LRCLIB/get.json")))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        _ = try await collect(provider.lyrics(for: infoRequest))

        let fetchRequest = mock.recorded.first(where: { $0.url?.path.hasPrefix("/api/get/") == true })
        let fetchPath = try #require(fetchRequest?.url?.path)
        #expect(fetchPath == "/api/get/67890")
    }

    @Test func networkErrorPropagatesAsNetworkError() async throws {
        let mock = MockHTTPClient()
        mock.stubAny(.error(URLError(.notConnectedToInternet)))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        await #expect(throws: LyricsProviderError.self) {
            _ = try await collect(provider.lyrics(for: infoRequest))
        }
    }

    @Test func decodingErrorPropagatesAsDecodingError() async throws {
        let mock = MockHTTPClient()
        mock.stub(host: "lrclib.net", response: .data(Data("not json".utf8)))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        await #expect(throws: LyricsProviderError.self) {
            _ = try await collect(provider.lyrics(for: infoRequest))
        }
    }

    // MARK: – SR-02: Dual-path + dedupe + partial-failure tests

    /// Keyword requests must only issue /api/search — the exact /api/get signature
    /// lookup requires structured title+artist+album+duration, not a keyword query.
    @Test func keywordRequestIssuesOnlyBroadSearch() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/search", response: .data(Data("[]".utf8)))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        _ = try await collect(provider.lyrics(for: keywordRequest))

        let searchRequests = mock.recorded.filter { $0.url?.path == "/api/search" }
        let exactRequests = mock.recorded.filter { $0.url?.path == "/api/get" }
        #expect(searchRequests.count == 1)
        #expect(exactRequests.isEmpty)
    }

    /// A complete title+artist+album+duration request must issue BOTH /api/search
    /// (broad) AND /api/get with query params (exact signature lookup).
    @Test func completeInfoRequestIssuesBothBroadAndExactPaths() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/search", response: .data(try FixtureLoader.data(named: "LRCLIB/search.json")))
        mock.stub(path: "/api/get", response: .data(try FixtureLoader.data(named: "LRCLIB/exact_get.json")))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        _ = try await collect(provider.lyrics(for: completeInfoRequest))

        let searchRequests = mock.recorded.filter { $0.url?.path == "/api/search" }
        let exactRequests = mock.recorded.filter { $0.url?.path == "/api/get" }
        #expect(searchRequests.count == 1)
        #expect(exactRequests.count == 1)

        // Verify exact lookup carries the required signature params.
        let exactURL = exactRequests.first?.url
        let query = exactURL?.query ?? ""
        #expect(query.contains("track_name=Test%20Song"))
        #expect(query.contains("artist_name=Test%20Artist"))
        #expect(query.contains("album_name=Test%20Album"))
        #expect(query.contains("duration=200"))
    }

    /// When /api/search and /api/get (exact) return the same LRCLIB id, exactly one
    /// candidate is yielded and the exact /api/get metadata wins (e.g. its syncedLyrics
    /// are used, not the broad search's copy).
    @Test func deduplicatesSameIdAcrossBothPaths() async throws {
        // exact_get.json id=12345 matches first entry in search.json id=12345.
        let mock = MockHTTPClient()
        mock.stub(path: "/api/search", response: .data(try FixtureLoader.data(named: "LRCLIB/search.json")))
        mock.stub(path: "/api/get", response: .data(try FixtureLoader.data(named: "LRCLIB/exact_get.json")))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        let lyrics = try await collect(provider.lyrics(for: completeInfoRequest))

        // Only one result for id=12345 (not two); plus possibly id=67890 from broad search.
        let byToken = Dictionary(grouping: lyrics, by: { $0.metadata.serviceToken })
        #expect(byToken["12345"]?.count == 1, "id 12345 must appear exactly once after dedupe")

        // The exact /api/get result must win: its syncedLyrics start with "exact first line".
        let deduped = try #require(byToken["12345"]?.first)
        let firstLine = deduped.lines.first?.content.description ?? ""
        #expect(firstLine.contains("exact first line"))
    }

    /// When the exact /api/get lookup fails (e.g. 404 / network error) but /api/search
    /// succeeds, the provider must still yield results from the broad path without throwing.
    @Test func partialFailureExactLookupFailsButBroadSucceeds() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/search", response: .data(try FixtureLoader.data(named: "LRCLIB/search.json")))
        // Exact /api/get returns a network error (simulates 404 or unreachable).
        mock.stub(path: "/api/get", response: .error(URLError(.resourceUnavailable)))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        // Must NOT throw; must yield at least the broad-path result.
        let lyrics = try await collect(provider.lyrics(for: completeInfoRequest))
        #expect(!lyrics.isEmpty)
        // The broad-path item (id=12345) must be present.
        let tokens = lyrics.compactMap { $0.metadata.serviceToken }
        #expect(tokens.contains("12345"))
    }

    /// When /api/search fails but the exact /api/get succeeds, the provider must
    /// yield the exact result without throwing.
    @Test func partialFailureBroadFailsButExactSucceeds() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/search", response: .error(URLError(.notConnectedToInternet)))
        mock.stub(path: "/api/get", response: .data(try FixtureLoader.data(named: "LRCLIB/exact_get.json")))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        let lyrics = try await collect(provider.lyrics(for: completeInfoRequest))
        #expect(!lyrics.isEmpty)
        let tokens = lyrics.compactMap { $0.metadata.serviceToken }
        #expect(tokens.contains("12345"))
    }

    /// When ALL paths fail (both /api/search and exact /api/get), the provider must throw.
    @Test func allPathsFailSurfacesError() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/search", response: .error(URLError(.notConnectedToInternet)))
        mock.stub(path: "/api/get", response: .error(URLError(.resourceUnavailable)))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        await #expect(throws: LyricsProviderError.self) {
            _ = try await collect(provider.lyrics(for: completeInfoRequest))
        }
    }

    // MARK: – Case 7 gap: non-colliding broad entries survive deduplication

    /// When the exact /api/get and /api/search return different ids, the broad-path
    /// entry with a different id must survive — deduplication must only drop the
    /// duplicate, not wipe all broad results.
    @Test func deduplicationPreservesNonCollidingBroadEntries() async throws {
        // search_two_synced.json has id=12345 and id=99999 (both with syncedLyrics,
        // so neither needs a per-id /api/get fetch).
        // exact_get.json has id=12345 — so 12345 deduplicates, but 99999 must survive.
        let mock = MockHTTPClient()
        mock.stub(path: "/api/search", response: .data(try FixtureLoader.data(named: "LRCLIB/search_two_synced.json")))
        mock.stub(path: "/api/get", response: .data(try FixtureLoader.data(named: "LRCLIB/exact_get.json")))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        let lyrics = try await collect(provider.lyrics(for: completeInfoRequest))
        let tokens = Set(lyrics.compactMap { $0.metadata.serviceToken })

        // The colliding entry must appear exactly once (exact wins).
        let byToken = Dictionary(grouping: lyrics, by: { $0.metadata.serviceToken })
        #expect(byToken["12345"]?.count == 1, "id 12345 must appear exactly once after dedupe")
        // The non-colliding broad entry must survive.
        #expect(tokens.contains("99999"), "non-colliding broad-path entry (id 99999) must be preserved")
    }

    /// The exact /api/get result that wins a dedup collision must carry the correct
    /// service token so downstream callers can trace it back to LRCLIB (source-trace tie).
    @Test func exactWinnerCarriesCorrectServiceToken() async throws {
        // exact_get.json id=12345 wins over the duplicate in search_two_synced.json.
        let mock = MockHTTPClient()
        mock.stub(path: "/api/search", response: .data(try FixtureLoader.data(named: "LRCLIB/search_two_synced.json")))
        mock.stub(path: "/api/get", response: .data(try FixtureLoader.data(named: "LRCLIB/exact_get.json")))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        let lyrics = try await collect(provider.lyrics(for: completeInfoRequest))
        let byToken = Dictionary(grouping: lyrics, by: { $0.metadata.serviceToken })
        let winner = try #require(byToken["12345"]?.first)

        // Service token must be the LRCLIB id as a string (source-trace requirement).
        #expect(winner.metadata.serviceToken == "12345")
        // Content must originate from the exact result, not the broad-path duplicate.
        let firstLine = winner.lines.first?.content.description ?? ""
        #expect(firstLine.contains("exact first line"))
    }
}

func collect<T>(_ stream: AsyncThrowingStream<T, Error>) async throws -> [T] {
    var items: [T] = []
    for try await item in stream {
        items.append(item)
    }
    return items
}
