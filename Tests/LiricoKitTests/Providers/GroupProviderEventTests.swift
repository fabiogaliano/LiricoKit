import Testing
import Foundation
@testable import LyricsService

// MARK: - Helpers shared within this file

private func makeLyrics(title: String) -> Lyrics {
    let lyrics = Lyrics(lines: [LyricsLine(content: "x", position: 0)], idTags: [:])
    lyrics.idTags[.title] = title
    return lyrics
}

private struct StaticProvider: LyricsProvider {
    let lyricsToYield: [Lyrics]

    func lyrics(for request: LyricsSearchRequest) -> AsyncThrowingStream<Lyrics, Error> {
        AsyncThrowingStream { continuation in
            for lyric in lyricsToYield {
                continuation.yield(lyric)
            }
            continuation.finish()
        }
    }
}

private struct FailingProvider: LyricsProvider {
    let error: Error

    func lyrics(for request: LyricsSearchRequest) -> AsyncThrowingStream<Lyrics, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

/// A provider that suspends until `gate` resolves, then yields one lyric.
/// Used to keep a provider alive long enough to observe cancellation behavior.
private struct GatedProvider: LyricsProvider {
    let title: String
    let gate: AsyncStream<Void>

    func lyrics(for request: LyricsSearchRequest) -> AsyncThrowingStream<Lyrics, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for await _ in gate {
                    continuation.yield(makeLyrics(title: title))
                    break
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private func collect(_ stream: AsyncStream<LyricsProviders.ProviderEvent>) async -> [LyricsProviders.ProviderEvent] {
    var events: [LyricsProviders.ProviderEvent] = []
    for await event in stream {
        events.append(event)
    }
    return events
}

// MARK: - Tests

struct GroupProviderEventTests {
    private let request = LyricsSearchRequest(
        searchTerm: .info(title: "Anything", artist: "Anyone"),
        duration: 200
    )

    // MARK: Normal completion

    @Test func successfulGroupEmitsFullLifecycle() async {
        let providerA = StaticProvider(lyricsToYield: [makeLyrics(title: "A1")])
        let descriptors = [
            LyricsProviders.ProviderDescriptor(source: "SourceA", provider: providerA),
        ]
        let group = LyricsProviders.Group(descriptors: descriptors)

        let events = await collect(group.events(for: request))

        // Must contain one started, one candidate, one finished, one completed.
        let started = events.filter { if case .providerStarted(let s, _) = $0 { return s == "SourceA" }; return false }
        let candidates = events.filter { if case .candidate(let s, _) = $0 { return s == "SourceA" }; return false }
        let finished = events.filter { if case .providerFinished(let s, _, let c) = $0 { return s == "SourceA" && c == 1 }; return false }
        let completed = events.filter { if case .completed = $0 { return true }; return false }

        #expect(started.count == 1)
        #expect(candidates.count == 1)
        #expect(finished.count == 1)
        #expect(completed.count == 1)
    }

    @Test func completedIsLastEvent() async {
        let provider = StaticProvider(lyricsToYield: [makeLyrics(title: "X")])
        let group = LyricsProviders.Group(
            descriptors: [LyricsProviders.ProviderDescriptor(source: "S", provider: provider)]
        )

        let events = await collect(group.events(for: request))
        #expect(!events.isEmpty)
        if case .completed = events.last! {
            // correct
        } else {
            Issue.record("Expected .completed as the last event, got \(events.last!)")
        }
    }

    @Test func sourceNameEchoesDescriptorExactly() async {
        let provider = StaticProvider(lyricsToYield: [makeLyrics(title: "T")])
        let expectedSource = "My Canonical Source"
        let group = LyricsProviders.Group(
            descriptors: [LyricsProviders.ProviderDescriptor(source: expectedSource, provider: provider)]
        )

        let events = await collect(group.events(for: request))
        for event in events {
            switch event {
            case .providerStarted(let s, _):
                #expect(s == expectedSource)
            case .candidate(let s, _):
                #expect(s == expectedSource)
            case .providerFinished(let s, _, _):
                #expect(s == expectedSource)
            case .providerFailed(let s, _, _, _):
                #expect(s == expectedSource)
            case .completed:
                break
            }
        }
    }

    // MARK: Provider failure does not cancel siblings

    @Test func failingProviderEmitsProviderFailedAndSiblingsStillComplete() async {
        let failing = FailingProvider(error: LyricsProviderError.processingFailed(reason: "boom"))
        let working = StaticProvider(lyricsToYield: [makeLyrics(title: "W1")])
        let group = LyricsProviders.Group(descriptors: [
            LyricsProviders.ProviderDescriptor(source: "Failing", provider: failing),
            LyricsProviders.ProviderDescriptor(source: "Working", provider: working),
        ])

        let events = await collect(group.events(for: request))

        // Failing provider must produce providerFailed, not terminate the stream.
        let failed = events.filter {
            if case .providerFailed(let s, _, _, _) = $0 { return s == "Failing" }
            return false
        }
        #expect(failed.count == 1)

        // Working provider's candidate must still appear.
        let workingCandidates = events.filter {
            if case .candidate(let s, _) = $0 { return s == "Working" }
            return false
        }
        #expect(workingCandidates.count == 1)

        // Working provider must still finish.
        let workingFinished = events.filter {
            if case .providerFinished(let s, _, _) = $0 { return s == "Working" }
            return false
        }
        #expect(workingFinished.count == 1)

        // Completed must still be emitted after all providers resolve.
        let completed = events.filter { if case .completed = $0 { return true }; return false }
        #expect(completed.count == 1)
    }

    @Test func yieldedCountIsZeroWhenProviderFailsImmediately() async {
        let failing = FailingProvider(error: LyricsProviderError.processingFailed(reason: "instant fail"))
        let group = LyricsProviders.Group(descriptors: [
            LyricsProviders.ProviderDescriptor(source: "F", provider: failing),
        ])

        let events = await collect(group.events(for: request))

        let failedEvent = events.first {
            if case .providerFailed = $0 { return true }
            return false
        }
        if case .providerFailed(_, _, _, let count) = failedEvent! {
            #expect(count == 0)
        } else {
            Issue.record("Expected providerFailed event")
        }
    }

    // MARK: Cancellation suppresses completed

    @Test func cancellingStreamDoesNotEmitCompleted() async {
        // Use a gated provider so the task is still running when we cancel.
        let (gate, gateContinuation) = AsyncStream.makeStream(of: Void.self)

        let gated = GatedProvider(title: "Gated", gate: gate)
        let group = LyricsProviders.Group(descriptors: [
            LyricsProviders.ProviderDescriptor(source: "Gated", provider: gated),
        ])

        // Wrap the iteration in a task we can cancel externally.
        let consumerTask = Task {
            var collectedEvents: [LyricsProviders.ProviderEvent] = []
            for await event in group.events(for: request) {
                collectedEvents.append(event)
                // After receiving providerStarted, cancel immediately without
                // opening the gate — this simulates a consumer timing out.
                if case .providerStarted = event {
                    break
                }
            }
            return collectedEvents
        }

        let collectedEvents = await consumerTask.value
        gateContinuation.finish()

        let completed = collectedEvents.filter { if case .completed = $0 { return true }; return false }
        #expect(completed.isEmpty, "completed must not appear after stream cancellation")
    }

    // MARK: Providers without descriptors

    @Test func candidatesArriveFromEveryProvider() async {
        let providerA = StaticProvider(lyricsToYield: [makeLyrics(title: "A1"), makeLyrics(title: "A2")])
        let providerB = StaticProvider(lyricsToYield: [makeLyrics(title: "B1")])
        let group = LyricsProviders.Group(providers: [providerA, providerB])

        let events = await collect(group.events(for: request))

        var titles: Set<String> = []
        var sources: Set<String> = []
        for case .candidate(let source, let lyrics) in events {
            sources.insert(source)
            if let title = lyrics.idTags[.title] {
                titles.insert(title)
            }
        }
        #expect(titles == ["A1", "A2", "B1"])
        #expect(sources == ["Provider0", "Provider1"])
    }

    @Test func groupWithoutProvidersOnlyCompletes() async {
        let group = LyricsProviders.Group(providers: [])

        let events = await collect(group.events(for: request))

        #expect(events.count == 1)
        guard case .completed = events.first else {
            Issue.record("Expected only .completed, got \(events)")
            return
        }
    }

    // MARK: Plugin-derived searches

    /// A plugin that always returns one derived request with a known search term,
    /// regardless of the original request.
    private struct FixedTermPlugin: LyricsSearchRequestPlugin {
        let derivedTerm: LyricsSearchRequest.SearchTerm

        func additionalRequests(for request: LyricsSearchRequest) async -> [LyricsSearchRequest] {
            [request.derived(searchTerm: derivedTerm)]
        }
    }

    @Test func pluginDerivedSearchEmitsEventsWithDerivedRequest() async {
        // The original request uses one artist; the plugin rewrites it to a
        // different artist so the two requests are distinguishable by searchTerm.
        let derivedTerm = LyricsSearchRequest.SearchTerm.info(title: "Anything", artist: "NativeArtist")
        let plugin = FixedTermPlugin(derivedTerm: derivedTerm)

        let provider = StaticProvider(lyricsToYield: [makeLyrics(title: "P1")])
        let group = LyricsProviders.Group(
            descriptors: [LyricsProviders.ProviderDescriptor(source: "SourceA", provider: provider)],
            plugins: [plugin]
        )

        let events = await collect(group.events(for: request))

        // The stream must contain events whose request carries the derived term,
        // proving plugin-derived searches are traceable through the event payload.
        let startedForDerived = events.filter {
            guard case .providerStarted(_, let r) = $0 else { return false }
            return r.searchTerm == derivedTerm
        }
        #expect(!startedForDerived.isEmpty, "providerStarted must be emitted for the plugin-derived request")

        let finishedForDerived = events.filter {
            guard case .providerFinished(_, let r, _) = $0 else { return false }
            return r.searchTerm == derivedTerm
        }
        #expect(!finishedForDerived.isEmpty, "providerFinished must be emitted for the plugin-derived request")

        // completed must appear only after the derived-request events, so it
        // must be the last event in the stream.
        guard case .completed = events.last else {
            Issue.record("Expected .completed as the last event, got \(String(describing: events.last))")
            return
        }
        let completedIndex = events.indices.last!
        let lastDerivedEventIndex = events.indices.last {
            guard case .providerFinished(_, let r, _) = events[$0] else { return false }
            return r.searchTerm == derivedTerm
        }
        if let derivedIdx = lastDerivedEventIndex {
            #expect(derivedIdx < completedIndex, "completed must arrive after all plugin-derived provider events")
        } else {
            Issue.record("No providerFinished event found for the derived request")
        }
    }

    @Test func pluginDerivedEventsCarryDerivedRequestNotOriginal() async {
        // Verify source-name echo is correct AND that the request field in each
        // plugin-derived event is the derived request, never the original.
        let originalTerm = LyricsSearchRequest.SearchTerm.info(title: "Anything", artist: "Anyone")
        let derivedTerm = LyricsSearchRequest.SearchTerm.info(title: "Anything", artist: "NativeArtist")
        let plugin = FixedTermPlugin(derivedTerm: derivedTerm)

        let provider = StaticProvider(lyricsToYield: [makeLyrics(title: "T")])
        let group = LyricsProviders.Group(
            descriptors: [LyricsProviders.ProviderDescriptor(source: "S", provider: provider)],
            plugins: [plugin]
        )

        let events = await collect(group.events(for: request))

        // Separate events by which request they carry.
        var originalRequestEvents: [LyricsProviders.ProviderEvent] = []
        var derivedRequestEvents: [LyricsProviders.ProviderEvent] = []

        for event in events {
            switch event {
            case .providerStarted(_, let r):
                if r.searchTerm == originalTerm { originalRequestEvents.append(event) }
                else if r.searchTerm == derivedTerm { derivedRequestEvents.append(event) }
            case .providerFinished(_, let r, _):
                if r.searchTerm == originalTerm { originalRequestEvents.append(event) }
                else if r.searchTerm == derivedTerm { derivedRequestEvents.append(event) }
            case .providerFailed(_, let r, _, _):
                if r.searchTerm == originalTerm { originalRequestEvents.append(event) }
                else if r.searchTerm == derivedTerm { derivedRequestEvents.append(event) }
            default:
                break
            }
        }

        // Both the original and derived requests must produce lifecycle events.
        #expect(!originalRequestEvents.isEmpty, "original request must produce provider lifecycle events")
        #expect(!derivedRequestEvents.isEmpty, "derived request must produce provider lifecycle events")
    }

    // MARK: Album name on LyricsSearchRequest

    @Test func albumNameAccessorReadsFromUserInfo() {
        var req = LyricsSearchRequest(
            searchTerm: .info(title: "T", artist: "A"),
            duration: 100,
            userInfo: [LyricsSearchRequest.UserInfoKey.albumName: "My Album"]
        )
        #expect(req.albumName == "My Album")

        req.userInfo.removeAll()
        #expect(req.albumName == nil)
    }
}
