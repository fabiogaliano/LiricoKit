import Testing
import Foundation
@testable import LyricsService

struct QQMusicProviderTests {
    private let infoRequest = LyricsSearchRequest(
        searchTerm: .info(title: "Test Song", artist: "Test Artist"),
        duration: 200,
        limit: 5
    )

    @Test func searchHitsBothApis() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/splcloud/fcgi-bin/smartbox_new.fcg",
                  response: .data(try FixtureLoader.data(named: "QQMusic/search1.json")))
        mock.stub(path: "/cgi-bin/musicu.fcg",
                  response: .data(try FixtureLoader.data(named: "QQMusic/search2.json")))
        mock.stub(path: "/qqmusic/fcgi-bin/lyric_download.fcg",
                  response: .data(try FixtureLoader.data(named: "QQMusic/lyrics.xml")))

        let provider = LyricsProviders.QQMusic(httpClient: mock)
        _ = try await collect(provider.lyrics(for: infoRequest))

        let api1 = mock.recorded.first(where: { $0.url?.path == "/splcloud/fcgi-bin/smartbox_new.fcg" })
        let api2 = mock.recorded.first(where: { $0.url?.path == "/cgi-bin/musicu.fcg" })
        #expect(api1 != nil)
        #expect(api2 != nil)
        let api1Query = api1?.url?.query ?? ""
        #expect(api1Query.contains("key=Test%20Song%20Test%20Artist"))
        #expect(api2?.httpMethod == "POST")
    }

    @Test func successfullyYieldsPlaintextLyrics() async throws {
        let mock = MockHTTPClient()
        let search1Data = try FixtureLoader.data(named: "QQMusic/search1.json")
        let search2Data = try FixtureLoader.data(named: "QQMusic/search2.json")
        let lyricsXMLData = try FixtureLoader.data(named: "QQMusic/lyrics.xml")
        let songDetailData = try FixtureLoader.data(named: "QQMusic/song_detail.json")

        mock.stub(path: "/splcloud/fcgi-bin/smartbox_new.fcg",
                  response: .data(search1Data))
        // First matching stub wins: route /cgi-bin/musicu.fcg POSTs by body content.
        mock.stub(matching: { request in
            guard request.url?.path == "/cgi-bin/musicu.fcg" else { return false }
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            return body.contains("get_song_detail_yqq")
        }, response: .data(songDetailData))
        mock.stub(path: "/cgi-bin/musicu.fcg", response: .data(search2Data))
        mock.stub(path: "/qqmusic/fcgi-bin/lyric_download.fcg", response: .data(lyricsXMLData))

        let provider = LyricsProviders.QQMusic(httpClient: mock)
        let lyrics = try await collect(provider.lyrics(for: infoRequest))
        #expect(!lyrics.isEmpty)
        let first = try #require(lyrics.first)
        #expect(first.idTags[.title] != nil)
        #expect(first.idTags[.artist] != nil)
        #expect(first.metadata.serviceToken != nil)
        #expect(first.metadata.artworkURL?.absoluteString.contains("albumMid123") == true)
    }

    @Test func networkErrorsOnBothApisThrowProcessingFailed() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/splcloud/fcgi-bin/smartbox_new.fcg",
                  response: .error(URLError(.notConnectedToInternet)))
        mock.stub(path: "/cgi-bin/musicu.fcg",
                  response: .error(URLError(.notConnectedToInternet)))

        let provider = LyricsProviders.QQMusic(httpClient: mock)
        // Both search APIs swallow their own errors and return []; the search wrapper
        // then raises processingFailed instead of returning a silently-empty result.
        await #expect(throws: LyricsProviderError.self) {
            _ = try await collect(provider.lyrics(for: infoRequest))
        }
    }

    @Test func processingFailsWhenLyricsXMLEmpty() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/splcloud/fcgi-bin/smartbox_new.fcg",
                  response: .data(try FixtureLoader.data(named: "QQMusic/search1.json")))
        mock.stub(path: "/cgi-bin/musicu.fcg",
                  response: .data(try FixtureLoader.data(named: "QQMusic/search2.json")))
        mock.stub(path: "/qqmusic/fcgi-bin/lyric_download.fcg",
                  response: .data(Data("<root></root>".utf8)))

        let provider = LyricsProviders.QQMusic(httpClient: mock)
        // fetch fails for every token, default stream finishes with zero yields.
        let lyrics = try await collect(provider.lyrics(for: infoRequest))
        #expect(lyrics.isEmpty)
    }

    @Test func desktopSearchLeadsAndDuplicatesAreFetchedOnce() async throws {
        let mock = MockHTTPClient()
        let api1 = #"{"code":0,"data":{"song":{"itemlist":[{"id":"111","mid":"mid111","name":"Test Song","singer":"Test Artist"},{"id":"222","mid":"mid222","name":"Test Song","singer":"Test Artist"}]}}}"#
        let api2 = #"{"req_1":{"code":0,"data":{"body":{"song":{"list":[{"mid":"mid222","name":"Test Song","id":222,"singer":[{"name":"Test Artist"}],"album":{"mid":"albumMid222"}}]}}}}}"#
        mock.stub(path: "/splcloud/fcgi-bin/smartbox_new.fcg", response: .data(Data(api1.utf8)))
        mock.stub(matching: { request in
            guard request.url?.path == "/cgi-bin/musicu.fcg" else { return false }
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            return body.contains("get_song_detail_yqq")
        }, response: .data(try FixtureLoader.data(named: "QQMusic/song_detail.json")))
        mock.stub(path: "/cgi-bin/musicu.fcg", response: .data(Data(api2.utf8)))
        mock.stub(path: "/qqmusic/fcgi-bin/lyric_download.fcg",
                  response: .data(try FixtureLoader.data(named: "QQMusic/lyrics.xml")))

        let provider = LyricsProviders.QQMusic(httpClient: mock)
        let lyrics = try await collect(provider.lyrics(for: infoRequest))

        #expect(lyrics.map(\.metadata.serviceToken) == ["mid222", "mid111"])
        let lyricRequests = mock.recorded.filter { $0.url?.path == "/qqmusic/fcgi-bin/lyric_download.fcg" }
        #expect(lyricRequests.count == 2)
    }

    @Test func desktopSearchAlbumSkipsCoverLookup() async throws {
        let mock = MockHTTPClient()
        let api2 = #"{"req_1":{"code":0,"data":{"body":{"song":{"list":[{"mid":"mid222","name":"Test Song","id":222,"singer":[{"name":"Test Artist"}],"album":{"mid":"albumMid222"}}]}}}}}"#
        mock.stub(path: "/splcloud/fcgi-bin/smartbox_new.fcg",
                  response: .data(Data(#"{"code":0,"data":{"song":{"itemlist":[]}}}"#.utf8)))
        mock.stub(path: "/cgi-bin/musicu.fcg", response: .data(Data(api2.utf8)))
        mock.stub(path: "/qqmusic/fcgi-bin/lyric_download.fcg",
                  response: .data(try FixtureLoader.data(named: "QQMusic/lyrics.xml")))

        let provider = LyricsProviders.QQMusic(httpClient: mock)
        let lyrics = try await collect(provider.lyrics(for: infoRequest))

        let first = try #require(lyrics.first)
        #expect(first.metadata.artworkURL?.absoluteString.contains("albumMid222") == true)
        let detailRequests = mock.recorded.filter {
            String(data: $0.httpBody ?? Data(), encoding: .utf8)?.contains("get_song_detail_yqq") == true
        }
        #expect(detailRequests.isEmpty)
    }
}
