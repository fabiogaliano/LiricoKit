import Foundation
// Regex predates Sendable; its patterns are immutable NSRegularExpressions,
// which are safe to share.
@preconcurrency import Regex

// Patterns are StaticStrings so they take Regex's non-throwing initializer. Given a literal
// and `options:`, Swift 6.3 picks the throwing String one, which a global can't call.

let id3TagRegex = Regex(#"^(?!\[[+-]?\d+:\d+(?:\.\d+)?\])\[(.+?):(.+)\]$"# as StaticString, options: .anchorsMatchLines)

let krcLineRegex = Regex(#"^\[(\d+),(\d+)\](.*)"# as StaticString, options: .anchorsMatchLines)

let qrcLineRegex = Regex(#"^\[(\d+),(\d+)\](.*)"# as StaticString, options: [.anchorsMatchLines])

// Lyric text can contain the brackets the timing tags use, so each text
// fragment runs up to the next complete tag, not the next bracket.
let netEaseYrcInlineTagRegex = Regex(#"\((\d+),(\d+),0\)((?:(?!\(\d+,\d+,0\)).)*)"# as StaticString)

let netEaseInlineTagRegex = Regex(#"\(0,(\d+)\)((?:(?!\(0,\d+\)).)+)(\(0,1\) )?"# as StaticString)

let kugouInlineTagRegex = Regex(#"<(\d+),(\d+),0>((?:(?!<\d+,\d+,0>).)*)"# as StaticString)

let qqmusicInlineTagRegex = Regex(#"((?:(?!\(\d+,\d+\)).)*)\((\d+),(\d+)\)"# as StaticString)

let netEaseTimeTagFixer = Regex(#"(\[\d+:\d+):(\d+\])"# as StaticString)
