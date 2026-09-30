import Foundation

protocol QQMusicSongSearchResult {
    var id: String { get }
    var mid: String { get }
    var name: String { get }
    var singers: [String] { get }
    /// Present only in the desktop search response; lets the cover URL be built without a lookup.
    var albumMid: String? { get }
}

extension QQMusicSongSearchResult {
    var albumMid: String? { nil }
}

struct QQResponseSearchResult: Decodable {
    let data: Data
    let code: Int

    struct Data: Decodable {
        let song: Song

        struct Song: Decodable {
            let list: [Item]
            enum CodingKeys: String, CodingKey {
                case list = "itemlist"
            }

            struct Item: Decodable, QQMusicSongSearchResult {
                var singers: [String] { [singer] }
                let mid: String
                let name: String
                let singer: String
                let id: String
            }
        }
    }
}

extension QQResponseSearchResult {
    var songs: [Data.Song.Item] {
        return data.song.list
    }
}

struct QQResponseSearchResult2: Decodable {
    struct Request: Decodable {
        struct Data: Decodable {
            struct Body: Decodable {
                struct Song: Decodable {
                    struct Item: Decodable, QQMusicSongSearchResult {
                        struct Singer: Decodable {
                            let name: String
                        }

                        struct Album: Decodable {
                            let mid: String?
                        }

                        let mid: String
                        let name: String
                        let _id: Int
                        let singer: [Singer]
                        let album: Album?
                        var singers: [String] { singer.map(\.name) }
                        var id: String { .init(_id) }
                        var albumMid: String? { album?.mid.flatMap { $0.isEmpty ? nil : $0 } }
                        enum CodingKeys: String, CodingKey {
                            case mid
                            case name
                            case _id = "id"
                            case singer
                            case album
                        }
                    }

                    let list: [Item]
                }

                let song: Song
            }

            let body: Body
        }

        let data: Data
        let code: Int
    }

    let request: Request

    enum CodingKeys: String, CodingKey {
        case request = "req_1"
    }
}
