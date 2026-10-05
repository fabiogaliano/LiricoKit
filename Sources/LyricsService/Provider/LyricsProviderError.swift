import Foundation

// Custom error type for more specific error handling
public enum LyricsProviderError: Error, LocalizedError {
    case invalidURL(urlString: String)
    case networkError(underlyingError: Error)
    case httpError(statusCode: Int)
    case decodingError(underlyingError: Error)
    case processingFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let urlString):
            return "The provided URL is invalid: \(urlString)"
        case .networkError(let underlyingError):
            return "A network error occurred: \(underlyingError.localizedDescription)"
        case .httpError(let statusCode):
            return "The server responded with HTTP status \(statusCode)."
        case .decodingError(let underlyingError):
            return "Failed to decode the server response: \(underlyingError.localizedDescription)"
        case .processingFailed(let reason):
            return "Failed to process the lyrics data: \(reason)"
        }
    }
}
