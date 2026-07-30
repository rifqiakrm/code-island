import SwiftUI
import AppKit
import ConfettiSwiftUI

// MARK: - Full-screen onboarding

struct OnboardingView: View {
    @ObservedObject var settingsStore: SettingsStore
    let onComplete: () -> Void

    @State private var step = 0
    @State private var confetti = 0
    @State private var reverse = false   // drives slide direction (back vs forward)
    private let totalSteps = 4

    /// The live theme — the faux notch + theme chips reflect it, and the theme
    /// step mutates it (it's the real, persisted `notchThemeID`).
    private var theme: NotchTheme { settingsStore.notchThemeID.theme }
    private let accent = Color(red: 1.0, green: 0.541, blue: 0.40)   // #ff8a66

    var body: some View {
        ZStack {
            // Cosmic gradient + twinkling starfield — matches the website.
            CosmicBackground()

            VStack(spacing: 0) {
                fauxNotch                       // flush to the top → merges with the real notch
                Spacer(minLength: 24)
                stepContent
                    .frame(maxWidth: 680)
                    .padding(.horizontal, 40)
                    .transition(.asymmetric(
                        insertion: .move(edge: reverse ? .leading : .trailing).combined(with: .opacity),
                        removal: .move(edge: reverse ? .trailing : .leading).combined(with: .opacity)
                    ))
                    .id(step)
                Spacer()
                progressDots
                    .padding(.bottom, 40)
            }
            // Let the faux notch reach the very top edge so it merges with the
            // hardware notch instead of floating below the safe-area inset.
            .ignoresSafeArea(edges: .top)

            ConfettiCannon(counter: $confetti, num: 90, radius: 540)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.notchTheme, theme)
        .overlay(alignment: .topTrailing) {
            if step < totalSteps - 1 {
                Button(action: complete) {
                    Text("Skip")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .padding(.trailing, 20)
            }
        }
        .overlay(alignment: .topLeading) {
            if step > 0 {
                Button(action: goBack) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .padding(.leading, 20)
            }
        }
    }

    // MARK: - Faux notch (the live, themed demo island)

    private var fauxNotch: some View {
        let glow = (theme.cardHueActive ?? .cyan).opacity(0.20)
        return ZStack {
            Ellipse()
                .fill(glow)
                .frame(width: 560, height: 130)
                .blur(radius: 80)
                .offset(y: 10)

            ZStack(alignment: .top) {
                NotchBackground(theme: theme, isExpanded: true, cornerRadius: 22)
                fauxNotchCard
                    .padding(.horizontal, 16)
                    .padding(.top, 46)      // clear the hardware notch occlusion
                    .padding(.bottom, 14)
            }
            .frame(width: 600, height: 128)
            .clipShape(NotchShape(cornerRadius: 22))
        }
        .frame(height: 128)
    }

    /// A themed mock session card — mirrors what `SessionCardView` would render,
    /// so it's an accurate live preview of the chosen theme.
    private var fauxNotchCard: some View {
        let tint = theme.cardHueActive ?? .cyan
        return HStack(spacing: 10) {
            SessionMascot(status: .thinking, size: 26, provider: .claude)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("code-island")
                        .font(theme.font(size: 13, weight: .heavy))
                        .foregroundColor(theme.cardForeground)
                    HStack(spacing: 5) {
                        Circle().fill(Color.cyan).frame(width: 5, height: 5)
                        Text("thinking")
                            .font(theme.font(size: 10, weight: .bold))
                            .foregroundColor(.cyan)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .notchPill(theme, fill: theme.chipFill(.cyan.opacity(0.15)))
                    Spacer(minLength: 0)
                }
                Text("fix the notch resize bug on resolution change…")
                    .font(theme.font(size: 11))
                    .foregroundColor(theme.cardForeground.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchCard(theme, tint: tint, active: true)
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcomeStep
        case 1: hooksStep
        case 2: themeStep
        default: readyStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            title("Welcome to Code Island")
            subtitle("Your MacBook's notch is now mission control for your AI coding agents — Claude Code, Codex, Gemini, Cursor, and more. Approve permissions, answer questions, and track usage without leaving your editor.")
            primaryButton("Get Started", action: advance)
        }
    }

    private var hooksStep: some View {
        VStack(spacing: 20) {
            title("Wired up automatically")
            subtitle("Code Island installed its hooks for every agent it detected. It's now listening for:")
            VStack(alignment: .leading, spacing: 10) {
                hookRow("SessionStart / SessionEnd", "Track each session's lifecycle")
                hookRow("PreToolUse / PostToolUse", "Follow tool execution live")
                hookRow("PermissionRequest", "Approve or deny from the notch")
                hookRow("Notification / Stop", "Status + finished-reply updates")
            }
            .padding(18)
            .frame(maxWidth: 460)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    )
            )
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundColor(.cyan)
                Text("Auto-detects every agent you have installed")
            }
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.6))
            providerStrip
            primaryButton("Continue", action: advance)
        }
    }

    /// Every supported agent's mascot — communicates the breadth of provider
    /// support at a glance. Fixed rows of 6, each centered, so the final
    /// partial row sits in the middle rather than left-aligned.
    private var providerStrip: some View {
        let cols = 6
        let rows = stride(from: 0, to: AIProvider.all.count, by: cols).map {
            Array(AIProvider.all[$0 ..< min($0 + cols, AIProvider.all.count)])
        }
        return VStack(spacing: 12) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    ForEach(rows[i]) { p in providerCell(p) }
                }
            }
        }
        .frame(maxWidth: 470)
    }

    private func providerCell(_ p: AIProvider) -> some View {
        VStack(spacing: 4) {
            SessionMascot(status: .idle, size: 22, animated: false, provider: p)
                .frame(height: 24)
            Text(p.displayName)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
        }
        .frame(width: 64)
    }

    private var themeStep: some View {
        VStack(spacing: 22) {
            title("Pick your look")
            subtitle("Restyle the notch windows — the island above updates live. You can change this anytime in Settings → Appearance.")
            HStack(spacing: 14) {
                ForEach(NotchThemeID.allCases) { id in
                    themeChip(id)
                }
            }
            primaryButton("Continue", action: advance)
        }
    }

    private var readyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(.green)
            title("You're all set!")
            subtitle("Start any of your coding agents and watch the notch come alive.")
            Toggle(isOn: $settingsStore.launchAtLogin) {
                HStack(spacing: 8) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    Text("Launch at startup")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .toggleStyle(.switch)
            .tint(.green)
            .fixedSize()
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    )
            )
            primaryButton("Start Using Code Island", action: complete)
        }
    }

    // MARK: - Theme chip

    private func themeChip(_ id: NotchThemeID) -> some View {
        let t = id.theme
        let selected = settingsStore.notchThemeID == id
        return Button {
            withAnimation(.easeOut(duration: 0.22)) { settingsStore.notchThemeID = id }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    NotchBackground(theme: t, isExpanded: true, cornerRadius: 9)
                    HStack(spacing: 5) {
                        SessionMascot(status: .thinking, size: 15, provider: .claude)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(t.cardForeground.opacity(0.45))
                            .frame(width: 30, height: 5)
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .notchCard(t, tint: t.cardHueActive ?? .cyan, active: true)
                    .padding(8)
                }
                .frame(width: 108, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(selected ? Color.cyan : Color.white.opacity(0.12),
                                      lineWidth: selected ? 2 : 1)
                )
                Text(id.displayName)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? .white : .white.opacity(0.55))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Building blocks

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 38, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
    }

    private func subtitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundColor(.white.opacity(0.65))
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func hookRow(_ name: String, _ desc: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.cyan)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
    }

    private func primaryButton(_ titleText: String, action: @escaping () -> Void) -> some View {
        Button(titleText, action: action)
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 4)
    }

    private var progressDots: some View {
        HStack(spacing: 9) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i == step ? accent : Color.white.opacity(0.2))
                    .frame(width: i == step ? 22 : 7, height: 7)
                    .animation(.easeOut(duration: 0.2), value: step)
            }
        }
    }

    // MARK: - Flow

    private func advance() {
        reverse = false
        withAnimation(.easeInOut(duration: 0.3)) {
            step = min(step + 1, totalSteps - 1)
        }
        if step == totalSteps - 1 {
            confetti += 1
        }
    }

    private func goBack() {
        reverse = true
        withAnimation(.easeInOut(duration: 0.3)) {
            step = max(step - 1, 0)
        }
    }

    private func complete() {
        settingsStore.hasCompletedOnboarding = true
        settingsStore.hasSeenThemeOnboarding = true
        onComplete()
    }
}

// MARK: - Cosmic background (ported from the website)

private struct CosmicBackground: View {
    @State private var twinkle = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.051, green: 0.031, blue: 0.125),   // #0d0820
                    Color(red: 0.027, green: 0.016, blue: 0.102),   // #07041a
                    Color(red: 0.020, green: 0.012, blue: 0.063),   // #050310
                ],
                startPoint: .top, endPoint: .bottom
            )
            // Soft colored nebula glows.
            glow(Color(red: 0.616, green: 0.424, blue: 1.0),  opacity: 0.20, at: UnitPoint(x: 0.5, y: 0.0),  radius: 0.78) // purple
            glow(Color(red: 0.424, green: 0.949, blue: 0.753), opacity: 0.10, at: UnitPoint(x: 0.9, y: 0.28), radius: 0.50) // teal
            glow(Color(red: 1.0,   green: 0.541, blue: 0.40),  opacity: 0.12, at: UnitPoint(x: 0.1, y: 0.6),  radius: 0.50) // peach
            glow(Color(red: 0.373, green: 0.478, blue: 0.863), opacity: 0.14, at: UnitPoint(x: 0.5, y: 1.0),  radius: 0.72) // blue
            Starfield()
                .opacity(twinkle ? 0.95 : 0.55)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                twinkle = true
            }
        }
    }

    private func glow(_ color: Color, opacity: Double, at center: UnitPoint, radius: CGFloat) -> some View {
        GeometryReader { geo in
            RadialGradient(
                gradient: Gradient(colors: [color.opacity(opacity), .clear]),
                center: center,
                startRadius: 0,
                endRadius: max(geo.size.width, geo.size.height) * radius
            )
        }
    }
}

private struct Starfield: View {
    private struct Star { let x: CGFloat; let y: CGFloat; let r: CGFloat; let color: Color }

    private static let w = Color.white
    private static let purple = Color(red: 0.76, green: 0.66, blue: 1.0)   // #c2a8ff
    private static let peach  = Color(red: 1.0,  green: 0.70, blue: 0.60)  // #ffb39a
    private static let teal   = Color(red: 0.50, green: 1.0,  blue: 0.83)  // #7fffd4
    private static let lilac  = Color(red: 0.85, green: 0.72, blue: 1.0)   // #d9b8ff
    private static let sand   = Color(red: 1.0,  green: 0.82, blue: 0.72)  // #ffd0b8

    private static let stars: [Star] = [
        Star(x: 0.12, y: 0.18, r: 1.5, color: purple), Star(x: 0.27, y: 0.65, r: 1, color: peach),
        Star(x: 0.38, y: 0.12, r: 1, color: w),        Star(x: 0.52, y: 0.78, r: 2, color: teal),
        Star(x: 0.64, y: 0.22, r: 1, color: w),        Star(x: 0.78, y: 0.55, r: 1.5, color: lilac),
        Star(x: 0.86, y: 0.14, r: 1, color: sand),     Star(x: 0.18, y: 0.88, r: 1.5, color: w),
        Star(x: 0.71, y: 0.92, r: 1, color: purple),   Star(x: 0.93, y: 0.78, r: 1, color: w),
        Star(x: 0.05, y: 0.42, r: 1, color: w),        Star(x: 0.44, y: 0.38, r: 2, color: peach),
        Star(x: 0.60, y: 0.50, r: 1, color: w),        Star(x: 0.08, y: 0.30, r: 1, color: w),
        Star(x: 0.33, y: 0.85, r: 1, color: purple),   Star(x: 0.48, y: 0.08, r: 1.5, color: w),
        Star(x: 0.55, y: 0.33, r: 1, color: teal),     Star(x: 0.68, y: 0.70, r: 1, color: w),
        Star(x: 0.82, y: 0.40, r: 1.5, color: peach),  Star(x: 0.90, y: 0.60, r: 1, color: w),
        Star(x: 0.22, y: 0.50, r: 1, color: w),        Star(x: 0.15, y: 0.72, r: 1, color: sand),
        Star(x: 0.40, y: 0.62, r: 1, color: w),        Star(x: 0.75, y: 0.16, r: 1, color: lilac),
        Star(x: 0.96, y: 0.32, r: 1, color: w),        Star(x: 0.30, y: 0.28, r: 1, color: w),
        Star(x: 0.58, y: 0.90, r: 1.5, color: purple), Star(x: 0.03, y: 0.86, r: 1, color: w),
    ]

    var body: some View {
        Canvas { context, size in
            for star in Self.stars {
                let d = star.r * 2
                let rect = CGRect(x: star.x * size.width - star.r,
                                  y: star.y * size.height - star.r,
                                  width: d, height: d)
                context.fill(Path(ellipseIn: rect), with: .color(star.color))
            }
        }
    }
}

// MARK: - Buttons

/// Refined primary CTA — terracotta gradient, rounded rect, soft glow, press feedback.
private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(Color(red: 0.10, green: 0.04, blue: 0.02))
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.541, blue: 0.40),
                                     Color(red: 1.0, green: 0.627, blue: 0.502)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: Color(red: 1.0, green: 0.541, blue: 0.40).opacity(0.38),
                    radius: configuration.isPressed ? 10 : 22,
                    y: configuration.isPressed ? 4 : 9)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - Window

/// Borderless windows reject key status by default; we need it so the
/// launch-at-login toggle and buttons are interactive.
private final class OnboardingPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class OnboardingWindowController: NSWindowController {
    init(settingsStore: SettingsStore, onComplete: @escaping () -> Void) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let window = OnboardingPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Above the menu bar (25) and the app's own notch panel (27) so first
        // run is a true full-screen takeover.
        window.level = NSWindow.Level(rawValue: 101)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = false
        window.setFrame(frame, display: false)

        // Frost + dim the desktop behind the window.
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]

        let view = OnboardingView(settingsStore: settingsStore, onComplete: {
            window.orderOut(nil)
            window.close()
            onComplete()
        })
        let host = NSHostingView(rootView: view)
        host.frame = blur.bounds
        host.autoresizingMask = [.width, .height]
        blur.addSubview(host)

        window.contentView = blur

        super.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}

// MARK: - What's New

/// A compact, centered card shown once per version bump — highlights + the
/// full cast of mascots bouncing along the top. Reuses the onboarding chrome
/// (cosmic background, starfield, primary button).
struct WhatsNewView: View {
    let version: String
    let onClose: () -> Void

    private static let accent = Color(red: 1.0, green: 0.541, blue: 0.40)

    private struct Highlight: Identifiable {
        let id = UUID()
        let symbol: String
        let tint: Color
        let title: String
        let detail: String
    }

    private let highlights: [Highlight] = [
        .init(symbol: "circle.hexagongrid.fill", tint: Color(red: 0.902, green: 0.141, blue: 0.161),
              title: "New theme: Web-Slinger",
              detail: "Midnight and suit red, webbing spun into the corners, and a masked spider that abseils in on a thread — Settings → Appearance."),
        .init(symbol: "sparkles", tint: Color(red: 0.62, green: 0.42, blue: 1.0),
              title: "17 coding agents, one notch",
              detail: "Claude, Codex, Gemini, Cursor, Copilot, Kiro, Pi, Qwen, Qoder, Factory, CodeBuddy, Kimi, OpenCode, Cline & more — side by side."),
        .init(symbol: "face.smiling", tint: Color(red: 0.42, green: 0.95, blue: 0.75),
              title: "A mascot for everyone",
              detail: "Every agent gets its own animated pixel mascot and logo, themed to its brand."),
        .init(symbol: "bell.badge", tint: Color(red: 1.0, green: 0.72, blue: 0.30),
              title: "Smart, per-agent permissions",
              detail: "Approve, deny, or answer questions right in the notch — with the buttons each tool actually supports."),
        .init(symbol: "lock.shield", tint: Color(red: 0.37, green: 0.78, blue: 1.0),
              title: "“Review every action” mode",
              detail: "Optional strict approval for agents without a native prompt (Gemini, Cursor, Copilot, Kimi, AntiGravity) — Settings → General."),
        .init(symbol: "checklist", tint: Color(red: 0.55, green: 0.70, blue: 0.98),
              title: "Plan mode, beautifully rendered",
              detail: "Claude's plans show as formatted markdown in the notch — approve into ⏵⏵ auto mode, approve & review edits manually, keep planning, or answer in terminal."),
    ]

    var body: some View {
        ZStack {
            CosmicBackground()

            VStack(spacing: 16) {
                mascotParade
                    .padding(.top, 30)

                VStack(spacing: 6) {
                    Text("What's New")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Text("Code Island v\(version)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.08)))
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(highlights) { highlightRow($0) }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 4)
                }

                Button("Let's go", action: onClose)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.bottom, 26)
            }
        }
        .frame(width: 560, height: 640)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
    }

    /// All provider mascots, gently bouncing (status = thinking). Split into two
    /// balanced, centered rows — 21 don't fit one line in a 560pt window.
    private var mascotParade: some View {
        let all = AIProvider.all
        let mid = (all.count + 1) / 2
        return VStack(spacing: 8) {
            mascotRow(Array(all[0..<mid]))
            mascotRow(Array(all[mid...]))
        }
    }

    private func mascotRow(_ providers: [AIProvider]) -> some View {
        HStack(spacing: 5) {
            ForEach(providers) { p in
                SessionMascot(status: .thinking, size: 24, animated: true, provider: p)
            }
        }
    }

    private func highlightRow(_ h: Highlight) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: h.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(h.tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(h.tint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(h.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(h.detail)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

final class WhatsNewWindowController: NSWindowController {
    init(version: String, onClose: @escaping () -> Void) {
        let size = NSSize(width: 560, height: 640)
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.frame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screenFrame.midX - size.width / 2,
                             y: screenFrame.midY - size.height / 2)

        let window = OnboardingPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = NSWindow.Level(rawValue: 101)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = WhatsNewView(version: version, onClose: {
            window.orderOut(nil)
            window.close()
            onClose()
        })
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        window.contentView = host

        super.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}
