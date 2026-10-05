import Foundation
import Synchronization

public final class Lyrics: LosslessStringConvertible, Sendable {
    private struct Content {
        var lines: [LyricsLine]
        var idTags: [IDTagKey: String]
        var metadata: Metadata
    }

    // Lyrics outlive the search that found them: callers hand them between
    // tasks, the main actor and display queues and keep editing them there
    // (offset, filtering), so every access goes through one lock. An edit
    // through a property, like `lines[i].enabled = false`, is a read and a
    // separate write, so two threads editing one property can still lose an edit.
    private let content: Mutex<Content>

    public var lines: [LyricsLine] {
        get { content.withLock { $0.lines } }
        set { content.withLock { $0.lines = newValue } }
    }

    public var idTags: [IDTagKey: String] {
        get { content.withLock { $0.idTags } }
        set { content.withLock { $0.idTags = newValue } }
    }

    public var metadata: Metadata {
        get { content.withLock { $0.metadata } }
        set { content.withLock { $0.metadata = newValue } }
    }

    public init(lines: [LyricsLine], idTags: [IDTagKey: String], metadata: Metadata = Metadata()) {
        var metadata = metadata
        metadata.attachmentTags = Set(lines.flatMap(\.attachments.content.keys))
        content = Mutex(Content(lines: lines, idTags: idTags, metadata: metadata))
        content.withLock { content in
            for idx in content.lines.indices {
                content.lines[idx].lyrics = self
            }
        }
    }

    public convenience init?(_ description: String) {
        var idTags: [IDTagKey: String] = [:]
        id3TagRegex.matches(in: description).forEach { match in
            if let key = match[1]?.content.trimmingCharacters(in: .whitespaces),
               let value = match[2]?.content.trimmingCharacters(in: .whitespaces),
               !value.isEmpty {
                idTags[.init(key)] = value
            }
        }

        var lines = lyricsLineRegex.matches(in: description).flatMap { match -> [LyricsLine] in
            let timeTagStr = match[1]!.string
            let timeTags = resolveTimeTag(timeTagStr)

            let lyricsContentStr = (match[2] ?? match[4])!.string
            var line = LyricsLine(content: lyricsContentStr, position: 0)

            if let translationStr = match[3]?.string, !translationStr.isEmpty {
                line.attachments[.translation()] = translationStr
            }

            return timeTags.map { timeTag in
                var l = line
                l.position = timeTag
                return l
            }
        }.sorted {
            $0.position < $1.position
        }

        guard !lines.isEmpty else {
            return nil
        }

        var tags: Set<LyricsLine.Attachments.Tag> = []
        lyricsLineAttachmentRegex.matches(in: description).forEach { match in
            let timeTagStr = match[1]!.string
            let timeTags = resolveTimeTag(timeTagStr)

            let attachmentTagStr = match[2]!.string
            let attachmentStr = match[3]?.string ?? ""

            for timeTag in timeTags {
                switch lines.lineIndex(of: timeTag) {
                case .found(at: let index):
                    lines[index].attachments[.init(attachmentTagStr)] = attachmentStr
                    tags.insert(.init(attachmentTagStr))
                case .notFound(insertAt: let index):
                    // `description` writes every line before its attachments, so an
                    // attachment with no line at its time is a line whose text starts with "[".
                    lines.insert(LyricsLine(content: "[\(attachmentTagStr)]\(attachmentStr)", position: timeTag), at: index)
                }
            }
        }
        self.init(lines: lines, idTags: idTags)
        content.withLock { $0.metadata.attachmentTags = tags }
    }

    public var description: String {
        let (idTags, lines) = content.withLock { ($0.idTags, $0.lines) }
        let components = idTags.map { "[\($0.key.rawValue):\($0.value)]" }
            + lines.map(\.description)
        return components.joined(separator: "\n")
    }

    public var legacyDescription: String {
        let (idTags, lines) = content.withLock { ($0.idTags, $0.lines) }
        let components = idTags.map { "[\($0.key.rawValue):\($0.value)]" } + lines.map { "[\($0.timeTag)]\($0.content)" + ($0.attachments.translation().map { "【\($0)】" } ?? "") }
        return components.joined(separator: "\n")
    }

    public struct IDTagKey: RawRepresentable, Hashable, Sendable {
        public var rawValue: String

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static let title = IDTagKey("ti")
        public static let album = IDTagKey("al")
        public static let artist = IDTagKey("ar")
        public static let author = IDTagKey("au")
        public static let lrcBy = IDTagKey("by")
        public static let offset = IDTagKey("offset")
        public static let length = IDTagKey("length")
    }

    public struct Metadata: Sendable {
        public var data: [Key: any Sendable]

        public init(data: [Key: any Sendable] = [:]) {
            self.data = data
        }

        public struct Key: RawRepresentable, Hashable, Sendable {
            public var rawValue: String

            public init(_ rawValue: String) {
                self.rawValue = rawValue
            }

            public init(rawValue: String) {
                self.rawValue = rawValue
            }
        }
    }
}

extension Lyrics {
    public var offset: Int {
        get {
            return idTags[.offset].flatMap { Int($0) } ?? 0
        }
        set {
            content.withLock { $0.idTags[.offset] = "\(newValue)" }
        }
    }

    public var timeDelay: TimeInterval {
        get {
            return TimeInterval(offset) / 1000
        }
        set {
            offset = Int(newValue * 1000)
        }
    }

    public var length: TimeInterval? {
        get {
            guard let len = idTags[.length],
                  let match = base60TimeRegex.firstMatch(in: len) else {
                return nil
            }
            let min = (match[1]?.content).flatMap(Double.init) ?? 0
            let sec = Double(match[2]!.content) ?? 0
            return min * 60 + sec
        }
        set {
            guard let newValue = newValue else {
                content.withLock { _ = $0.idTags.removeValue(forKey: .length) }
                return
            }
            let fmt = NumberFormatter()
            fmt.minimumFractionDigits = 0
            fmt.maximumFractionDigits = 2
            let str = fmt.string(from: newValue as NSNumber)
            content.withLock { $0.idTags[.length] = str }
        }
    }

    public subscript(_ position: TimeInterval) -> (currentLineIndex: Int?, nextLineIndex: Int?) {
        let lines = self.lines
        let index: Int
        switch lines.lineIndex(of: position) {
        case .found(at: let i): index = i + 1
        case .notFound(insertAt: let i): index = i
        }
        let current = (0 ..< index).reversed().first { lines[$0].enabled }
        let next = lines[index...].firstIndex(where: \.enabled)
        return (current, next)
    }
}

private enum LineMatch {
    case found(at: Int)
    case notFound(insertAt: Int)
}

extension [LyricsLine] {
    fileprivate func lineIndex(of position: TimeInterval) -> LineMatch {
        var left = 0
        var right = count - 1

        while left <= right {
            let mid = (left + right) / 2
            let candidate = self[mid]
            if candidate.position < position {
                left = mid + 1
            } else if position < candidate.position {
                right = mid - 1
            } else {
                return .found(at: mid)
            }
        }
        return .notFound(insertAt: left)
    }
}

extension Lyrics {
    public func filtrate(isIncluded predicate: NSPredicate) {
        // The predicate is caller code that may read these lyrics, so it can't
        // run while the lock is held.
        let lines = self.lines
        let excluded = lines.indices.filter { !predicate.evaluate(with: lines[$0]) }
        content.withLock { content in
            for index in excluded where content.lines.indices.contains(index) {
                content.lines[index].enabled = false
            }
        }
    }
}

// MARK: CustomStringConvertible

extension Lyrics.Metadata: CustomStringConvertible {
    public var description: String {
        return Mirror(reflecting: self).children.map { "[\($0!):\($1)]" }.joined(separator: "\n")
    }
}

extension Lyrics.IDTagKey: CustomStringConvertible {
    public var description: String {
        return rawValue
    }
}
