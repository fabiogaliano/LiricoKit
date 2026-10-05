import Testing
import Foundation
@testable import LyricsService

/// End-to-end provider checks that hit real network endpoints.
///
/// Disabled by default. Opt in by setting the `INTEGRATION_TESTS=1` environment variable
/// (e.g. via the Xcode scheme or `INTEGRATION_TESTS=1 swift test`).
private let integrationEnabled: Bool =
    ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] == "1"

private let musixmatchToken: String? =
    ProcessInfo.processInfo.environment["MUSIXMATCH_TOKEN"].flatMap { $0.isEmpty ? nil : $0 }

private let testSong = "Over"
private let testArtist = "yihuik苡慧/白静晨"
private let duration = 155.0
private let searchReq = LyricsSearchRequest(
    searchTerm: .info(title: testSong, artist: testArtist),
    duration: duration
)

@Suite(.enabled(if: integrationEnabled, "Set INTEGRATION_TESTS=1 to run against the real providers"))
struct LiricoKitIntegrationTests {
    private func run(provider: LyricsProvider) async throws {
        for try await lyrics in provider.lyrics(for: searchReq) {
            print(lyrics)
        }
    }

    @Test func qqMusicProvider() async throws {
        try await run(provider: LyricsProviders.Service.qq.create())
    }

    @Test func LRCLIBProvider() async throws {
        try await run(provider: LyricsProviders.Service.lrclib.create())
    }

    @Test func kugouProvider() async throws {
        try await run(provider: LyricsProviders.Service.kugou.create())
    }

    @Test func netEaseProvider() async throws {
        try await run(provider: LyricsProviders.Service.netease.create())
    }

    @Test(.enabled(if: musixmatchToken != nil, "Set MUSIXMATCH_TOKEN to run against Musixmatch"))
    func musixmatchProvider() async throws {
        let token = try #require(musixmatchToken)
        let provider = LyricsProviders.Service.musixmatch.create(.init(usertoken: token))
        try await run(provider: provider)
    }
}
