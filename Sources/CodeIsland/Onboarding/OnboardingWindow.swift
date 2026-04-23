import SwiftUI
import ConfettiSwiftUI

struct OnboardingView: View {
    @ObservedObject var settingsStore: SettingsStore
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var confettiTrigger = 0
    @State private var hookInstallSuccess: Bool? = nil

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.1, green: 0.05, blue: 0.2),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                switch currentStep {
                case 0:
                    welcomeStep
                case 1:
                    installStep
                case 2:
                    readyStep
                default:
                    EmptyView()
                }
            }
            .padding(40)

            // Confetti overlay
            ConfettiCannon(counter: $confettiTrigger, num: 80, radius: 500)
        }
        .frame(width: 560, height: 520)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "terminal.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            Text("Welcome to Code Island")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            Text("Your MacBook's notch is about to become\nyour AI coding command center.")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Spacer()

            nextButton("Get Started")
        }
    }

    private var installStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 48))
                .foregroundColor(.cyan)

            Text("Install Hooks")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            Text("Code Island needs to register hooks with Claude Code\nto receive session events in real-time.")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 6) {
                hookRow("SessionStart / SessionEnd", "Monitor session lifecycle")
                hookRow("PreToolUse / PostToolUse", "Track tool execution")
                hookRow("PermissionRequest", "Approve/deny from the notch")
                hookRow("Notification / Stop", "Status updates")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.05))
            )

            Spacer()

            if let success = hookInstallSuccess {
                HStack(spacing: 8) {
                    Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(success ? .green : .orange)
                    Text(success ? "Hooks installed successfully!" : "Could not install hooks. Make sure Claude Code has been run at least once.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(success ? .green : .orange)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill((success ? Color.green : Color.orange).opacity(0.1))
                )
            }

            Button(action: {
                let success = HookInstaller.install()
                hookInstallSuccess = success
                if success {
                    currentStep += 1
                    confettiTrigger += 1
                }
            }) {
                Text(hookInstallSuccess == false ? "Retry Install" : "Install Hooks & Continue")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.cyan)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var readyStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text("You're All Set!")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            Text("Code Island is now monitoring your Claude Code sessions.\nStart coding and watch the notch come alive!")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            // Launch at login toggle
            HStack {
                Toggle(isOn: $settingsStore.launchAtLogin) {
                    HStack(spacing: 8) {
                        Image(systemName: "sunrise.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        Text("Launch at startup")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
                .toggleStyle(.switch)
                .tint(.green)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.05))
            )

            Spacer()

            Button(action: {
                settingsStore.hasCompletedOnboarding = true
                onComplete()
            }) {
                Text("Start Using Code Island")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.green)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func hookRow(_ name: String, _ desc: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 12))
                .foregroundColor(.cyan)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                Text(desc)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private func nextButton(_ title: String) -> some View {
        Button(action: { currentStep += 1 }) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.cyan)
                )
        }
        .buttonStyle(.plain)
    }
}

final class OnboardingWindowController: NSWindowController {
    init(settingsStore: SettingsStore, onComplete: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.center()

        let view = OnboardingView(settingsStore: settingsStore, onComplete: {
            window.close()
            onComplete()
        })
        window.contentView = NSHostingView(rootView: view)

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}
