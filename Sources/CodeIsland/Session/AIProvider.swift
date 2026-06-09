import SwiftUI

/// Represents an AI coding agent (Claude Code, Codex, Gemini, etc.).
/// Sessions are tagged with a provider id via `BridgeMessage.source`; the UI
/// uses this struct to group, filter, color, and label them.
///
/// Adding a new provider:
/// 1. Add a `static let` instance below
/// 2. Append it to `AIProvider.all`
/// 3. (Optional) Bundle its icon under `Resources/cli-icons/<id>.png`
/// 4. Build the appropriate bridge / installer that stamps `source: "<id>"` on hooks
struct AIProvider: Identifiable, Hashable {
    let id: String              // Stable identifier sent by the bridge (e.g. "claude")
    let displayName: String     // Shown in section headers & filter chips
    let accentColor: Color      // Tint for the accent border / section header / chip
    let mascotPalette: PixelMascot.MascotPalette        // Idle / branded palette
    let activeMascotPalette: PixelMascot.MascotPalette  // Thinking / tool-use palette (brand-tinted)
    let mascotShape: PixelMascot.MascotShape            // Silhouette drawn by the mascot view

    static let claude = AIProvider(
        id: "claude",
        displayName: "Claude",
        accentColor: Color(red: 0.85, green: 0.47, blue: 0.34),
        mascotPalette: .claude,
        activeMascotPalette: .claudeActive,
        mascotShape: .crab
    )

    static let codex = AIProvider(
        id: "codex",
        displayName: "Codex",
        accentColor: Color(red: 0.92, green: 0.92, blue: 0.92),
        mascotPalette: .codex,
        activeMascotPalette: .codexActive,
        mascotShape: .box
    )

    static let gemini = AIProvider(
        id: "gemini",
        displayName: "Gemini",
        accentColor: Color(red: 0.55, green: 0.62, blue: 1.00),
        mascotPalette: .gemini,
        activeMascotPalette: .geminiActive,
        mascotShape: .sparkle
    )

    static let all: [AIProvider] = [.claude, .codex, .gemini]

    static func from(_ source: String?) -> AIProvider {
        guard let source else { return .claude }
        return all.first(where: { $0.id == source }) ?? .claude
    }
}
