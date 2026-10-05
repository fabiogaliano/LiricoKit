/// This structure represents the full response from the Musixmatch "track.search" API endpoint:
/// https://apic-desktop.musixmatch.com/ws/1.1/track.search
struct MusixmatchResponseSearchResult: Decodable {
    struct Message: Decodable {
        struct Body: Decodable {
            struct TrackContainer: Decodable {
                let track: Track
            }

            let trackList: [TrackContainer]?

            enum CodingKeys: String, CodingKey {
                case trackList = "track_list"
            }
        }

        struct Header: Decodable {
            let hint: String?
            let statusCode: Int

            enum CodingKeys: String, CodingKey {
                case hint
                case statusCode = "status_code"
            }
        }

        let body: Body?
        let header: Header
    }

    let message: Message

    struct Track: Decodable {
        /// Preference order: 800x800 -> 500x500 -> 350x350 -> 100x100 -> empty string
        var albumCoverBest: String {
            if let s = albumCoverart800x800, !s.isEmpty { return s }
            if let s = albumCoverart500x500, !s.isEmpty { return s }
            if let s = albumCoverart350x350, !s.isEmpty { return s }
            if let s = albumCoverart100x100, !s.isEmpty { return s }
            return ""
        }
        
        let albumCoverart100x100: String?
        let albumCoverart350x350: String?
        let albumCoverart500x500: String?
        let albumCoverart800x800: String?
        let albumName: String
        let artistName: String
        let hasSubtitles: Int
        let instrumental: Int
        let trackId: Int
        let trackLength: Int
        let trackName: String
        let trackSpotifyId: String

        enum CodingKeys: String, CodingKey {
            case albumCoverart100x100 = "album_coverart_100x100"
            case albumCoverart350x350 = "album_coverart_350x350"
            case albumCoverart500x500 = "album_coverart_500x500"
            case albumCoverart800x800 = "album_coverart_800x800"
            case albumName = "album_name"
            case artistName = "artist_name"
            case hasSubtitles = "has_subtitles"
            case instrumental
            case trackId = "track_id"
            case trackLength = "track_length"
            case trackName = "track_name"
            case trackSpotifyId = "track_spotify_id"
        }
    }
}
