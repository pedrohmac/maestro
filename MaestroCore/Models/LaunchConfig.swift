import Foundation

public struct LaunchStep: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var command: String
    public var workingDirectory: String?
    public var background: Bool
    public var waitSeconds: Int?

    public init(
        id: String = UUID().uuidString,
        name: String,
        command: String,
        workingDirectory: String? = nil,
        background: Bool = false,
        waitSeconds: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.workingDirectory = workingDirectory
        self.background = background
        self.waitSeconds = waitSeconds
    }
}

public struct LaunchConfig: Codable, Equatable {
    public var steps: [LaunchStep]
    public var openUrl: String?
    public var readyCheckUrl: String?
    public var readyCheckTimeoutSeconds: Int?

    public init(
        steps: [LaunchStep] = [],
        openUrl: String? = nil,
        readyCheckUrl: String? = nil,
        readyCheckTimeoutSeconds: Int? = nil
    ) {
        self.steps = steps
        self.openUrl = openUrl
        self.readyCheckUrl = readyCheckUrl
        self.readyCheckTimeoutSeconds = readyCheckTimeoutSeconds
    }

    public static let configPath = ".maestro/launch.json"

    public static func load(from workspaceRoot: String) -> LaunchConfig? {
        let path = "\(workspaceRoot)/\(configPath)"
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        return try? JSONDecoder().decode(LaunchConfig.self, from: data)
    }

    public func save(to workspaceRoot: String) throws {
        let dirPath = "\(workspaceRoot)/.maestro"
        try FileManager.default.createDirectory(
            atPath: dirPath,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        let filePath = "\(workspaceRoot)/\(LaunchConfig.configPath)"
        try data.write(to: URL(fileURLWithPath: filePath))
    }
}
