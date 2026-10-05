import Foundation
import LyricsCore

private let mergeTimetagThreshold = 0.02

extension Lyrics {
    // Both merges edit a local copy of the lines and store it back once: each
    // write through `lines` copies the whole array.
    func merge(translation: Lyrics) {
        var lines = self.lines
        let translationLines = translation.lines
        var index = lines.startIndex
        var transIndex = translationLines.startIndex
        while index < lines.endIndex, transIndex < translationLines.endIndex {
            if abs(lines[index].position - translationLines[transIndex].position) < mergeTimetagThreshold {
                let transStr = translationLines[transIndex].content
                if !transStr.isEmpty, transStr != "//" {
                    lines[index].attachments[.translation()] = transStr
                }
                lines.formIndex(after: &index)
                translationLines.formIndex(after: &transIndex)
            } else if lines[index].position > translationLines[transIndex].position {
                translationLines.formIndex(after: &transIndex)
            } else {
                lines.formIndex(after: &index)
            }
        }
        self.lines = lines
        metadata.attachmentTags.insert(.translation())
    }

    /// merge without maching timetag
    func forceMerge(translation: Lyrics) {
        var lines = self.lines
        let translationLines = translation.lines
        guard lines.count == translationLines.count else {
            return
        }
        for idx in lines.indices {
            let transStr = translationLines[idx].content
            if !transStr.isEmpty, transStr != "//" {
                lines[idx].attachments[.translation()] = transStr
            }
        }
        self.lines = lines
        metadata.attachmentTags.insert(.translation())
    }
}
