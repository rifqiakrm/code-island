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
        accentColor: Color(red: 0.278, green: 0.588, blue: 0.894),
        mascotPalette: .gemini,
        activeMascotPalette: .geminiActive,
        mascotShape: .geminiStar
    )

    static let qwen = AIProvider(
        id: "qwen",
        displayName: "Qwen Code",
        accentColor: Color(red: 0.486, green: 0.228, blue: 0.929),
        mascotPalette: .qwen,
        activeMascotPalette: .qwenActive,
        mascotShape: .qwenGem
    )

    static let qoder = AIProvider(
        id: "qoder",
        displayName: "Qoder",
        accentColor: Color(red: 0.165, green: 0.859, blue: 0.361),
        mascotPalette: .qoder,
        activeMascotPalette: .qoderActive,
        mascotShape: .qoderBlob
    )

    /// Factory's CLI is `droid` — the bridge stamps `--source droid`, so the
    /// id matches that while the label stays "Factory".
    static let factory = AIProvider(
        id: "droid",
        displayName: "Factory",
        accentColor: Color(red: 0.835, green: 0.416, blue: 0.149),
        mascotPalette: .factory,
        activeMascotPalette: .factoryActive,
        mascotShape: .factoryBot
    )

    static let codebuddy = AIProvider(
        id: "codebuddy",
        displayName: "CodeBuddy",
        accentColor: Color(red: 0.424, green: 0.302, blue: 1.000),
        mascotPalette: .codebuddy,
        activeMascotPalette: .codebuddyActive,
        mascotShape: .buddyCat
    )

    static let cursor = AIProvider(
        id: "cursor",
        displayName: "Cursor",
        // Cursor's brand is near-black; use a readable warm-gray for the
        // chip/border tint so it isn't invisible on the dark notch.
        accentColor: Color(red: 0.60, green: 0.58, blue: 0.54),
        mascotPalette: .cursor,
        activeMascotPalette: .cursorActive,
        mascotShape: .cursorBox
    )

    static let copilot = AIProvider(
        id: "copilot",
        displayName: "Copilot",
        accentColor: Color(red: 0.800, green: 0.200, blue: 0.400),
        mascotPalette: .copilot,
        activeMascotPalette: .copilotActive,
        mascotShape: .copilotBot
    )

    static let kimi = AIProvider(
        id: "kimi",
        displayName: "Kimi",
        accentColor: Color(red: 0.29, green: 0.56, blue: 1.000),  // Kimi blue #4A90FF
        mascotPalette: .kimi,
        activeMascotPalette: .kimiActive,
        mascotShape: .kimiMoon
    )

    static let opencode = AIProvider(
        id: "opencode",
        displayName: "OpenCode",
        // OpenCode is monochrome; readable light gray so the chip/border isn't
        // invisible on the dark notch (same approach as Cursor's near-black).
        accentColor: Color(red: 0.62, green: 0.62, blue: 0.64),
        mascotPalette: .opencode,
        activeMascotPalette: .opencodeActive,
        mascotShape: .openCodeMark
    )

    static let cline = AIProvider(
        id: "cline",
        displayName: "Cline",
        accentColor: Color(red: 0.00, green: 0.70, blue: 0.49),  // Cline green #00B37D
        mascotPalette: .cline,
        activeMascotPalette: .clineActive,
        mascotShape: .clineBot
    )

    static let trae = AIProvider(
        id: "trae", displayName: "Trae",
        accentColor: Color(red: 0.953, green: 0.286, blue: 0.275),  // Trae coral-red
        mascotPalette: .trae, activeMascotPalette: .traeActive, mascotShape: .traeRocket
    )
    static let traecli = AIProvider(
        id: "traecli", displayName: "TraeCli",
        accentColor: Color(red: 0.94, green: 0.18, blue: 0.14),  // Trae red
        mascotPalette: .traecli, activeMascotPalette: .traecliActive, mascotShape: .traeBolt
    )
    static let kiro = AIProvider(
        id: "kiro", displayName: "Kiro",
        accentColor: Color(red: 0.49, green: 0.36, blue: 1.00),  // Kiro violet
        mascotPalette: .kiro, activeMascotPalette: .kiroActive, mascotShape: .kiroGhost
    )
    static let pi = AIProvider(
        id: "pi", displayName: "Pi",
        accentColor: Color(red: 0.96, green: 0.69, blue: 0.13),  // Pi amber
        mascotPalette: .pi, activeMascotPalette: .piActive, mascotShape: .piGlyph
    )
    static let ohMyPi = AIProvider(
        id: "omp", displayName: "Oh My Pi",
        accentColor: Color(red: 0.13, green: 0.78, blue: 0.74),  // OMP teal
        mascotPalette: .omp, activeMascotPalette: .ompActive, mascotShape: .piGlyph
    )
    static let stepfun = AIProvider(
        id: "stepfun", displayName: "StepFun",
        accentColor: Color(red: 0.247, green: 0.318, blue: 0.953),  // StepFun indigo
        mascotPalette: .stepfun, activeMascotPalette: .stepfunActive, mascotShape: .stepfunStairs
    )
    static let antigravity = AIProvider(
        id: "antigravity", displayName: "AntiGravity",
        accentColor: Color(red: 0.259, green: 0.522, blue: 0.957),  // Google blue
        mascotPalette: .antigravity, activeMascotPalette: .antigravityActive, mascotShape: .antigravityOrbit
    )
    static let workbuddy = AIProvider(
        id: "workbuddy", displayName: "WorkBuddy",
        accentColor: Color(red: 0.000, green: 0.322, blue: 0.851),  // Tencent blue
        mascotPalette: .workbuddy, activeMascotPalette: .workbuddyActive, mascotShape: .workbuddyPal
    )
    static let hermes = AIProvider(
        id: "hermes", displayName: "Hermes",
        accentColor: Color(red: 0.953, green: 0.722, blue: 0.196),  // Hermes gold
        mascotPalette: .hermes, activeMascotPalette: .hermesActive, mascotShape: .hermesWing
    )

    static let all: [AIProvider] = [
        .claude, .codex, .gemini, .qwen, .qoder, .factory, .codebuddy, .cursor, .copilot,
        .kimi, .opencode, .cline,
        .trae, .traecli, .kiro, .pi, .ohMyPi, .stepfun, .antigravity, .workbuddy, .hermes,
    ]

    static func from(_ source: String?) -> AIProvider {
        guard let source else { return .claude }
        return all.first(where: { $0.id == source }) ?? .claude
    }

    /// Which buttons the permission window should show — capped to what each
    /// tool's hook actually supports (showing buttons that silently no-op is
    /// worse than not showing them). Claude/Codex persist allow-all & bypass;
    /// Claude-fork + OpenCode support allow-all; Cursor/Copilot only allow an
    /// allow/deny/defer; Gemini/Kimi only allow/deny.
    var permissionActions: [PermissionAction] {
        switch id {
        case "claude", "codex":          return [.deny, .allowOnce, .allowAll, .bypass]
        case "qwen", "qoder", "opencode": return [.deny, .allowOnce, .allowAll]
        case "cursor", "copilot", "trae": return [.deny, .allowOnce, .deferToApp]
        default:                         return [.deny, .allowOnce]   // gemini, kimi, forks, pi, kiro, …
        }
    }
}
