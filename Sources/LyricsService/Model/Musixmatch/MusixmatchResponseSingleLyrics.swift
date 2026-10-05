/// This structure represents the full response from the Musixmatch "macro.subtitles.get" API endpoint:
/// https://apic-desktop.musixmatch.com/ws/1.1/macro.subtitles.get
struct MusixmatchResponseSingleLyrics: Decodable {
    struct Message: Decodable {
        struct Body: Decodable {
            struct MacroCalls: Decodable {
                let matcherTrackGet: MatcherTrackGet?
                let trackSubtitlesGet: TrackSubtitlesGet?

                enum CodingKeys: String, CodingKey {
                    case matcherTrackGet = "matcher.track.get"
                    case trackSubtitlesGet = "track.subtitles.get"
                }
            }

            let macroCalls: MacroCalls

            enum CodingKeys: String, CodingKey {
                case macroCalls = "macro_calls"
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

        let body: Body
        let header: Header
    }

    let message: Message

    struct MatcherTrackGet: Decodable {
        struct Message: Decodable {
            struct Body: Decodable {
                let track: MusixmatchResponseSearchResult.Track
            }

            struct Header: Decodable {
                let statusCode: Int

                enum CodingKeys: String, CodingKey {
                    case statusCode = "status_code"
                }
            }

            let body: Body
            let header: Header
        }

        let message: Message
    }

    struct TrackSubtitlesGet: Decodable {
        struct Message: Decodable {
            struct Body: Decodable {
                let subtitleList: [SubtitleListItem]?

                enum CodingKeys: String, CodingKey {
                    case subtitleList = "subtitle_list"
                }
            }

            struct Header: Decodable {
                let statusCode: Int

                enum CodingKeys: String, CodingKey {
                    case statusCode = "status_code"
                }
            }

            let body: Body
            let header: Header
        }

        let message: Message
    }

    struct SubtitleListItem: Decodable {
        let subtitle: Subtitle
    }

    struct Subtitle: Decodable {
        let subtitleBody: String

        enum CodingKeys: String, CodingKey {
            case subtitleBody = "subtitle_body"
        }
    }
}
