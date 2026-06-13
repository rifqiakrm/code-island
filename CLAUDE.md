# Code Island

A native macOS Swift app that turns your MacBook's notch into a live dashboard for your AI coding agents (Claude Code + OpenAI Codex). Inspired by [Vibe Island](https://vibeisland.app). See [README.md](README.md) for user-facing docs.

## Architecture

```
Code Island.app/
├── Contents/
│   ├── MacOS/code-island                ← Main SwiftUI app (menu bar, notch panel)
│   ├── Helpers/CodeIslandBridge         ← CLI bridge (reads hook JSON via stdin; --source flag)
│   └── Info.plist                       ← LSUIElement=true (no dock icon)
└── ~/.code-island/
    ├── bin/code-island-bridge           ← Claude launcher (zsh shim)
    ├── bin/code-island-codex-bridge     ← Codex launcher (passes --source codex)
    ├── run/code-island.pid
    ├── cache/rl.json                    ← Cached rate limits per provider
    ├── debug.log                        ← Runtime debug log
    └── sound-packs/                     ← User sound packs
```

**Tech stack**: Swift 5.9+, SwiftUI + AppKit, macOS 14.0+, SPM

## Provider Abstraction

`AIProvider` (Sources/CodeIsland/Session/AIProvider.swift) unifies Claude and Codex with:
- `id`, `displayName`, `accentColor`
- `mascotShape` (.crab / .box / .sparkle)
- `mascotPalette` / `activeMascotPalette`
- `AIProvider.from(source:)` maps the bridge's `source` field to a provider

Each `Session.source` defaults to "claude" if the bridge doesn't stamp it.

## IPC Flow

1. Agent fires hooks (SessionStart, Stop, PreToolUse, PostToolUse, PermissionRequest, etc.)
2. Hook calls the appropriate launcher in `~/.code-island/bin/` with JSON on stdin
3. Bridge stamps `source` (claude / codex), captures parent PID via `getppid()`, enriches with terminal env vars (process tree walk for bundle ID)
4. Bridge sends JSON to Code Island app via Unix socket at `/tmp/code-island.sock`
5. For PermissionRequest: socket connection stays open, app sends response back, bridge outputs to stdout

## Key Hook Payload Fields

- `hook_event_name` — event type (NOT `hook_event`)
- `prompt` — user's message (UserPromptSubmit)
- `last_assistant_message` — assistant's response (Stop, Claude only)
- `permission_mode` — "bypassPermissions" means auto-allow (Claude only, set at session startup)
- `transcript_path` — path to session .jsonl file
- `tool_name` — for `AskUserQuestion` (Claude) or `request_user_input` (Codex), show question UI
- `source` — provider identifier ("claude" / "codex"), stamped by the bridge

## Permission Modes (Claude, mid-session setMode)

- `bypassPermissions` — **cannot be set mid-session**, only at Claude Code startup via `--dangerously-skip-permissions`. Mid-session setMode requests are silently ignored.
- `dontAsk` — works mid-session, suppresses future permission prompts for the session. This is what our "Bypass" button actually sends to Claude.
- `default` — normal mode, prompts for permissions.

## Codex Permission Persistence

Codex rejects Claude's `updatedPermissions` shape. For Allow All / Bypass we instead append a `prefix_rule(...)` block to `~/.codex/rules/codeisland.rules` (see `CodexPermissionRules.swift`):
- **Allow All** for Bash: first 3 tokens become the prefix (`git commit -m`)
- **Allow All** for other tools: prefix is the tool name
- **Bypass** (broad): first 1 token (Codex rejects empty patterns — true wildcards aren't possible)

The hook then responds with a plain `behavior: allow` since the rule will match future calls.

## Codex `request_user_input` Mirror

Codex's equivalent of Claude's `AskUserQuestion` fires via `PreToolUse` with `tool_name = "request_user_input"` and `tool_input.questions` matching Claude's shape. Codex PreToolUse hooks only support `allow/deny` (no answer substitution), so we:

1. Detect it in `SessionStore.handleMessage` PreToolUse branch
2. Mirror the question in the notch via `pendingQuestion`
3. On click, call `TerminalJumper.jump(to: session)` to surface Codex.app — user answers there
4. PostToolUse clears the pending question via the existing `pendingDismissedExternally` path

## Bridge Terminal Detection

The bridge walks up the process tree (ppid chain) to find the first GUI app with a bundle ID. Fully dynamic — works with any terminal/IDE without hardcoding. iTerm2 gets special treatment (AppleScript tab jump via ITERM_SESSION_ID, but only when TERM_PROGRAM=iTerm.app to avoid inherited env vars).

For Codex.app, the bundle ID is `com.openai.codex`; jump just activates the app (no tab API).

## Permission Response Format (Claude)

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow|deny",
      "updatedPermissions": [
        {"type": "addRules", "rules": [{"toolName": "Bash"}], "behavior": "allow", "destination": "session"},
        {"type": "setMode", "mode": "dontAsk", "destination": "session"}
      ]
    }
  }
}
```

## Question (AskUserQuestion) Response Format (Claude)

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedInput": {
        "questions": [...],
        "answers": {"What's your API style?": "REST", "Fuel?": "Coffee,Tea"}
      }
    }
  }
}
```

## Rate Limits

Live-fetched over HTTP (not statusline anymore):
- Claude: `api.anthropic.com/api/oauth/usage` with OAuth token from env → keychain → refresh
- Codex: `chatgpt.com/backend-api/wham/usage` with ChatGPT auth token

`RateLimitStore` keeps a per-provider snapshot, polls every 5 minutes, and `RateLimitBar` renders the active provider's 5h+7d windows. Tap to cycle providers; empty providers are skipped.

## Notch Window

- Layer 27 (same as Vibe Island, just above menu bar at 25)
- `constrainFrameRect` override to render in notch area
- `ClickThroughHostingView` with `acceptsFirstMouse` for click-through
- Collapsed: 280x34 on notch Macs, 280x5 on non-notch Macs (just a hover strip)
- Expanded: 600x320, Permission: 600x380, Question: 600x480, Finished: 600x380

## States

- **Collapsed** — mascot left, session count right
- **Expanded** (hover) — rate limit bar + sound toggle + settings gear + filter chips (when ≥2 providers active) + collapsible per-provider section list
- **Finished** (Stop event) — rate limit bar + session card with scrollable response + Done button, auto-collapses in 3s
- **Permission** — rate limit bar + tool details + 4 buttons (Deny, Allow Once, Allow All, Bypass)
- **Question** — rate limit bar + all questions shown, pill buttons, multi-select (Claude only), Submit All Answers

## Theming

`NotchTheme` (Sources/CodeIsland/Notch/NotchTheme.swift) is a pure token set that restyles the notch **chrome only**. Five themes, selectable in **Settings → Appearance** (live preview cards, instant switching):

- `default` — the original look, **unchanged** (load-bearing: existing users must see no difference)
- `glass` — Liquid Glass (translucent `.ultraThinMaterial` window, capsule controls, sans font)
- `pixel` — Retro 8-bit (dark cards, colored borders + colored hard offset shadows, square corners, mono)
- `terminal` — minimal (pure black, hairline chrome, mono)
- `brutalist` — Neo-Brutalist (vivid light cards + dark text, cream wells, black borders, hard white shadows, sans)

**Wiring**
- Persisted as `SettingsStore.notchThemeID` (UserDefaults, same `@Published`+`didSet` pattern). No pref / first launch → `.default` (the `didSet` only writes on user change, so a fresh install never persists a theme).
- `NotchContentView` reads `settingsStore.notchThemeID.theme` and injects `.environment(\.notchTheme, theme)`. Every view reads `@Environment(\.notchTheme) private var theme`.

**Invariant — chrome only.** Themes restyle window fill/border, card/box/pill/button shape (radius, stroke width, shadow), and font *design* (mono ↔ sans). They never touch **semantic/brand colors**: provider accents, mascot palettes, status colors (cyan/green/orange/red), tool colors, action-button red/green/purple, rate-limit thresholds. `cardForeground`/`wellForeground` default to `.white`, so the four dark themes render text identically to Default; only `brutalist` opts into dark text on its light cards/cream wells.

**Tokens & helpers**
- `theme.font(size:weight:)` — replaces `.system(…, design: .monospaced)` so a theme swaps the whole app mono↔sans.
- Drop-in background modifiers: `.notchCard(theme, tint:active:)`, `.notchBox(theme)`, `.notchPill(theme, fill:stroke:base:)`, `.notchButton(theme, fill:stroke:)`. **Shadows apply to the background SHAPE, not `self`** — a hard shadow on the whole view ghosts every glyph of text inside it.
- `PillCorner` policy (`.asAuthored`/`.square`/`.capsule`/`.cap`) lets each pill keep its authored `base` radius on Default while themes reshape it.
- `theme.buttonInk(accent)` → per-theme `(fill, stroke, text)` for action buttons.
- `theme.cardHueActive`/`cardHueIdle` — Pixel/Brutalist tint cards by activity (terracotta/sky-or-gray) instead of status; error→red + waiting→orange stay semantic (remap lives in `SessionCardView.cardTint`).
- `NotchBorderShape` strokes sides+bottom only (flush top, no seam) for bordered themes. The **collapsed strip is forced pure black in every theme** — only expanded windows are themed (`NotchBackground` branches on `isExpanded`).
- `SyntaxHighlighter.Theme.light` — dark-on-light palette used when `theme.lightWells` (Brutalist cream wells), passed to `highlight(...)`/`diff(...)`.

**Adding a theme**: add a `NotchThemeID` case + a `NotchTheme` instance in `NotchTheme.all`. It flows everywhere automatically; new windows that use the token modifiers theme for free.

## Permission/Question Queue

- `SessionStore.nextPendingPermission()` and `nextPendingQuestion()` return the next pending session
- After responding to one, the content view automatically shows the next pending permission/question
- On hover from collapsed state, if any permission/question is pending, it shows instead of expanding to the session list
- Permission/question states don't auto-collapse on mouse exit — user must respond
- `pendingPermission` / `pendingQuestion` cleared **synchronously** in `respondToPermission()` / `respondToQuestion()` before invoking the response closure, so the queue check sees accurate state

## Session Cleanup

Process-based, not time-based. Every 5s, `SessionStore.sweepClosedAgents()` calls `kill(pid, 0)` on each session's `agentPid` — if errno == ESRCH the process is gone and the session is marked completed and removed. This handles Codex's missing SessionEnd reliably while letting long-idle Claude sessions stay open.

## Mascots

- **Claude**: 13x8 pixel crab from the [Claude Code Mascot Generator](https://claude-code-mascot-generator.replit.app/). Terracotta default, cyan thinking, green idle, red error.
- **Codex**: pixel terminal box (head bump + body + `>_` face + stubby feet) in 58x52 logical space. Light gray default, sky-blue active.
- **Gemini**: sparkle (placeholder for future Gemini integration).

Animated bounce when thinking; color swaps via `mascotPalette` vs `activeMascotPalette`.

## Building

```bash
swift build                    # Debug
swift build -c release         # Release
```

## Creating DMG

```bash
brew install create-dmg
./scripts/build-dmg.sh 1.0.0   # produces build/Code-Island-1.0.0.dmg
```

## Development Tips

- Process name is `CodeIsland` (no space) — use `pkill -9 CodeIsland` not `pkill -f "Code Island"` (the latter matches other processes)
- Kill and relaunch: `pkill -9 CodeIsland; sleep 1; rm -f /tmp/code-island.sock; .build/debug/CodeIsland &`
- Reset onboarding/prefs: `defaults delete dev.codeisland.macos` (the bundle ID, not "CodeIsland")
- Full uninstall: `pkill -9 CodeIsland; rm -rf "/Applications/Code Island.app" ~/.code-island; defaults delete dev.codeisland.macos; rm -f /tmp/code-island.sock`
- Debug log: `tail -f ~/.code-island/debug.log`
- Test bridge: `echo '{"session_id":"test","hook_event_name":"SessionStart","cwd":"/tmp"}' | .build/debug/CodeIslandBridge`
- Test Codex bridge: append `--source codex` to the bridge invocation
- Tap raw Codex JSON: swap `~/.code-island/bin/code-island-codex-bridge` for a tee script that copies stdin to a debug file before forwarding

## Sounds

Per-sound toggles in Settings + onboarding `SoundEngine`:
- `sessionStart` / `sessionEnd`
- `completion` (fired on `Stop` → status `.idle`)
- `toolUse` (fired on `PreToolUse` — **off by default**, gets spammy)
- `error`
- `approvalNeeded` / `approvalGranted` / `approvalDenied`

Generated at runtime by `SoundSynthesizer` (8-bit square/triangle/sawtooth waves). Drop custom audio files (`.wav` / `.mp3` / `.m4a` / `.aiff` / `.caf`) into `~/.code-island/sound-packs/<event-name>.<ext>` to override; delete the file to revert to the synth default.

## Hook Installers

Both installers run idempotently on every launch (see `AppDelegate.applicationDidFinishLaunching`).

### Claude (`HookInstaller`)
1. Creates `~/.claude/` if needed (so first-time Claude users work)
2. Adds/updates hook entries for all event types with `matcher: "*"`
3. Writes the bridge launcher script at `~/.code-island/bin/code-island-bridge`

### Codex (`CodexInstaller`)
1. Creates `$CODEX_HOME` (default `~/.codex/`) if needed
2. Writes `~/.codex/hooks.json` in Codex's nested format (no `matcher` field) subscribing to: SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PostToolUse, Stop, PermissionRequest, Notification, SubagentStart, SubagentStop, PreCompact
3. Sets `[features].hooks = true` in `~/.codex/config.toml` (creates the section if missing)
4. Writes the bridge launcher at `~/.code-island/bin/code-island-codex-bridge` (passes `--source codex`)

Both return `Bool` for success/failure — onboarding shows a checkmark or retry UI based on this.
