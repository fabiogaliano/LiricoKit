import Foundation
import Regex

// swiftlint:disable force_try
private let timeTagRegex = try! Regex(#"\[([-+]?\d+):(\d+(?:\.\d+)?)\]"#)

func resolveTimeTag(_ str: String) -> [TimeInterval] {
    let matchs = timeTagRegex.matches(in: str)
    return matchs.map { match in
        let min = Double(match[1]!.content)!
        let sec = Double(match[2]!.content)!
        return min * 60 + sec
    }
}

let id3TagRegex = try! Regex(#"^(?!\[[+-]?\d+:\d+(?:\.\d+)?\])\[(.+?):(.+)\]$"#, options: .anchorsMatchLines)

// Legacy files put a translation in a trailing `【…】` after the lyrics. Brackets
// anywhere else, or with no lyrics before them, are part of the lyrics.
// Groups: 1 time tags, 2 lyrics before a translation, 3 translation, 4 lyrics without one.
let lyricsLineRegex = Regex(#"^((?:\[[+-]?\d+:\d+(?:\.\d+)?\])+)(?!\[)(?:([^\n\r]+?)【([^【\n\r]*)】[^\S\n\r]*|([^\n\r]*))(?=[\n\r]|\z)"#, options: .anchorsMatchLines)

let base60TimeRegex = try! Regex(#"^\s*(?:(\d+):)?(\d+(?:.\d+)?)\s*$"#)

// A second time tag is a repeated line, not an attachment tag.
let lyricsLineAttachmentRegex = Regex(#"^((?:\[[+-]?\d+:\d+(?:\.\d+)?\])+)\[(?![+-]?\d+:\d+(?:\.\d+)?\])(.+?)\](.*)"#, options: .anchorsMatchLines)

let timeLineAttachmentRegex = try! Regex(#"<(\d+,\d+)>"#)

let timeLineAttachmentDurationRegex = try! Regex(#"<(\d+)>"#)

let rangeAttachmentRegex = try! Regex(#"<([^,]+,\d+,\d+)>"#)
// swiftlint:enable force_try
