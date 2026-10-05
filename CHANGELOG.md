# Changelog

## Unreleased

- **breaking:** remove the `LyricsServiceUI` module (source icon drawing); `LiricoKit` no longer re-exports it
- **breaking:** remove `Lyrics.quality`, `Lyrics.isMatched()` and `Lyrics.generateFurigana()`
- **breaking:** remove `LyricsProviders.Group.lyrics(for:)`; `Group` no longer conforms to `LyricsProvider` (it is still `Sendable`). Use `events(for:)`
- **breaking:** `LyricsProviderError` has a new `httpError(statusCode:)` case, so exhaustive switches over it need updating
- drop the SwiftCF dependency, which only furigana generation used
- fix word-timed lyrics (QQ Music QRC, NetEase YRC and klyric, Kugou KRC) dropping text that contains `(` or `<`, e.g. "said (oh yeah)"
- fix a crash on Kugou KRC payloads shorter than three bytes
- fix `Lyrics(_:)` losing text when reloading saved lyrics: lines like `【副歌】我爱你` or `【間奏】` no longer load as a translation, lines starting with `[` such as `[Chorus] la la` are no longer dropped as attachments, and lines with several time tags are no longer duplicated on each save
- report non-2xx responses as the new `LyricsProviderError.httpError(statusCode:)` instead of a decoding error, or an empty result when the error body happened to decode
- cancel in-flight lyrics downloads when a provider stream or `Group.events(for:)` consumer is cancelled
- yield each provider's results as their downloads finish, so one slow download no longer holds back the rest; results within a provider no longer arrive in search-rank order
- time out each request after 10 s instead of URLSession's 60 s
- fail a provider (`providerFailed` in `Group.events(for:)`) when its search found songs but none of the lyrics downloads reached the service; downloads that reach it and find no lyrics still finish with zero results
- LRCLIB: skip records without synced lyrics before applying the request's `limit`, and stop refetching them by id
- QQ Music: clean up the XML response in linear time (was seconds on long lyrics)
- drop the unused BigInt and swift-async-algorithms dependencies

## 2.0.0

- rename package LyricsKit → LiricoKit: products `LiricoKit` and `LiricoKitAppleMusic`, umbrella module `LiricoKit` (replace `import LyricsKit`); repository moved to `fabiogaliano/LiricoKit`

## 1.9.0

- add `LyricsProviders.Group.events(for:)` for non-throwing provider lifecycle streaming
- add `LyricsProviders.ProviderDescriptor` for canonical grouped-source identity
- add `LyricsSearchRequest.albumName` typed accessor for provider-side album metadata
- teach LRCLIB to race broad `/api/search` with exact `/api/get` when title, artist, album, and duration are all present
