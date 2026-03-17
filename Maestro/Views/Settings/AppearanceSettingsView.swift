import SwiftUI

// MARK: - Darker Mode Environment Key

private struct IsDarkerModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isDarkerMode: Bool {
        get { self[IsDarkerModeKey.self] }
        set { self[IsDarkerModeKey.self] = newValue }
    }
}

// MARK: - Darker Color Helpers

extension Color {
    /// Window background: true black in darker mode, standard in dark mode.
    static func windowBackground(darker: Bool) -> Color {
        darker ? Color(nsColor: NSColor(srgbRed: 0.02, green: 0.02, blue: 0.02, alpha: 1))
               : Color(nsColor: .windowBackgroundColor)
    }

    /// Control/card background: very dark gray in darker mode, standard in dark mode.
    static func controlBackground(darker: Bool) -> Color {
        darker ? Color(nsColor: NSColor(srgbRed: 0.07, green: 0.07, blue: 0.07, alpha: 1))
               : Color(nsColor: .controlBackgroundColor)
    }

    /// Text area background: pure black in darker mode, standard in dark mode.
    static func textBackground(darker: Bool) -> Color {
        darker ? Color(nsColor: NSColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 1))
               : Color(nsColor: .textBackgroundColor)
    }
}

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    case darker = "darker"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        case .darker: "Darker"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        case .darker: "moon.stars.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark, .darker: .dark
        }
    }

    var isDarker: Bool {
        self == .darker
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue

    private var selectedMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceMode) ?? .system
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Mode", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.inline)

                Text("Choose how Maestro looks. \"System\" follows your macOS appearance setting. \"Darker\" uses deeper blacks for reduced light emission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
