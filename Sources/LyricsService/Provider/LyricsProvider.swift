import Foundation
import LyricsCore
import os

public enum LyricsProviders {}

public protocol LyricsProvider: Sendable {
    func lyrics(for request: LyricsSearchRequest) -> AsyncThrowingStream<Lyrics, Error>
}

protocol _LyricsProvider: LyricsProvider {
    associatedtype LyricsToken: Sendable

    static var service: String { get }

    func search(for request: LyricsSearchRequest) async throws -> [LyricsToken]

    func fetch(with token: LyricsToken) async throws -> Lyrics
}

extension _LyricsProvider {
    func lyrics(for request: LyricsSearchRequest) -> AsyncThrowingStream<Lyrics, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let tokens = try await self.search(for: request).prefix(request.limit)

                    // Child tasks so that cancelling the stream cancels in-flight
                    // fetches, and so one slow fetch can't hold back finished ones.
                    let unreachable = await withTaskGroup(of: Result<Lyrics, Error>.self) { taskGroup -> Error? in
                        for token in tokens {
                            taskGroup.addTask {
                                do {
                                    let lrc = try await self.fetch(with: token)
                                    lrc.metadata.request = request
                                    lrc.metadata.service = Self.service
                                    return .success(lrc)
                                } catch {
                                    return .failure(error)
                                }
                            }
                        }

                        // A fetch that finds no lyrics still got an answer. Callers show
                        // "not found" and "failed" differently, so only fail the stream
                        // when no fetch reached the service at all.
                        var serviceAnswered = false
                        var transportFailure: Error?
                        for await result in taskGroup {
                            switch result {
                            case .success(let lyric):
                                serviceAnswered = true
                                continuation.yield(lyric)
                            case .failure(let error):
                                if !Task.isCancelled {
                                    Logger.liricoKit(category: Self.service)
                                        .error("A fetch task failed, skipping. Error: \(error)")
                                }
                                if error.isTransportFailure {
                                    transportFailure = transportFailure ?? error
                                } else {
                                    serviceAnswered = true
                                }
                            }
                        }
                        return serviceAnswered ? nil : transportFailure
                    }
                    if let unreachable {
                        throw unreachable
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

extension Error {
    fileprivate var isTransportFailure: Bool {
        switch self as? LyricsProviderError {
        case .networkError?, .httpError?:
            return true
        default:
            return false
        }
    }
}
