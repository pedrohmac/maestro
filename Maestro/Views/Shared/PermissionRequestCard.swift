import SwiftUI

struct PermissionRequestCard: View {
    let permission: PendingPermission
    var onAllow: () -> Void
    var onDeny: () -> Void
    @Environment(\.isDarkerMode) private var isDarkerMode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(permission.toolName)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Spacer()
                Text(permission.receivedAt.relativeFormatted)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !permission.input.isEmpty {
                Text(permission.input)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            }

            HStack(spacing: 8) {
                Button(action: onAllow) {
                    Label("Allow", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .controlSize(.small)

                Button(action: onDeny) {
                    Label("Deny", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}
