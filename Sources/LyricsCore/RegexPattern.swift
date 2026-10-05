import Foundation
// Regex predates Sendable; its patterns are immutable NSRegularExpressions,
// which are safe to share.
@preconcurrency import Regex

// Patterns are StaticStrings so they take Regex's non-throwing initializer. Given a literal
// and `options:`, Swift 6.3 picks the throwing String one, which a global can't call.

private let timeTagRegex = Regex(#"\[([-+]?\d+):(\d+(?:\.\d+)?)\]"# as StaticString)

func resolveTimeTag(_ str: String) -> [TimeInterval] {
    let matchs = timeTagRegex.matches(in: str)
    return matchs.map { match in
        let min = Double(match[1]!.content)!
        let sec = Double(match[2]!.content)!
        return min * 60 + sec
    }
}

let id3TagRegex = Regex(#"^(?!\[[+-]?\d+:\d+(?:\.\d+)?\])\[(.+?):(.+)\]$"# as StaticString, options: .anchorsMatchLines)

// Legacy files put a translation in a trailing `【…】` after the lyrics. Brackets
// anywhere else, or with no lyrics before them, are part of the lyrics.
// Groups: 1 time tags, 2 lyrics before a translation, 3 translation, 4 lyrics without one.
let lyricsLineRegex = Regex(#"^((?:\[[+-]?\d+:\d+(?:\.\d+)?\])+)(?!\[)(?:([^\n\r]+?)【([^【\n\r]*)】[^\S\n\r]*|([^\n\r]*))(?=[\n\r]|\z)"# as StaticString, options: .anchorsMatchLines)

let base60TimeRegex = Regex(#"^\s*(?:(\d+):)?(\d+(?:.\d+)?)\s*$"# as StaticString)

// A second time tag is a repeated line, not an attachment tag.
let lyricsLineAttachmentRegex = Regex(#"^((?:\[[+-]?\d+:\d+(?:\.\d+)?\])+)\[(?![+-]?\d+:\d+(?:\.\d+)?\])(.+?)\](.*)"# as StaticString, options: .anchorsMatchLines)

let timeLineAttachmentRegex = Regex(#"<(\d+,\d+)>"# as StaticString)

let timeLineAttachmentDurationRegex = Regex(#"<(\d+)>"# as StaticString)

let rangeAttachmentRegex = Regex(#"<([^,]+,\d+,\d+)>"# as StaticString)
