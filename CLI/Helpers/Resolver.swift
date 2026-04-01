import Foundation
import MaestroCore
import SwiftData

enum ResolverError: LocalizedError {
    case projectNotFound(String)
    case ambiguousProject(String, [String])
    case taskNotFound(String)
    case ambiguousTask(String, [String])
    case runNotFound(String)
    case ambiguousRun(String, [String])

    var errorDescription: String? {
        switch self {
        case .projectNotFound(let query):
            return "No project found matching '\(query)'"
        case .ambiguousProject(let query, let candidates):
            return "Multiple projects match '\(query)':\n" +
                candidates.map { "  - \($0)" }.joined(separator: "\n")
        case .taskNotFound(let query):
            return "No task found matching '\(query)'"
        case .ambiguousTask(let query, let candidates):
            return "Multiple tasks match '\(query)':\n" +
                candidates.map { "  - \($0)" }.joined(separator: "\n")
        case .runNotFound(let query):
            return "No agent run found matching '\(query)'"
        case .ambiguousRun(let query, let candidates):
            return "Multiple runs match '\(query)':\n" +
                candidates.map { "  - \($0)" }.joined(separator: "\n")
        }
    }
}

enum Resolver {
    // MARK: - Project Resolution

    static func resolveProject(_ query: String, in context: ModelContext) throws -> Project {
        let descriptor = FetchDescriptor<Project>()
        let projects = try context.fetch(descriptor)

        // 1. Exact ID match
        if let match = projects.first(where: { $0.id == query }) {
            return match
        }

        // 2. ID prefix match
        let idPrefixMatches = projects.filter { $0.id.hasPrefix(query) }
        if idPrefixMatches.count == 1 {
            return idPrefixMatches[0]
        }
        if idPrefixMatches.count > 1 {
            let candidates = idPrefixMatches.map { "\($0.name) (\($0.id.prefix(8)))" }
            throw ResolverError.ambiguousProject(query, candidates)
        }

        // 3. Exact name match (case-insensitive)
        let nameExact = projects.filter { $0.name.lowercased() == query.lowercased() }
        if nameExact.count == 1 {
            return nameExact[0]
        }
        if nameExact.count > 1 {
            let candidates = nameExact.map { "\($0.name) (\($0.id.prefix(8)))" }
            throw ResolverError.ambiguousProject(query, candidates)
        }

        // 4. Prefix name match (case-insensitive)
        let namePrefix = projects.filter { $0.name.lowercased().hasPrefix(query.lowercased()) }
        if namePrefix.count == 1 {
            return namePrefix[0]
        }
        if namePrefix.count > 1 {
            let candidates = namePrefix.map { "\($0.name) (\($0.id.prefix(8)))" }
            throw ResolverError.ambiguousProject(query, candidates)
        }

        // 5. Substring name match (case-insensitive)
        let nameContains = projects.filter { $0.name.lowercased().contains(query.lowercased()) }
        if nameContains.count == 1 {
            return nameContains[0]
        }
        if nameContains.count > 1 {
            let candidates = nameContains.map { "\($0.name) (\($0.id.prefix(8)))" }
            throw ResolverError.ambiguousProject(query, candidates)
        }

        throw ResolverError.projectNotFound(query)
    }

    // MARK: - Task Resolution

    static func resolveTask(_ query: String, in context: ModelContext) throws -> ProjectTask {
        let descriptor = FetchDescriptor<ProjectTask>()
        let tasks = try context.fetch(descriptor)

        // 0. Ticket number match (#N or just a number)
        let ticketQuery = query.hasPrefix("#") ? String(query.dropFirst()) : nil
        if let numStr = ticketQuery, let num = Int(numStr) {
            let ticketMatches = tasks.filter { $0.ticketNumber == num }
            if ticketMatches.count == 1 {
                return ticketMatches[0]
            }
            if ticketMatches.count > 1 {
                let candidates = ticketMatches.map { "\($0.ticketDisplay) \($0.title) [\($0.project?.name ?? "?")] (\($0.id.prefix(8)))" }
                throw ResolverError.ambiguousTask(query, candidates)
            }
        }

        // 1. Exact ID match
        if let match = tasks.first(where: { $0.id == query }) {
            return match
        }

        // 2. ID prefix match
        let idPrefixMatches = tasks.filter { $0.id.hasPrefix(query) }
        if idPrefixMatches.count == 1 {
            return idPrefixMatches[0]
        }
        if idPrefixMatches.count > 1 {
            let candidates = idPrefixMatches.map { "\($0.ticketDisplay) \($0.title) (\($0.id.prefix(8)))" }
            throw ResolverError.ambiguousTask(query, candidates)
        }

        throw ResolverError.taskNotFound(query)
    }

    // MARK: - Run Resolution

    static func resolveRun(_ query: String, in context: ModelContext) throws -> AgentRun {
        let descriptor = FetchDescriptor<AgentRun>()
        let runs = try context.fetch(descriptor)

        // 1. Exact ID match
        if let match = runs.first(where: { $0.id == query }) {
            return match
        }

        // 2. ID prefix match
        let idPrefixMatches = runs.filter { $0.id.hasPrefix(query) }
        if idPrefixMatches.count == 1 {
            return idPrefixMatches[0]
        }
        if idPrefixMatches.count > 1 {
            let candidates = idPrefixMatches.map { "\($0.taskTitle) (\($0.id.prefix(8)))" }
            throw ResolverError.ambiguousRun(query, candidates)
        }

        throw ResolverError.runNotFound(query)
    }
}
