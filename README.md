# LiricoKit

Lyrics search and parsing engine for [Lirico](https://github.com/fabiogaliano/Lirico). Forked from [LyricsKit](https://github.com/MxIris-LyricsX-Project/LyricsKit), the lyrics submodule of [LyricsX](https://github.com/ddddxxx/LyricsX).

## Installation

```swift
.package(url: "https://github.com/fabiogaliano/LiricoKit", from: "2.0.0")
```

Products: `LiricoKit` (core + providers) and `LiricoKitAppleMusic` (Apple Music support, links WebKit).

## Supported Sources

- NetEase Music
- QQ Music
- Kugou Music
- LRCLIB
- Musixmatch
- <del>TTPod</del>
- <del>Gecimi</del>
- <del>Syair</del>
- <del>Xiami Music</del> (discontinued)
- <del>ViewLyrics</del> (not working anymore)

## What's New in 2.0.0

- Renamed from LyricsKit to LiricoKit: the package, `LiricoKit` product/module, and `LiricoKitAppleMusic` product. Replace `import LyricsKit` with `import LiricoKit`; `LyricsCore`, `LyricsService`, and `LyricsServiceUI` are unchanged.

## What's New in 1.9.0

- `LyricsProviders.Group.events(for:)` exposes a non-throwing provider lifecycle stream.
- `LyricsProviders.ProviderDescriptor` lets callers stamp canonical source names into grouped searches.
- `LyricsSearchRequest.albumName` exposes typed album metadata for providers that can use it.
- LRCLIB now runs broad `/api/search` and exact `/api/get` lookups concurrently when full track metadata is available.

## Usage

#### Search one source

```swift
import LiricoKit

let request = LyricsSearchRequest(
    searchTerm: .info(title: "Tranquilize", artist: "The Killers"),
    duration: 225.2
)

let kugou = LyricsProviders.Service.kugou.create()
for try await lyrics in kugou.lyrics(for: request) {
    print(lyrics)
}
```

Each source's results arrive as they finish downloading, not in search-rank order. The stream throws when the search fails, or when none of the lyrics downloads reach the service.

#### Search several sources

`Group` runs its sources concurrently and reports each one's progress as events. A failing source never stops the others.

```swift
let group = LyricsProviders.Group(descriptors: [
    .init(source: "Kugou", provider: LyricsProviders.Service.kugou.create()),
    .init(source: "NetEase", provider: LyricsProviders.Service.netease.create()),
    .init(source: "LRCLIB", provider: LyricsProviders.Service.lrclib.create()),
])

for await event in group.events(for: request) {
    switch event {
    case .candidate(let source, let lyrics):
        print(source, lyrics.idTags[.title] ?? "")
    case .providerFailed(let source, _, let message, _):
        print("\(source) failed: \(message)")
    case .completed:
        print("done")
    default:
        break
    }
}
```

The stream ends without `.completed` when the consumer stops iterating or its task is cancelled, and in-flight requests are cancelled with it.

#### Musixmatch source requires a token

The method for retrieving lyrics from Musixmatch is adapted from [LyricsPlus](https://github.com/spicetify/cli/tree/main/CustomApps/lyrics-plus). To use this feature properly, you need to follow the steps provided [here](https://gist.github.com/TrueMyst/0461aea999e347182486934fd83a4cf9) or [here](https://spicetify.app/docs/faq#sometimes-popup-lyrics-andor-lyrics-plus-seem-to-not-work) to obtain a usertoken.

## License

LiricoKit is derived from LyricsKit (part of LyricsX) and licensed under MPL 2.0. See the [LICENSE file](LICENSE).

## LRCX file

### Specification

```
<lrcx>              ::= <line> (NEWLINE <line>)*
<line>              ::= <id tag>
                      | <lyric line>
                      | <lyric attachment>
                      | ""

<id tag>            ::= "[" <tag key> ":" <tag value> "]"
<tag key>           ::= <character except NEWLINE or ":">+
<tag value>         ::= <character except NEWLINE>+

<lyric line>        ::= <time tag>+ <lyrics text> <inline translation>?
<lyric attachment>  ::= <time tag>+ "[" <attachment tag> "]" <attachment body>

<time tag>          ::= "[" ("+" | "-")? <minutes> ":" <seconds> ("." <fraction>)? "]"
<minutes>           ::= <digit>+
<seconds>           ::= <digit>+
<fraction>          ::= <digit>+

<lyrics text>       ::= <character except NEWLINE>*
<inline translation>::= "【" <character except NEWLINE or "【">* "】"

<attachment tag>            ::= <character except NEWLINE or "]">+
<attachment body>           ::= <plain text attachment>
                              | <index based attachment>
                              | <range based attachment>
<plain text attachment>     ::= <character except NEWLINE>*
<index based attachment>    ::= <index based segment>+ <duration segment>?
<range based attachment>    ::= <range based segment>+
<index based segment>       ::= "<" <milliseconds> "," <character index> ">"
<duration segment>          ::= "<" <milliseconds> ">"
<range based segment>       ::= "<" <segment value> "," <lower bound> "," <upper bound> ">"
<segment value>             ::= <character except NEWLINE, "," or ">">+
```

- A line with several time tags is repeated at each time.
- An attachment applies to the lyric line with the same time tag, and is written after it. An attachment-shaped line with no lyric line at its time is read as a lyric line whose text starts with `[`.
- An attachment tag can't itself be a time tag.
- `<inline translation>` is the legacy translation format. It is only read as a translation when it ends the line and follows some lyrics text; otherwise it is part of the text.

### Predefined tags

Predefined ID tags:

| Tag | Key | Value |
| --- | --- | --- |
| title | ti | string |
| album | al | string |
| artist | ar | string |
| author | au | string |
| lyrics by | by | string |
| offset | offset | integer, milliseconds |
| length | length | seconds, or `minutes:seconds` |

Predefined attachment tags:

| Tag | Key | Body |
| --- | --- | --- |
| translation | `tr`, or `tr:<language>` with an [RFC 4646](https://www.ietf.org/rfc/rfc4646.txt) code | plain text |
| word time tag | tt | index based: milliseconds from the line's start, at each character index |
| furigana | fu | range based |
| romaji | ro | range based |
