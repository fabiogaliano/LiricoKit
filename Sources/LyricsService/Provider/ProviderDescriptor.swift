import Foundation
import LyricsCore

extension LyricsProviders {

    /// A value that pairs a `LyricsProvider` implementation with the canonical
    /// source name used in ranking and event attribution.
    ///
    /// The `source` string is the single source-of-truth for how a provider
    /// identifies itself in `ProviderEvent` payloads and downstream ranking
    /// keys.  Keeping both together ensures that whoever constructs a descriptor
    /// controls the identity — individual provider implementations never pick
    /// their own event labels at call-time.
    public struct ProviderDescriptor: Sendable {
        /// Canonical source display name and source-priority ranking key.
        public let source: String
        public let provider: LyricsProvider

        public init(source: String, provider: LyricsProvider) {
            self.source = source
            self.provider = provider
        }
    }

    /// Lifecycle events produced by `Group.events(for:)`.
    ///
    /// Each provider in the group emits the sequence:
    ///   `providerStarted` → zero or more `candidate` → `providerFinished` | `providerFailed`
    ///
    /// After every provider has finished (in any order) the group emits a
    /// single `completed`.  If the consumer cancels the stream, `completed` is
    /// suppressed — its absence is the signal for cancel/timeout vs. normal
    /// completion.
    public enum ProviderEvent {
        case providerStarted(source: String, request: LyricsSearchRequest)
        case candidate(source: String, lyrics: Lyrics)
        case providerFinished(source: String, request: LyricsSearchRequest, yieldedCount: Int)
        case providerFailed(source: String, request: LyricsSearchRequest, message: String, yieldedCount: Int)
        case completed
    }
}
