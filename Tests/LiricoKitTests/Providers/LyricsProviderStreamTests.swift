import Testing
import Foundation
@preconcurrency import LyricsCore
@testable import LyricsService

/// A provider whose fetches take a set time and report how they ended.
private struct DelayedFetchProvider: _LyricsProvider {
    struct LyricsToken: Sendable {
        let title: String
        let delayNanoseconds: UInt64
    }

    struct FetchEnd: Sendable {
        let title: String
        let wasCancelled: Bool
    }

    static let service = "Delayed"

    let tokens: [LyricsToken]
    let fetchEnded: AsyncStream<FetchEnd>.Continuation

    func search(for request: LyricsSearchRequest) async throws -> [LyricsToken] {
        tokens
    }

    func fetch(with token: LyricsToken) async throws -> Lyrics {
        do {
            try await Task.sleep(nanoseconds: token.delayNanoseconds)
        } catch {
            fetchEnded.yield(FetchEnd(title: token.title, wasCancelled: true))
            throw error
        }
        fetchEnded.yield(FetchEnd(title: token.title, wasCancelled: false))
        let lyrics = Lyrics(lines: [LyricsLine(content: token.title, position: 0)], idTags: [:])
        lyrics.idTags[.title] = token.title
        return lyrics
    }
}

private let slowFetchNanoseconds: UInt64 = 3_000_000_000

private func waitForEnd(of title: String, in ends: AsyncStream<DelayedFetchProvider.FetchEnd>) async -> DelayedFetchProvider.FetchEnd? {
    for await end in ends where end.title == title {
        return end
    }
    return nil
}

struct LyricsProviderStreamTests {
    private let request = LyricsSearchRequest(searchTerm: .info(title: "T", artist: "A"), duration: 200)

    @Test func yieldsEachFetchAsItCompletes() async throws {
        let (_, endsContinuation) = AsyncStream.makeStream(of: DelayedFetchProvider.FetchEnd.self)
        let provider = DelayedFetchProvider(
            tokens: [.init(title: "slow", delayNanoseconds: slowFetchNanoseconds), .init(title: "fast", delayNanoseconds: 0)],
            fetchEnded: endsContinuation
        )

        var first: Lyrics?
        for try await lyrics in provider.lyrics(for: request) {
            first = lyrics
            break
        }

        #expect(first?.idTags[.title] == "fast")
    }

    @Test func stoppingIterationCancelsPendingFetches() async throws {
        let (ends, endsContinuation) = AsyncStream.makeStream(of: DelayedFetchProvider.FetchEnd.self)
        let provider = DelayedFetchProvider(
            tokens: [.init(title: "fast", delayNanoseconds: 0), .init(title: "slow", delayNanoseconds: slowFetchNanoseconds)],
            fetchEnded: endsContinuation
        )

        for try await _ in provider.lyrics(for: request) {
            break
        }

        let slowEnd = await waitForEnd(of: "slow", in: ends)
        #expect(slowEnd?.wasCancelled == true)
    }

    @Test func cancellingAGroupEventsConsumerCancelsProviderFetches() async throws {
        let (ends, endsContinuation) = AsyncStream.makeStream(of: DelayedFetchProvider.FetchEnd.self)
        let provider = DelayedFetchProvider(
            tokens: [.init(title: "fast", delayNanoseconds: 0), .init(title: "slow", delayNanoseconds: slowFetchNanoseconds)],
            fetchEnded: endsContinuation
        )
        let group = LyricsProviders.Group(descriptors: [.init(source: "Delayed", provider: provider)])
        let (firstCandidate, firstCandidateContinuation) = AsyncStream.makeStream(of: Void.self)
        let request = self.request

        let consumer = Task {
            for await event in group.events(for: request) {
                if case .candidate = event {
                    firstCandidateContinuation.yield()
                }
            }
        }
        for await _ in firstCandidate { break }
        consumer.cancel()

        let slowEnd = await waitForEnd(of: "slow", in: ends)
        #expect(slowEnd?.wasCancelled == true)
    }
}

/// A provider whose fetches fail the way real ones do.
private struct FailingFetchProvider: _LyricsProvider {
    enum LyricsToken: Sendable {
        case unreachable
        case noLyrics
    }

    static let service = "Failing"

    let tokens: [LyricsToken]

    func search(for request: LyricsSearchRequest) async throws -> [LyricsToken] {
        tokens
    }

    func fetch(with token: LyricsToken) async throws -> Lyrics {
        switch token {
        case .unreachable:
            throw LyricsProviderError.networkError(underlyingError: URLError(.timedOut))
        case .noLyrics:
            throw LyricsProviderError.processingFailed(reason: "No valid lyric content found.")
        }
    }
}

struct LyricsProviderFailureTests {
    private let request = LyricsSearchRequest(searchTerm: .info(title: "T", artist: "A"), duration: 200)

    @Test func everyFetchUnreachableFailsTheStream() async throws {
        let provider = FailingFetchProvider(tokens: [.unreachable, .unreachable])

        await #expect(throws: LyricsProviderError.self) {
            _ = try await collect(provider.lyrics(for: self.request))
        }
    }

    @Test func fetchesThatFindNoLyricsFinishEmpty() async throws {
        let provider = FailingFetchProvider(tokens: [.noLyrics, .unreachable])

        let lyrics = try await collect(provider.lyrics(for: request))
        #expect(lyrics.isEmpty)
    }

    @Test func groupReportsAnUnreachableLyricsHostAsProviderFailed() async throws {
        let mock = MockHTTPClient()
        mock.stub(host: "mobilecdn.kugou.com", response: .data(try FixtureLoader.data(named: "Kugou/search.json")))
        mock.stub(host: "krcs.kugou.com", response: .error(URLError(.timedOut)))
        let group = LyricsProviders.Group(descriptors: [
            .init(source: "Kugou", provider: LyricsProviders.Kugou(httpClient: mock)),
        ])

        var outcomes: [String] = []
        for await event in group.events(for: request) {
            switch event {
            case .providerFinished(_, _, let count): outcomes.append("finished(\(count))")
            case .providerFailed(_, _, _, let count): outcomes.append("failed(\(count))")
            default: break
            }
        }

        #expect(outcomes == ["failed(0)"])
    }
}
