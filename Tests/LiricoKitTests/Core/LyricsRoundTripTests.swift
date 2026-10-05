import Testing
import Foundation
import LyricsCore

/// Lirico saves lyrics as `description` and loads them back with `Lyrics(_:)`.
struct LyricsRoundTripTests {
    private func reloaded(_ lyrics: Lyrics) throws -> Lyrics {
        try #require(Lyrics(lyrics.description))
    }

    private func line(_ content: String, at position: TimeInterval, translation: String? = nil) -> LyricsLine {
        var line = LyricsLine(content: content, position: position)
        line.attachments[.translation()] = translation
        return line
    }

    // MARK: Content that looks like markup

    @Test func lineWithBracketedSectionLabelKeepsItsText() throws {
        let lyrics = try #require(Lyrics("[00:10.000]【副歌】我爱你"))
        #expect(lyrics.lines.map(\.content) == ["【副歌】我爱你"])
        #expect(lyrics.lines[0].attachments.translation() == nil)
    }

    @Test func labelOnlyLineIsTextNotATranslation() throws {
        let lyrics = try #require(Lyrics("[00:10.000]【間奏】\n[00:12.000]la"))
        #expect(lyrics.lines.map(\.content) == ["【間奏】", "la"])
        #expect(lyrics.lines[0].attachments.translation() == nil)
    }

    @Test func sectionLabelSurvivesSaveAndReload() throws {
        let lyrics = Lyrics(lines: [
            line("【副歌】我爱你", at: 10, translation: "I love you"),
            line("你爱我", at: 12.5),
            line("【間奏】", at: 15),
        ], idTags: [.title: "Test Song"])

        let reloaded = try reloaded(lyrics)
        #expect(reloaded.lines == lyrics.lines)
    }

    @Test func lineStartingWithASquareBracketSurvivesSaveAndReload() throws {
        let lyrics = Lyrics(lines: [
            line("[Chorus] la la", at: 10, translation: "啦啦"),
            line("[Verse 2: Guest] yeah", at: 12.5),
            line("la la la", at: 15),
        ], idTags: [.title: "Test Song"])

        let reloaded = try reloaded(lyrics)
        #expect(reloaded.lines == lyrics.lines)
        #expect(reloaded.metadata.attachmentTags == [.translation()])
    }

    // MARK: Existing formats

    @Test func lrcxTranslationAttachmentsLoad() throws {
        let lyrics = try #require(Lyrics("""
        [ti:Test Song]
        [ar:Test Artist]
        [00:10.000]Hello
        [00:10.000][tr]你好
        [00:12.500]World
        [00:12.500][tr:zh-Hant]世界
        """))
        #expect(lyrics.idTags[.title] == "Test Song")
        #expect(lyrics.lines.map(\.content) == ["Hello", "World"])
        #expect(lyrics.lines[0].attachments.translation() == "你好")
        #expect(lyrics.lines[1].attachments[.translation(languageCode: "zh-Hant")] == "世界")
        #expect(lyrics.metadata.attachmentTags == [.translation(), .translation(languageCode: "zh-Hant")])

        #expect(try reloaded(lyrics).lines == lyrics.lines)
    }

    @Test func legacyInlineTranslationLoads() throws {
        let lyrics = try #require(Lyrics("""
        [00:10.00]Hello【你好】
        [00:12.50]【副歌】我爱你【I love you】
        [00:15.00]No translation
        """))
        #expect(lyrics.lines.map(\.content) == ["Hello", "【副歌】我爱你", "No translation"])
        #expect(lyrics.lines.map { $0.attachments.translation() } == ["你好", "I love you", nil])

        #expect(try reloaded(lyrics).lines == lyrics.lines)
    }

    @Test func legacyDescriptionReloadsWithItsTranslations() throws {
        let lyrics = Lyrics(lines: [
            line("【副歌】我爱你", at: 10, translation: "I love you"),
            line("Hello", at: 12.5, translation: "你好"),
        ], idTags: [:])

        let reloaded = try #require(Lyrics(lyrics.legacyDescription))
        #expect(reloaded.lines == lyrics.lines)
    }

    @Test func wordTimingSurvivesSaveAndReload() throws {
        var timed = line("[Chorus] said (oh yeah)", at: 10)
        timed.attachments.timetag = .init(
            tags: [.init(index: 0, time: 0), .init(index: 13, time: 0.2), .init(index: 23, time: 0.6)],
            duration: 0.6
        )
        let lyrics = Lyrics(lines: [timed, line("next", at: 11)], idTags: [:])

        let reloaded = try reloaded(lyrics)
        #expect(reloaded.lines == lyrics.lines)
        #expect(reloaded.lines[0].attachments.timetag?.description == "<0,0><200,13><600,23><600>")
    }

    @Test func repeatedTimeTagsExpandIntoLines() throws {
        let lyrics = try #require(Lyrics("[00:10.00][00:20.00]Repeat\n[00:15.00]Between"))
        #expect(lyrics.lines.map(\.content) == ["Repeat", "Between", "Repeat"])
        #expect(lyrics.lines.map(\.position) == [10, 15, 20])
        #expect(lyrics.metadata.attachmentTags.isEmpty)

        #expect(try reloaded(lyrics).lines == lyrics.lines)
    }
}
