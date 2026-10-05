import Foundation
import LyricsCore

extension LyricsProviders {
    final class LRCLIB {
        let httpClient: HTTPClient
        private var performer: NetworkPerformer { NetworkPerformer(httpClient: httpClient) }

        init(httpClient: HTTPClient = .shared) {
            self.httpClient = httpClient
        }
    }
}

extension LyricsProviders.LRCLIB: _LyricsProvider {
    struct LyricsToken {
        let value: LRCLIBResponse
        /// True when this token came from the exact /api/get signature lookup
        /// (vs. the broad /api/search path). Used to resolve dedupe tie-breaks.
        let fromExactLookup: Bool

        init(value: LRCLIBResponse, fromExactLookup: Bool = false) {
            self.value = value
            self.fromExactLookup = fromExactLookup
        }
    }

    static let service: String = "LRCLIB"

    // MARK: – Token gathering with dual-path + dedupe

    /// Runs the broad /api/search path and, when title+artist+album+duration are
    /// all present, the exact /api/get signature lookup concurrently, deduplicating
    /// by LRCLIB id. One failing path does not suppress results from the other.
    func search(for request: LyricsSearchRequest) async throws -> [LyricsToken] {
        guard case .info(let title, let artist) = request.searchTerm,
              let albumName = request.albumName,
              !albumName.isEmpty,
              request.duration > 0
        else {
            // Keyword searches, or info searches missing album/duration:
            // fall through to the broad /api/search path only.
            return try await broadSearch(for: request)
        }

        // Both paths run concurrently; errors are captured independently so a failure
        // on one path (e.g. 404 from exact lookup) does not suppress the other's results.
        async let broadTask: [LyricsToken] = broadSearch(for: request)
        async let exactTask: LyricsToken? = exactSignatureLookup(
            title: title,
            artist: artist,
            albumName: albumName,
            duration: request.duration
        )

        var broadTokens: [LyricsToken]? = nil
        var exactToken: LyricsToken? = nil
        var broadError: Error? = nil

        do { broadTokens = try await broadTask } catch { broadError = error }
        do { exactToken = try await exactTask } catch {}

        let hasBroadResults = !(broadTokens?.isEmpty ?? true)
        let hasExactResult = exactToken != nil

        // Only propagate failure when ALL attempted paths fail before yielding anything.
        if !hasBroadResults && !hasExactResult {
            // Surface the broad search error (primary path) when both paths failed.
            if let error = broadError { throw error }
        }

        return deduplicate(broadTokens: broadTokens ?? [], exactToken: exactToken)
    }

    // MARK: – Search paths

    /// Broad /api/search — used for all request types (keyword + info).
    private func broadSearch(for request: LyricsSearchRequest) async throws -> [LyricsToken] {
        let queryItems: [URLQueryItem]
        switch request.searchTerm {
        case .keyword(let keyword):
            queryItems = [URLQueryItem(name: "q", value: keyword)]
        case .info(let title, let artist):
            queryItems = [
                URLQueryItem(name: "track_name", value: title),
                URLQueryItem(name: "artist_name", value: artist),
            ]
        }
        let endpoint = Endpoint(
            host: "lrclib.net",
            path: "/api/search",
            queryItems: queryItems
        )
        let results: [LRCLIBResponse] = try await performer.performJSON(endpoint)
        return results.map { LyricsToken(value: $0, fromExactLookup: false) }
    }

    /// Exact /api/get signature lookup — distinct from the per-id /api/get/{id} used
    /// in fetch(with:). This one takes structured query params and returns a single
    /// record (or 404). Only invoked for info+album+duration searches.
    private func exactSignatureLookup(
        title: String,
        artist: String,
        albumName: String,
        duration: TimeInterval
    ) async throws -> LyricsToken? {
        let endpoint = Endpoint(
            host: "lrclib.net",
            path: "/api/get",
            queryItems: [
                URLQueryItem(name: "track_name", value: title),
                URLQueryItem(name: "artist_name", value: artist),
                URLQueryItem(name: "album_name", value: albumName),
                URLQueryItem(name: "duration", value: String(format: "%.0f", duration)),
            ]
        )
        let response: LRCLIBResponse = try await performer.performJSON(endpoint)
        return LyricsToken(value: response, fromExactLookup: true)
    }

    // MARK: – Deduplication

    /// Merges exact and broad tokens, deduplicating by LRCLIB id.
    /// The exact /api/get result wins on collision (placed first, broad duplicate dropped),
    /// and the exact result is also prepended so it ranks before broad results.
    private func deduplicate(broadTokens: [LyricsToken], exactToken: LyricsToken?) -> [LyricsToken] {
        var seen = Set<Int>()
        var result: [LyricsToken] = []

        // Exact token goes first and wins any collision with broad results.
        if let exact = exactToken {
            seen.insert(exact.value.id)
            result.append(exact)
        }

        for token in broadTokens where seen.insert(token.value.id).inserted {
            result.append(token)
        }

        return result
    }

    // MARK: – Fetch (per-id /api/get/{id})

    /// Fetches full lyrics for a token. If the token already carries syncedLyrics
    /// (common for both exact and broad results) it parses inline without a network call.
    /// Otherwise, falls back to the per-id /api/get/{id} endpoint — this is the existing
    /// broad-path fetch, distinct from the exact-signature /api/get used in gatherTokens.
    func fetch(with token: LyricsToken) async throws -> Lyrics {
        if let lyrics = parseLyrics(for: token.value) {
            return lyrics
        }

        let endpoint = Endpoint(
            host: "lrclib.net",
            path: "/api/get/\(token.value.id)"
        )
        let fetchedToken: LRCLIBResponse = try await performer.performJSON(endpoint)

        guard let lyrics = parseLyrics(for: fetchedToken) else {
            throw LyricsProviderError.processingFailed(reason: "Synced lyrics not found in fetched LRCLIB response.")
        }
        return lyrics
    }

    private func parseLyrics(for token: LRCLIBResponse) -> Lyrics? {
        guard let syncedLyrics = token.syncedLyrics,
              let lyrics = Lyrics(syncedLyrics) else { return nil }
        lyrics.applyMetadata(
            title: token.trackName,
            artist: token.artistName,
            album: token.albumName,
            length: Double(token.duration),
            serviceToken: "\(token.id)"
        )
        return lyrics
    }
}
