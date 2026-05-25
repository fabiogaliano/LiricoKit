# Changelog

## 1.9.0

- add `LyricsProviders.Group.events(for:)` for non-throwing provider lifecycle streaming
- add `LyricsProviders.ProviderDescriptor` for canonical grouped-source identity
- add `LyricsSearchRequest.albumName` typed accessor for provider-side album metadata
- teach LRCLIB to race broad `/api/search` with exact `/api/get` when title, artist, album, and duration are all present
