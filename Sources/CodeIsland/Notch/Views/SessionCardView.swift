import SwiftUI

struct SessionCardView: View {
    let session: Session
    var onDone: (() -> Void)? = nil

    private var isActive: Bool {
        session.status == .thinking || session.status == .toolUse
    }

    private var statusAccent: Color {
        switch session.status {
        case .thinking, .toolUse: return .cyan
        case .idle, .completed: return .green
        case .waitingPermission: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: mascot + title + effort + time
            HStack(spacing: 8) {
                SessionMascot(status: session.status, size: 18, provider: session.provider)
                Text(session.displayName)
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let effort = session.effortLevel {
                    EffortBadge(level: effort)
                }
                Spacer(minLength: 6)
                if let model = session.shortModelName {
                    Text(model)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                    Text("·")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                }
                Text(session.durationText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }

            // Row 2: prompt (on its own line for readability)
            if let prompt = session.firstPrompt ?? session.lastUserMessage {
                Text(prompt)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            // Row 3: status pill + terminal pill
            HStack(spacing: 7) {
                statusPill
                Spacer(minLength: 6)
                terminalPill
            }

            // Idle conversation sub-box
            if session.status == .idle, session.lastAssistantMessage != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let msg = session.lastUserMessage {
                        HStack(alignment: .top, spacing: 6) {
                            Text("YOU")
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .kerning(1.2)
                            Text(msg)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                    if let resp = session.lastAssistantMessage {
                        HStack(alignment: .top, spacing: 6) {
                            Text(session.provider.displayName.uppercased())
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundColor(session.provider.accentColor.opacity(0.85))
                                .kerning(1.2)
                            ScrollView {
                                Text(resp)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.85))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 70)
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                        )
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(statusAccent.opacity(isActive ? 0.05 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(statusAccent.opacity(isActive ? 0.35 : 0.15), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            TerminalJumper.jump(to: session)
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        HStack(spacing: 5) {
            statusIcon
            Text(statusText)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(statusAccent)
                .lineLimit(1)
            if isActive, let started = session.activeStartedAt {
                Text("·")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                // TimelineView ticks every 100ms so the elapsed time is live.
                TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                    Text(formatElapsed(ctx.date.timeIntervalSince(started)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(statusAccent.opacity(0.15))
        )
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        if seconds < 1.0 {
            return "\(Int(seconds * 1000))ms"
        }
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m)m \(s)s"
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch session.status {
        case .thinking, .toolUse:
            AnimatedSparkle(color: statusAccent)
        case .idle, .completed:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 10))
                .foregroundColor(statusAccent)
        case .waitingPermission:
            Image(systemName: "lock")
                .font(.system(size: 10))
                .foregroundColor(statusAccent)
        case .error:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundColor(statusAccent)
        }
    }

    private var statusText: String {
        switch session.status {
        case .toolUse:
            if let tool = session.currentTool { return "Using \(tool)" }
            return "Working..."
        case .thinking: return "Thinking..."
        case .idle, .completed: return "Idle"
        case .waitingPermission: return "Needs approval"
        case .error: return "Error"
        }
    }

    private var terminalPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "terminal")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.6))
            Text(session.detectedTerminalApp)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.75))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }
}

/// Pulsing/rotating sparkle used as the "thinking" indicator on the session card.
struct AnimatedSparkle: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: 10))
            .foregroundColor(color)
            .scaleEffect(pulse ? 1.25 : 0.85)
            .opacity(pulse ? 1.0 : 0.6)
            .rotationEffect(.degrees(pulse ? 18 : -18))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

struct BadgePill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.opacity(0.15))
            )
    }
}

struct EffortBadge: View {
    let level: String

    private var color: Color {
        switch level.lowercased() {
        case "low": return .green
        case "medium": return .yellow
        case "high": return .purple
        case "xhigh", "max": return .pink
        default: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(level.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(color)
                .kerning(0.5)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color.opacity(0.15))
        )
    }
}

private func formatDuration(_ ms: Int) -> String {
    if ms >= 1000 {
        return String(format: "%.1fs", Double(ms) / 1000.0)
    }
    return "\(ms)ms"
}
