import Testing
import Foundation
@testable import LyricsService

/// Outputs pinned from the previous quadratic implementation.
struct XMLUtilsTests {
    @Test func removesAttributeOnlyTagFromALyricDownloadResponse() {
        let response = """

        <?xml version="1.0" encoding="utf-8"?>

        <lyric>
        <content>A1B2C3D4E5F60718</content>
        <contentts>0918273645AABBCC</contentts>
        <contentroma></contentroma>
        <miniversion="1" />
        </lyric>


        """
        let expected = """
        <?xml version="1.0" encoding="utf-8"?>

        <lyric>
        <content>A1B2C3D4E5F60718</content>
        <contentts>0918273645AABBCC</contentts>
        <contentroma></contentroma>

        </lyric>
        """
        #expect(XMLUtils.removeIllegalContent(response) == expected)
    }

    @Test func keepsWellFormedSelfClosingTags() {
        let decryptedQrc = """
        <?xml version="1.0" encoding="utf-8"?>
        <QrcInfos>
        <QrcHeadInfo SaveTime="1700000000" Version="100"/>
        <LyricInfo LyricCount="1">
        <Lyric_1 LyricType="1" LyricContent="[0,500]Hello(0,500)"/>
        </LyricInfo>
        </QrcInfos>
        """
        #expect(XMLUtils.removeIllegalContent(decryptedQrc) == decryptedQrc)
    }

    @Test func removesTagsExposedByAnEarlierRemoval() {
        let input = #"<root><a=<b="1"/>/><c x="2"/><d ="3" /></root>"#
        #expect(XMLUtils.removeIllegalContent(input) == #"<root><c x="2"/></root>"#)
    }

    @Test func handlesLongResponsesInLinearTime() {
        let hex = String(repeating: "A1B2C3D4E5F60718", count: 1440)
        let response = "<lyric>\n<content>\(hex)</content>\n<miniversion=\"1\" />\n</lyric>"

        let cleaned = XMLUtils.removeIllegalContent(response)

        #expect(cleaned == "<lyric>\n<content>\(hex)</content>\n\n</lyric>")
    }
}
