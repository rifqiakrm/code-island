import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Code Island Settings")
                .font(.system(size: 16, weight: .bold, design: .monospaced))

            GroupBox("Sound") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable sounds", isOn: $settingsStore.soundEnabled)
                        .font(.system(size: 13, design: .monospaced))

                    HStack {
                        Text("Volume")
                            .font(.system(size: 12, design: .monospaced))
                        Slider(value: $settingsStore.soundVolume, in: 0...1)
                    }
                    .disabled(!settingsStore.soundEnabled)

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Session start/end", isOn: $settingsStore.soundSessionStart)
                        Toggle("Completion", isOn: $settingsStore.soundCompletion)
                        Toggle("Tool use", isOn: $settingsStore.soundToolUse)
                        Toggle("Error", isOn: $settingsStore.soundError)
                        Toggle("Permission", isOn: $settingsStore.soundPermission)
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .disabled(!settingsStore.soundEnabled)
                }
                .padding(4)
            }

            GroupBox("Behavior") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Auto-expand on permission request", isOn: $settingsStore.autoExpandOnPermission)
                        .font(.system(size: 13, design: .monospaced))

                    Toggle("Launch at login", isOn: $settingsStore.launchAtLogin)
                        .font(.system(size: 13, design: .monospaced))
                }
                .padding(4)
            }

            GroupBox("Integration") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Socket")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("/tmp/code-island.sock")
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    Button("Install Claude Code Hooks") {
                        HookInstaller.install()
                    }
                    .font(.system(size: 12, design: .monospaced))
                }
                .padding(4)
            }

            Spacer()

            HStack {
                Text("Code Island v0.9.0")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 380, height: 500)
    }
}
