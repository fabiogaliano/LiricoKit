import Testing
import Foundation
@testable import LyricsService

struct KugouKrcDecrypterTests {
    private static let krcKey: [UInt8] = [64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105]

    /// Builds a payload the way Kugou serves it: "krc1", then a zlib stream XOR-ed with the KRC key.
    private static func encryptedPayload(for content: String) throws -> Data {
        let deflated = try (Data(content.utf8) as NSData).compressed(using: .zlib) as Data
        let zlibStream: [UInt8] = [0x78, 0x9C] + Array(deflated)
        let encoded = zlibStream.enumerated().map { $0.element ^ krcKey[$0.offset & 0b1111] }
        return Data("krc1".utf8) + Data(encoded)
    }

    @Test func decryptsAndParsesARealisticPayload() throws {
        let krc = """
        [id:$00000000]
        [ar:Test Artist]
        [ti:Test Song]
        [offset:0]
        [1200,600]<0,200,0>said <200,200,0><3 <400,200,0>you
        [1800,400]<0,200,0>Hello <200,200,0>world
        """
        let decrypted = try #require(decryptKugouKrc(try Self.encryptedPayload(for: krc)))
        #expect(decrypted == krc)

        let lyrics = try #require(Lyrics(kugouKrcContent: decrypted))
        #expect(lyrics.idTags[.title] == "Test Song")
        #expect(lyrics.lines.map(\.content) == ["said <3 you", "Hello world"])
    }

    @Test(arguments: [
        Data("krc1".utf8),
        Data("krc1".utf8) + Data([0x38]),
        Data("krc1".utf8) + Data([0x38, 0xDB]),
    ])
    func returnsNilForTruncatedPayloads(_ payload: Data) {
        #expect(decryptKugouKrc(payload) == nil)
    }
}
