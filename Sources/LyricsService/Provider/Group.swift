import Foundation
import LyricsCore

extension LyricsProviders {
    public final class Group: Sendable {
        public let providers: [LyricsProvider]

        /// Plugins run upstream of `providers`: they widen a search by
        /// producing extra requests, they never produce lyrics themselves.
        public let plugins: [LyricsSearchRequestPlugin]

        /// Descriptors whose `source` strings are echoed verbatim in
        /// `ProviderEvent` payloads.  Populated only when `Group` is
        /// constructed via `init(descriptors:plugins:)`.
        private let descriptors: [ProviderDescriptor]

        public init(
            providers: [LyricsProvider] = [],
            plugins: [LyricsSearchRequestPlugin] = []
        ) {
            self.providers = providers
            self.plugins = plugins
            self.descriptors = []
        }

        /// Descriptor-based initialiser.  Use this path when you need
        /// `events(for:)` to echo canonical source names in its payloads.
        public init(
            descriptors: [ProviderDescriptor],
            plugins: [LyricsSearchRequestPlugin] = []
        ) {
            self.descriptors = descriptors
            self.providers = descriptors.map(\.provider)
            self.plugins = plugins
        }

        /// Ask every plugin for extra requests to search, discarding any
        /// whose term repeats the original request or an earlier plugin's.
        private func expand(_ request: LyricsSearchRequest) async -> [LyricsSearchRequest] {
            var collectedRequests: [LyricsSearchRequest] = []
            await withTaskGroup(of: [LyricsSearchRequest].self) { taskGroup in
                for plugin in plugins {
                    taskGroup.addTask {
                        await plugin.additionalRequests(for: request)
                    }
                }
                for await pluginRequests in taskGroup {
                    collectedRequests.append(contentsOf: pluginRequests)
                }
            }
            var scheduledTerms: [LyricsSearchRequest.SearchTerm] = [request.searchTerm]
            var uniqueRequests: [LyricsSearchRequest] = []
            for candidateRequest in collectedRequests
            where !scheduledTerms.contains(candidateRequest.searchTerm) {
                scheduledTerms.append(candidateRequest.searchTerm)
                uniqueRequests.append(candidateRequest)
            }
            return uniqueRequests
        }

        // MARK: - Event stream

        /// An `AsyncStream` that emits structured lifecycle events for every
        /// provider search, including those for plugin-derived requests.
        ///
        /// Provider failures surface as `.providerFailed` events rather than
        /// thrown errors, so one provider's failure can never cancel the others.
        /// The stream emits `.completed` exactly once when every provider has
        /// finished normally — both those serving the original request and those
        /// serving plugin-derived requests. If the consumer cancels the stream
        /// (task cancel or `break` inside a `for await`), `.completed` is
        /// suppressed — the absence of `.completed` is the canonical signal for
        /// cancel/timeout.
        ///
        /// Events for plugin-derived requests carry the derived request in their
        /// payload, making plugin-derived searches traceable by the caller.
        ///
        /// - Requires: The group was constructed via `init(descriptors:plugins:)`.
        ///   If it was constructed via the plain `init(providers:plugins:)` path,
        ///   the source name falls back to the provider's index in the array.
        public func events(for request: LyricsSearchRequest) -> AsyncStream<ProviderEvent> {
            // Build a (provider, source) pair for each entry.  When descriptors
            // are available they carry the canonical source name; otherwise fall
            // back to a stable ordinal label so the stream is still usable.
            let pairs: [(provider: LyricsProvider, source: String)]
            if descriptors.isEmpty {
                pairs = providers.enumerated().map { (idx, p) in (p, "Provider\(idx)") }
            } else {
                pairs = descriptors.map { ($0.provider, $0.source) }
            }

            return AsyncStream { continuation in
                let task = Task {
                    await withTaskGroup(of: Void.self) { taskGroup in
                        // Run providers for the original request immediately —
                        // plugin resolution must never delay the direct providers.
                        taskGroup.addTask {
                            await Self.runProviders(pairs, for: request, continuation: continuation)
                        }
                        // Plugins widen the search; each extra request they
                        // produce is also searched with all providers.  Events
                        // for derived requests carry the derived request so
                        // callers can trace which plugin influenced each result.
                        if !self.plugins.isEmpty {
                            taskGroup.addTask {
                                let extraRequests = await self.expand(request)
                                await withTaskGroup(of: Void.self) { extraTaskGroup in
                                    for extraRequest in extraRequests {
                                        extraTaskGroup.addTask {
                                            await Self.runProviders(
                                                pairs,
                                                for: extraRequest,
                                                continuation: continuation
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // Only yield `.completed` when the task was NOT cancelled.
                    // A cancelled task means the consumer broke out of the loop
                    // (timeout, early exit); suppressing `.completed` lets
                    // callers distinguish that from a normal finish.
                    if !Task.isCancelled {
                        continuation.yield(.completed)
                    }
                    continuation.finish()
                }
                // Cancel child work when the consumer stops iterating.
                continuation.onTermination = { _ in task.cancel() }
            }
        }

        /// Fan out to all providers for `request`, emitting lifecycle events
        /// for each one.  The same `pairs` array is reused for every request
        /// (original and plugin-derived) so the two code paths cannot drift.
        private static func runProviders(
            _ pairs: [(provider: LyricsProvider, source: String)],
            for request: LyricsSearchRequest,
            continuation: AsyncStream<ProviderEvent>.Continuation
        ) async {
            await withTaskGroup(of: Void.self) { taskGroup in
                for (provider, source) in pairs {
                    taskGroup.addTask {
                        await Self.runProvider(
                            provider,
                            source: source,
                            request: request,
                            continuation: continuation
                        )
                    }
                }
            }
        }

        private static func runProvider(
            _ provider: LyricsProvider,
            source: String,
            request: LyricsSearchRequest,
            continuation: AsyncStream<ProviderEvent>.Continuation
        ) async {
            continuation.yield(.providerStarted(source: source, request: request))
            var count = 0
            do {
                for try await lyric in provider.lyrics(for: request) {
                    continuation.yield(.candidate(source: source, lyrics: lyric))
                    count += 1
                }
                continuation.yield(.providerFinished(source: source, request: request, yieldedCount: count))
            } catch {
                continuation.yield(.providerFailed(
                    source: source,
                    request: request,
                    message: error.localizedDescription,
                    yieldedCount: count
                ))
            }
        }
    }
}
