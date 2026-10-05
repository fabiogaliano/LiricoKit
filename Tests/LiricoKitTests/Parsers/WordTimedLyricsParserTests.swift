import Testing
import Foundation
@testable import LyricsService

/// Word-timed formats wrap their timing in `(…)` or `<…>`, and lyric text can
/// contain those same characters.
struct WordTimedLyricsParserTests {
    @Test func qqMusicQrcKeepsTextContainingParentheses() throws {
        let content = """
        [ti:Test Song]
        [ar:Test Artist]
        [al:Test Album]
        [by:]
        [offset:0]
        [1200,600]said(1200,200) (oh(1400,200) yeah)(1600,200)
        [1800,400]Hello(1800,200) world(2000,200)
        """
        let lyrics = try #require(Lyrics(qqmusicQrcContent: content))

        #expect(lyrics.lines.map(\.content) == ["said (oh yeah)", "Hello world"])
        #expect(lyrics.lines.map(\.position) == [1.2, 1.8])
        #expect(lyrics.lines[0].attachments.timetag?.description == "<0,0><200,4><400,8><600,14><600>")
        #expect(lyrics.lines[1].attachments.timetag?.description == "<0,0><200,5><400,11><400>")
    }

    @Test func netEaseYrcKeepsTextContainingParentheses() throws {
        let content = """
        {"t":0,"c":[{"tx":"作词: "},{"tx":"Test Writer"}]}
        [1200,600](1200,200,0)said (1400,200,0)(oh (1600,200,0)yeah)
        [1800,400](1800,200,0)Hello (2000,200,0)world
        """
        let lyrics = try #require(Lyrics(netEaseYrcContent: content))

        #expect(lyrics.lines.map(\.content) == ["said (oh yeah)", "Hello world"])
        #expect(lyrics.lines[0].attachments.timetag?.description == "<0,0><200,5><400,9><600,14><600>")
        #expect(lyrics.lines[1].attachments.timetag?.description == "<0,0><200,6><400,11><400>")
    }

    @Test func netEaseKLyricKeepsTextContainingParentheses() throws {
        let content = """
        [ti:Test Song]
        [1200,600](0,200)said(0,1) (0,200)(oh(0,1) (0,200)yeah)
        """
        let lyrics = try #require(Lyrics(netEaseKLyricContent: content))

        #expect(lyrics.lines.map(\.content) == ["said (oh yeah)"])
        #expect(lyrics.lines[0].attachments.timetag?.description == "<0,0><201,5><402,9><602,14><600>")
    }

    @Test func kugouKrcKeepsTextContainingAngleBrackets() throws {
        let content = """
        [id:$00000000]
        [ar:Test Artist]
        [ti:Test Song]
        [offset:0]
        [1200,600]<0,200,0>said <200,200,0><3 <400,200,0>you
        """
        let lyrics = try #require(Lyrics(kugouKrcContent: content))

        #expect(lyrics.lines.map(\.content) == ["said <3 you"])
        #expect(lyrics.lines[0].attachments.timetag?.description == "<0,0><200,5><400,8><600,11><600>")
    }
}
