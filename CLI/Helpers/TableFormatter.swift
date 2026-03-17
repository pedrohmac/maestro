import Foundation

enum TableFormatter {
    static func `print`(headers: [String], rows: [[String]]) {
        guard !rows.isEmpty else { return }

        let columnCount = headers.count
        var widths = headers.map { $0.count }

        for row in rows {
            for (i, cell) in row.enumerated() where i < columnCount {
                widths[i] = max(widths[i], cell.count)
            }
        }

        // Header
        let headerLine = headers.enumerated().map { i, h in
            h.padding(toLength: widths[i], withPad: " ", startingAt: 0)
        }.joined(separator: "  ")
        Swift.print(headerLine)

        // Separator
        let separator = widths.map { String(repeating: "-", count: $0) }.joined(separator: "  ")
        Swift.print(separator)

        // Rows
        for row in rows {
            let line = row.enumerated().map { i, cell in
                if i < columnCount {
                    return cell.padding(toLength: widths[i], withPad: " ", startingAt: 0)
                }
                return cell
            }.joined(separator: "  ")
            Swift.print(line)
        }
    }
}

enum JSONFormatter {
    static func format(_ dict: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func format(_ array: [[String: String]]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: array,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func formatAny(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
