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
- Spotify
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

#### Search lyrics from the internet

```swift
import LyricsService

// create a search request
let song = "Tranquilize"
let artist = "The Killers"
let duration = 225.2
let searchReq = LyricsSearchRequest(
    searchTerm: .info(title: song, artist: artist),
    duration: duration
)

// choose a lyrics service provider
let provider = LyricsProviders.Kugou()
// or search from multiple sources
let provider = LyricsProviders.Group(service: [.kugou, .netease, .qq])

// search
provider.lyricsPublisher(request: searchReq).sink { lyrics in
    print(lyrics)
}
```

#### Provider lifecycle events and canonical source names

```swift
import LyricsService

let group = LyricsProviders.Group(descriptors: [
    .init(source: "Kugou", provider: LyricsProviders.Kugou()),
    .init(source: "NetEase", provider: LyricsProviders.NetEase()),
])

for await event in group.events(for: searchReq) {
    print(event)
}
```

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

<id tag>            ::= <tag>
<tag>               ::= "[" <tag content> "]"
<tag content>       ::= <tag key>
                      | <tag key> ":" <tag value>
<tag key>           ::= [0-9a-zA-Z_-]+
<tag value>         ::= <character except NEWLINE or "]">+

<lyric line>        ::= <time tag> <character except NEWLINE>*
<lyric attachment>  ::= <time tag> <attachment tag> <attachment body>

<time tag>          ::= "[" (<minute> ":")* <second> ("." <millisecond>)* "]"

<attachment tag>            ::= <tag>
<attachment body>           ::= <plain text attachment>
                              | <index based attachment>
                              | <range based attachment>
<plain text attachment>     ::= <character except NEWLINE>+
<index based attachment>    ::= <index based segment>+
<range based attachment>    ::= <range based segment>+
<index based segment>       ::= "<" <segment value> "," <segment index> ">"
<range based segment>       ::= "<" <segment value> "," <segment range> ">"
<segment value>             ::= <characters except NEWLINE, "," or ">">
<segment index>             ::= <number>
<segment range>             ::= <lowerBound> "," <upperBound>
```

### Predefined tags

Predefined ID tags:

| Tag | Key | Value Type | Description |
| --- | --- | --- | --- |
| title | ti | string | |
| album | al | string | |
| artist | ar | string | |
| offset | offset | integer | |
| length | length | decimal | |

Predefind attachment tags:

| Tag | Key | Value Type | Attachment type | Description |
| --- | --- | --- | --- | --- |
| translation | tr | [RFC 4646](https://www.ietf.org/rfc/rfc4646.txt) | plain text | |
| word time tag | tt | no value | index based (with timestamp in millisecond) | |
| furigana | fu | no value | range based | |
| romaji | ro | no value | range based | |
