import Foundation

/// Detects connection and API availability errors in agent process output.
enum ConnectionChecker {

    private static let patterns = [
        "econnrefused", "enotfound", "etimedout", "econnreset",
        "fetch failed", "network error", "socket hang up",
        "connection refused", "getaddrinfo",
        "overloaded_error", "could not connect",
        "503 service unavailable", "502 bad gateway",
        "api connection error", "request timed out",
        "network is unreachable", "no route to host",
        "err_internet_disconnected",
    ]

    /// Returns `true` when the text contains patterns typical of network or API errors.
    static func isConnectionError(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return patterns.contains { lowered.contains($0) }
    }

    /// User-facing explanation shown when a connection error is detected.
    static let userMessage = "Connection error: Unable to reach the AI API. "
        + "This could be caused by no internet connection or the API being "
        + "temporarily unavailable. Please check your internet connection and try again."
}
