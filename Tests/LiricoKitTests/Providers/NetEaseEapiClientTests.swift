import Testing
import Foundation
@testable import LyricsService

struct NetEaseEapiClientTests {
    @Test func md5HashKnownVectors() {
        // RFC 1321 standard test vectors
        #expect(NetEaseEapiClient.md5Hash("") == "d41d8cd98f00b204e9800998ecf8427e")
        #expect(NetEaseEapiClient.md5Hash("a") == "0cc175b9c0f1b6a831c399e269772661")
        #expect(NetEaseEapiClient.md5Hash("abc") == "900150983cd24fb0d6963f7d28e17f72")
        #expect(NetEaseEapiClient.md5Hash("message digest") == "f96b697d7cb7938d525a2f31aaf161d0")
    }

    @Test func aesEncryptMatchesOpenSSL() throws {
        // `openssl enc -aes-128-ecb` with the eapi key, PKCS#7 padding.
        let encrypted = try NetEaseEapiClient.aesEncryptECB(data: Data("Hello, eapi world!".utf8), key: NetEaseEapiClient.eapiKey)
        #expect(hexString(encrypted) == "0392E41FB19DB7B9D70F8357FF991910081F6F0133BACA84DF2E6AAF31E453D9")
    }

    @Test func aesEncryptPadsBlockAlignedInputWithAWholeBlock() throws {
        // `openssl enc -aes-128-ecb` with the eapi key, PKCS#7 padding.
        let encrypted = try NetEaseEapiClient.aesEncryptECB(data: Data("0123456789abcdef".utf8), key: NetEaseEapiClient.eapiKey)
        #expect(hexString(encrypted) == "12AD99C476F307B9AFA42686D88FA74F6AA3B102FBE7296AB0DB9EA5C46AD12B")
    }

    @Test func aesEncryptOfEmptyInputIsOnePaddingBlock() throws {
        // `openssl enc -aes-128-ecb` with the eapi key, PKCS#7 padding.
        let encrypted = try NetEaseEapiClient.aesEncryptECB(data: Data(), key: NetEaseEapiClient.eapiKey)
        #expect(hexString(encrypted) == "6AA3B102FBE7296AB0DB9EA5C46AD12B")
    }

    @Test func aesEncryptRejectsAKeyOfTheWrongSize() {
        #expect(throws: LyricsProviderError.self) {
            try NetEaseEapiClient.aesEncryptECB(data: Data("x".utf8), key: Data("short".utf8))
        }
    }

    @Test func aesEncryptIsDeterministicForSameInput() throws {
        let key = NetEaseEapiClient.eapiKey
        let plaintext = Data("Deterministic".utf8)
        let firstEncryption = try NetEaseEapiClient.aesEncryptECB(data: plaintext, key: key)
        let secondEncryption = try NetEaseEapiClient.aesEncryptECB(data: plaintext, key: key)
        #expect(firstEncryption == secondEncryption)
    }

    @Test func eApiParamsReturnsParamsKeyWithHexString() throws {
        let result = try NetEaseEapiClient.eApiParams(
            url: "https://interface3.music.163.com/eapi/song/lyric/v1",
            object: ["id": "12345"]
        )
        let hex = try #require(result["params"])
        // Hex string of AES output: even length, uppercase A-F + digits.
        #expect(hex.count % 2 == 0)
        #expect(hex.allSatisfy { ($0.isNumber) || ($0 >= "A" && $0 <= "F") })
        // AES ECB output is a multiple of 16 bytes -> hex length multiple of 32.
        #expect(hex.count % 32 == 0)
    }

    @Test func eApiParamsMatchesReferenceEncoding() throws {
        // `md5` and `openssl enc -aes-128-ecb` over
        // `/api/song/lyric/v1-36cd479b6b5-{"id":"12345"}-36cd479b6b5-<md5>`, where <md5> digests
        // `nobody/api/song/lyric/v1use{"id":"12345"}md5forencrypt`.
        let result = try NetEaseEapiClient.eApiParams(
            url: "https://interface3.music.163.com/eapi/song/lyric/v1",
            object: ["id": "12345"]
        )
        #expect(result == [
            "params": "04AE33D34A93FE3EC22DA8FA305D290AB337D0FE5F36D211DE0D338CC6AA89D0"
                + "242B1150EAD66640AC447793C004C8DC97DB035B47C04646B0430453EA881D52"
                + "EE562FD80E3C439347440875E9587F0CBBF2286DD92731457D3A3479BB7DD229",
        ])
    }

    @Test func eApiParamsIsDeterministicForSameInput() throws {
        let url = "https://interface3.music.163.com/eapi/song/lyric/v1"
        let payload: [String: String] = ["id": "12345", "csrf_token": ""]
        let first = try NetEaseEapiClient.eApiParams(url: url, object: payload)
        let second = try NetEaseEapiClient.eApiParams(url: url, object: payload)
        #expect(first == second)
    }

    @Test func normalizeEapiURLRewritesApiToEapi() {
        let input = "https://interface.music.163.com/api/song/lyric/v1"
        let normalized = NetEaseEapiClient.normalizeEapiURL(input)
        #expect(normalized.contains("/eapi/"))
        #expect(!normalized.contains("/api/"))
    }
}

private func hexString(_ data: Data) -> String {
    data.map { String(format: "%02X", $0) }.joined()
}
