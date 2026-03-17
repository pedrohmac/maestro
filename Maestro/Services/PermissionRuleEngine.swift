import Foundation
import MaestroCore

struct PermissionRuleEngine {
    /// Evaluate permission rules against a tool invocation.
    /// Rules are evaluated in order; first match wins.
    /// Returns nil when no rule matches (needs user decision).
    static func evaluate(toolName: String, input: String, rules: [PermissionRule]) -> RuleAction? {
        let extractedPath = extractPath(from: input)

        for rule in rules {
            // Tool name matching: exact or wildcard
            guard rule.toolName == "*" || rule.toolName == toolName else {
                continue
            }

            // Path pattern matching (if rule specifies one)
            if let pattern = rule.pathPattern, !pattern.isEmpty {
                guard let path = extractedPath, globMatch(path: path, pattern: pattern) else {
                    continue
                }
            }

            return rule.action
        }

        return nil
    }

    /// Extract a file path or command from JSON input string.
    private static func extractPath(from input: String) -> String? {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // Try common field names: file_path, path, command
        if let filePath = json["file_path"] as? String { return filePath }
        if let path = json["path"] as? String { return path }
        if let command = json["command"] as? String { return command }
        return nil
    }

    /// Simple glob matching supporting * and ** patterns.
    static func globMatch(path: String, pattern: String) -> Bool {
        // Convert glob pattern to regex
        var regex = "^"
        var i = pattern.startIndex
        while i < pattern.endIndex {
            let c = pattern[i]
            if c == "*" {
                let next = pattern.index(after: i)
                if next < pattern.endIndex && pattern[next] == "*" {
                    // ** matches any path segments
                    regex += ".*"
                    i = pattern.index(after: next)
                    // Skip trailing slash after **
                    if i < pattern.endIndex && pattern[i] == "/" {
                        i = pattern.index(after: i)
                    }
                    continue
                } else {
                    // * matches anything except /
                    regex += "[^/]*"
                }
            } else if c == "?" {
                regex += "[^/]"
            } else if ".+^${}()|[]\\".contains(c) {
                regex += "\\\(c)"
            } else {
                regex += String(c)
            }
            i = pattern.index(after: i)
        }
        regex += "$"

        return (try? NSRegularExpression(pattern: regex))
            .map { $0.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil }
            ?? false
    }
}
