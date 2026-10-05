import Foundation
import Regex

let id3TagRegex = Regex(#"^(?!\[[+-]?\d+:\d+(?:\.\d+)?\])\[(.+?):(.+)\]$"#, options: .anchorsMatchLines)

let krcLineRegex = Regex(#"^\[(\d+),(\d+)\](.*)"#, options: .anchorsMatchLines)

let qrcLineRegex = Regex(#"^\[(\d+),(\d+)\](.*)"#, options: [.anchorsMatchLines])

// Lyric text can contain the brackets the timing tags use, so each text
// fragment runs up to the next complete tag, not the next bracket.
let netEaseYrcInlineTagRegex = Regex(#"\((\d+),(\d+),0\)((?:(?!\(\d+,\d+,0\)).)*)"#)

let netEaseInlineTagRegex = Regex(#"\(0,(\d+)\)((?:(?!\(0,\d+\)).)+)(\(0,1\) )?"#)

let kugouInlineTagRegex = Regex(#"<(\d+),(\d+),0>((?:(?!<\d+,\d+,0>).)*)"#)

let qqmusicInlineTagRegex = Regex(#"((?:(?!\(\d+,\d+\)).)*)\((\d+),(\d+)\)"#)
