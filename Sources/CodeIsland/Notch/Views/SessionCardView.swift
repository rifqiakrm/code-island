import SwiftUI

struct SessionCardView: View {
    @Environment(\.notchTheme) private var theme
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

    /// The colour the card itself is tinted with. Most themes use the status
    /// colour; Pixel/Brutalist override the normal thinking/idle states with
    /// fixed mockup hues (terracotta / sky) but keep error + waiting semantic.
    private var cardTint: Color {
        switch session.status {
        case .thinking, .toolUse: return theme.cardHueActive ?? statusAccent
        case .idle, .completed:   return theme.cardHueIdle ?? statusAccent
        case .waitingPermission, .error: return statusAccent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: mascot + title + effort + time
            HStack(spacing: 8) {
                SessionMascot(status: session.status, size: 18, provider: session.provider)
                Text(session.displayName)
                    .font(theme.font(size: 13, weight: .heavy))
                    .foregroundColor(theme.cardForeground)
                    .lineLimit(1)
                if let profile = session.profile {
                    Text(profile)
                        .font(theme.font(size: 8, weight: .heavy))
                        .tracking(0.5)
                        .foregroundColor(session.provider.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(session.provider.accentColor.opacity(0.16))
                        )
                }
                if let effort = session.effortLevel {
                    EffortBadge(level: effort)
                }
                Spacer(minLength: 6)
                if let model = session.shortModelName {
                    Text(model)
                        .font(theme.font(size: 9))
                        .foregroundColor(theme.cardForeground.opacity(0.55))
                    Text("·")
                        .font(theme.font(size: 9))
                        .foregroundColor(theme.cardForeground.opacity(0.25))
                }
                Text(session.durationText)
                    .font(theme.font(size: 9))
                    .foregroundColor(theme.cardForeground.opacity(0.45))
            }

            // Row 2: prompt (on its own line for readability)
            // Show the latest user prompt — `firstPrompt` was sticky for
            // the entire session and stayed stale after the user sent more.
            if let prompt = session.lastUserMessage ?? session.firstPrompt {
                Text(prompt)
                    .font(theme.font(size: 11))
                    .foregroundColor(theme.cardForeground.opacity(0.7))
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
                                .font(theme.font(size: 9, weight: .heavy))
                                .foregroundColor(.white.opacity(0.5))
                                .kerning(1.2)
                            Text(msg)
                                .font(theme.font(size: 11))
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                    if let resp = session.lastAssistantMessage {
                        HStack(alignment: .top, spacing: 6) {
                            Text(session.provider.displayName.uppercased())
                                .font(theme.font(size: 9, weight: .heavy))
                                .foregroundColor(session.provider.accentColor.opacity(0.85))
                                .kerning(1.2)
                            ScrollView {
                                Text(resp)
                                    .font(theme.font(size: 11))
                                    .foregroundColor(.white.opacity(0.85))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 70)
                        }
                    }
                }
                .padding(10)
                // On light-card themes the inset well goes dark so its white
                // conversation text stays legible; otherwise it's the theme box.
                .background(
                    RoundedRectangle(cornerRadius: theme.boxRadius, style: .continuous)
                        .fill(theme.lightCards ? Color.black.opacity(0.82) : theme.boxFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.boxRadius, style: .continuous)
                                .strokeBorder(theme.lightCards ? Color.black : theme.boxStroke,
                                              lineWidth: theme.strokeWidth)
                        )
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .notchCard(theme, tint: cardTint, active: isActive)
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
                .font(theme.font(size: 10, weight: .bold))
                .foregroundColor(statusAccent)
                .lineLimit(1)
            if isActive, let started = session.activeStartedAt {
                Text("·")
                    .font(theme.font(size: 10))
                    .foregroundColor(.white.opacity(0.3))
                // TimelineView ticks every 100ms so the elapsed time is live.
                // Tick once a second: the elapsed display reads in whole seconds
                // at a glance, so 10Hz just repainted the transparent window for
                // nothing (× every thinking card).
                TimelineView(.periodic(from: .now, by: 1.0)) { ctx in
                    Text(formatElapsed(ctx.date.timeIntervalSince(started)))
                        .font(theme.font(size: 10))
                        .foregroundColor(.white.opacity(0.55))
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .notchPill(theme, fill: theme.chipFill(statusAccent.opacity(0.15)))
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
                .font(theme.font(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .notchPill(theme, fill: theme.chipFill(.white.opacity(0.06)), base: 4)
    }
}

/// One shared ~6Hz tick drives every "thinking" sparkle in lockstep. A
/// `repeatForever` animation interpolates at the display's 60–120Hz and a
/// transparent overlay recomposites its whole area on each frame — so N pulsing
/// cards used to mean N×120 full-window repaints/sec. Stepping discretely (and
/// in sync) cuts that to ~6 repaints/sec total, regardless of card count.
private let sparklePulseClock = Timer.publish(every: 0.16, on: .main, in: .common).autoconnect()

/// Pulsing/rotating sparkle used as the "thinking" indicator on the session card.
struct AnimatedSparkle: View {
    let color: Color
    @State private var phase = 0

    // Same extremes as the old smooth pulse (0.85↔1.25, 0.6↔1.0, ±18°), but as
    // 4 discrete frames — matches the pixel-art mascots' stepped motion.
    private static let scales: [CGFloat] = [0.85, 1.05, 1.25, 1.05]
    private static let opacities: [Double] = [0.6, 0.8, 1.0, 0.8]
    private static let angles: [Double] = [-18, 0, 18, 0]

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: 10))
            .foregroundColor(color)
            .scaleEffect(Self.scales[phase])
            .opacity(Self.opacities[phase])
            .rotationEffect(.degrees(Self.angles[phase]))
            .onReceive(sparklePulseClock) { _ in
                phase = (phase + 1) % 4
            }
    }
}

struct BadgePill: View {
    @Environment(\.notchTheme) private var theme
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(theme.font(size: 9, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .notchPill(theme, fill: theme.chipFill(color.opacity(0.15)), base: 4)
    }
}

struct EffortBadge: View {
    @Environment(\.notchTheme) private var theme
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
                .font(theme.font(size: 9, weight: .heavy))
                .foregroundColor(color)
                .kerning(0.5)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .notchPill(theme, fill: theme.chipFill(color.opacity(0.15)), base: 4)
    }
}

private func formatDuration(_ ms: Int) -> String {
    if ms >= 1000 {
        return String(format: "%.1fs", Double(ms) / 1000.0)
    }
    return "\(ms)ms"
}
