import Foundation
import LyricsCore

extension Lyrics.Metadata.Key {
    public static let request = Lyrics.Metadata.Key("request")
    public static let remoteURL = Lyrics.Metadata.Key("remoteURL")
    public static let artworkURL = Lyrics.Metadata.Key("artworkURL")
    public static let service = Lyrics.Metadata.Key("service")
    public static let serviceToken = Lyrics.Metadata.Key("serviceToken")
}

extension Lyrics.Metadata {
    public var request: LyricsSearchRequest? {
        get { return data[.request] as? LyricsSearchRequest }
        set { data[.request] = newValue }
    }

    public var remoteURL: URL? {
        get { return data[.remoteURL] as? URL }
        set { data[.remoteURL] = newValue }
    }

    public var artworkURL: URL? {
        get { return data[.artworkURL] as? URL }
        set { data[.artworkURL] = newValue }
    }

    public var service: String? {
        get { return data[.service] as? String }
        set { data[.service] = newValue }
    }

    public var serviceToken: String? {
        get { return data[.serviceToken] as? String }
        set { data[.serviceToken] = newValue }
    }
}

extension Lyrics {
    /// Whether this result was found via a request a `LyricsSearchRequestPlugin`
    /// derived from the caller's original search, rather than via the original
    /// request itself — e.g. an Apple Music name-recovery re-search.
    public var isFromSearchPlugin: Bool {
        metadata.request?.origin == .plugin
    }

    /// The search term a `LyricsSearchRequestPlugin` used to find this result
    /// — e.g. the recovered native-script name. `nil` for a result from the
    /// caller's original search.
    public var searchPluginTerm: LyricsSearchRequest.SearchTerm? {
        guard isFromSearchPlugin else {
            return nil
        }
        return metadata.request?.searchTerm
    }
}
