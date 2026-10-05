import Foundation
import LyricsCore
import FoundationToolbox

public enum LyricsProviders {}

public protocol LyricsProvider: Sendable {
    func lyrics(for request: LyricsSearchRequest) -> AsyncThrowingStream<Lyrics, Error>
}

protocol _LyricsProvider: LyricsProvider {
    associatedtype LyricsToken

    static var service: String { get }

    func search(for request: LyricsSearchRequest) async throws -> [LyricsToken]

    func fetch(with token: LyricsToken) async throws -> Lyrics
}

@Loggable
enum LyricsProviderLog {
    static func fetchTaskFailed(_ error: any Error) {
        #log(.error, "A fetch task failed, skipping. Error: \(error)")
    }
}

extension _LyricsProvider {
    func lyrics(for request: LyricsSearchRequest) -> AsyncThrowingStream<Lyrics, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let tokens = try await self.search(for: request).prefix(request.limit)

                    // Child tasks so that cancelling the stream cancels in-flight
                    // fetches, and so one slow fetch can't hold back finished ones.
                    await withTaskGroup(of: Lyrics?.self) { taskGroup in
                        for token in tokens {
                            taskGroup.addTask {
                                do {
                                    let lrc = try await self.fetch(with: token)
                                    lrc.metadata.request = request
                                    lrc.metadata.service = Self.service
                                    return lrc
                                } catch {
                                    if !Task.isCancelled {
                                        LyricsProviderLog.fetchTaskFailed(error)
                                    }
                                    return nil
                                }
                            }
                        }
                        for await lyric in taskGroup {
                            if let lyric {
                                continuation.yield(lyric)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
