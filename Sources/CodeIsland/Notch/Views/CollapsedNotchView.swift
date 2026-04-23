import SwiftUI

struct CollapsedNotchView: View {
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var rateLimitStore: RateLimitStore

    var body: some View {
        HStack {
            if !sessionStore.activeSessions.isEmpty {
                // Left: mascot
                if let latest = sessionStore.activeSessions.values
                    .sorted(by: { $0.startedAt > $1.startedAt }).first {
                    SessionMascot(status: latest.status, size: 1.5)
                }

                Spacer()

                // Right: dot + count
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text("\(sessionStore.activeSessions.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusColor: Color {
        if sessionStore.activeSessions.isEmpty {
            return .gray
        }
        if sessionStore.activeSessions.values.contains(where: { $0.pendingPermission != nil }) {
            return .orange
        }
        if sessionStore.activeSessions.values.contains(where: { $0.status == .thinking }) {
            return .cyan
        }
        return .green
    }

    private var sessionIcon: String {
        if sessionStore.activeSessions.values.contains(where: { $0.pendingPermission != nil }) {
            return "hand.raised.fill"
        }
        if sessionStore.activeSessions.values.contains(where: { $0.status == .thinking }) {
            return "brain"
        }
        return "terminal.fill"
    }

    private var statusText: String {
        let count = sessionStore.activeSessions.count
        if sessionStore.activeSessions.values.contains(where: { $0.pendingPermission != nil }) {
            return "Approval needed"
        }
        if count == 1, let session = sessionStore.activeSessions.values.first {
            return session.status.displayText
        }
        return "\(count) sessions"
    }
}
