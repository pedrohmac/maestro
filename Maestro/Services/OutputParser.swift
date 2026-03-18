import Foundation
import MaestroCore

enum AgentEvent: Sendable, Codable {
    case assistantText(String)
    case toolUse(name: String, input: String)
    case toolResult(name: String, output: String)
    case result(sessionId: String?, costUSD: Double?, tokensUsed: Int?, durationMs: Int?)
    case error(String)
    case toolError(String)
    case systemMessage(String)
    case permissionRequest(toolName: String, input: String, requestId: String)
    case userMessage(String)
}

struct OutputParser {
    static func parse(line: String) -> AgentEvent? {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let type = json["type"] as? String ?? ""

        switch type {
        case "assistant":
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                // Extract tool_use blocks (text already streamed via content_block_delta)
                for block in content {
                    if (block["type"] as? String) == "tool_use" {
                        let name = block["name"] as? String ?? "unknown"
                        let input: String
                        if let inputDict = block["input"] as? [String: Any],
                           let inputData = try? JSONSerialization.data(withJSONObject: inputDict, options: [.prettyPrinted, .sortedKeys]) {
                            input = String(data: inputData, encoding: .utf8) ?? ""
                        } else {
                            input = ""
                        }
                        return .toolUse(name: name, input: input)
                    }
                }
            }
            // Also handle direct content text
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? String {
                return .assistantText(content)
            }
            return nil

        case "user":
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if (block["type"] as? String) == "tool_result" {
                        let isError = block["is_error"] as? Bool ?? false
                        let output: String
                        if let contentStr = block["content"] as? String {
                            output = contentStr
                        } else if let contentArr = block["content"] as? [[String: Any]] {
                            output = contentArr.compactMap { ($0["text"] as? String) }.joined(separator: "\n")
                        } else {
                            output = ""
                        }
                        if isError {
                            return .toolError(output)
                        }
                        if !output.isEmpty {
                            return .toolResult(name: "Tool", output: output)
                        }
                    }
                }
            }
            return nil

        case "content_block_start", "content_block_delta":
            if let contentBlock = json["content_block"] as? [String: Any] ?? (json["delta"] as? [String: Any]) {
                if let text = contentBlock["text"] as? String, !text.isEmpty {
                    return .assistantText(text)
                }
            }
            return nil

        case "tool_use":
            let name = json["name"] as? String ?? (json["tool"] as? String ?? "unknown")
            let input: String
            if let inputDict = json["input"] as? [String: Any],
               let inputData = try? JSONSerialization.data(withJSONObject: inputDict, options: .fragmentsAllowed) {
                input = String(data: inputData, encoding: .utf8) ?? ""
            } else {
                input = json["input"] as? String ?? ""
            }
            return .toolUse(name: name, input: input)

        case "tool_result":
            let name = json["name"] as? String ?? (json["tool"] as? String ?? "unknown")
            let output = json["output"] as? String ?? json["content"] as? String ?? ""
            return .toolResult(name: name, output: output)

        case "result":
            let sessionId = json["session_id"] as? String
            let costUSD = json["cost_usd"] as? Double ?? (json["total_cost_usd"] as? Double)
            var tokensUsed: Int? = nil
            if let usage = json["usage"] as? [String: Any] {
                let input = usage["input_tokens"] as? Int ?? 0
                let output = usage["output_tokens"] as? Int ?? 0
                tokensUsed = input + output
            }
            let durationMs = json["duration_ms"] as? Int
            return .result(sessionId: sessionId, costUSD: costUSD, tokensUsed: tokensUsed, durationMs: durationMs)

        case "error":
            let message = json["error"] as? String ?? json["message"] as? String ?? "Unknown error"
            return .error(message)

        case "stream_event":
            guard let event = json["event"] as? [String: Any],
                  let eventType = event["type"] as? String else { return nil }
            switch eventType {
            case "content_block_start":
                if let contentBlock = event["content_block"] as? [String: Any],
                   let text = contentBlock["text"] as? String, !text.isEmpty {
                    return .assistantText(text)
                }
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any],
                   let text = delta["text"] as? String, !text.isEmpty {
                    return .assistantText(text)
                }
            default:
                break
            }
            return nil

        case "system":
            let subtype = json["subtype"] as? String
            if subtype == "task_started" {
                let desc = json["description"] as? String ?? "Subagent started"
                return .systemMessage(desc)
            }
            if let message = json["message"] as? String, !message.isEmpty {
                return .systemMessage(message)
            }
            return nil

        case "permission_request":
            let toolName: String
            if let tool = json["tool"] as? [String: Any] {
                toolName = tool["name"] as? String ?? "unknown"
            } else {
                toolName = json["tool"] as? String ?? json["tool_name"] as? String ?? "unknown"
            }
            let input: String
            if let inputDict = json["input"] as? [String: Any],
               let inputData = try? JSONSerialization.data(withJSONObject: inputDict, options: [.prettyPrinted, .sortedKeys]) {
                input = String(data: inputData, encoding: .utf8) ?? ""
            } else if let tool = json["tool"] as? [String: Any],
                      let inputDict = tool["input"] as? [String: Any],
                      let inputData = try? JSONSerialization.data(withJSONObject: inputDict, options: [.prettyPrinted, .sortedKeys]) {
                input = String(data: inputData, encoding: .utf8) ?? ""
            } else {
                input = json["input"] as? String ?? ""
            }
            let requestId = json["permission_id"] as? String ?? json["id"] as? String ?? UUID().uuidString
            return .permissionRequest(toolName: toolName, input: input, requestId: requestId)

        default:
            // Try to extract any text content from unknown types
            if let message = json["message"] as? String {
                return .systemMessage("[\(type)] \(message)")
            }
            return nil
        }
    }
}
