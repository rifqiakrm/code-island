# Code Island

A native macOS Swift app that turns your MacBook's notch into a live dashboard for **12 AI coding agents** — Claude Code, Codex, Gemini, Qwen, Qoder, Factory (`droid`), CodeBuddy, Cursor, Copilot, Kimi, OpenCode, and Cline. Inspired by [Vibe Island](https://vibeisland.app). See [README.md](README.md) for user-facing docs.

## Architecture

```
Code Island.app/
├── Contents/
│   ├── MacOS/code-island                ← Main SwiftUI app (menu bar, notch panel)
│   ├── Helpers/CodeIslandBridge         ← CLI bridge: reads hook JSON via stdin; --source / --event flags
│   └── Info.plist                       ← LSUIElement=true (no dock icon)
└── ~/.code-island/
    ├── bin/code-island-<agent>-bridge   ← one zsh launcher per agent (claude has no suffix; codex/gemini/cursor/…)
    ├── config.json                      ← {"strictApproval": {provider: bool}} — read by the bridge
    ├── run/code-island.pid
    ├── cache/rl.json                    ← Cached rate limits per provider
    ├── debug.log                        ← Runtime debug log
    └── sound-packs/                     ← User sound packs
```

**Tech stack**: Swift 5.9+, SwiftUI + AppKit, macOS 14.0+, SPM

## Provider Abstraction

`AIProvider` (Sources/CodeIsland/Session/AIProvider.swift) unifies all 12 agents with:
- `id`, `displayName`, `accentColor`
- `mascotShape` (per-agent Canvas pixel art — `.crab`, `.box`, `.geminiStar`, `.qwenGem`, `.qoderBlob`, `.factoryBot`, `.buddyCat`, `.cursorBox`, `.copilotBot`, `.kimiMoon`, `.openCodeMark`, `.clineBot`)
- `mascotPalette` / `activeMascotPalette`
- `AIProvider.from(source:)` maps the bridge's `source` field to a provider
- `AIProvider.all` is the source of truth — adding a provider here flows it everywhere (filter chips, grouping, mascot, accent)

Note: Factory's CLI is `droid`, so its provider `id` is `"droid"` while `displayName` is "Factory".
Each `Session.source` defaults to "claude" if the bridge doesn't stamp it. **The CLI icon (`ProviderIcon`) loads `Resources/cli-icons/<id>.png`** (so Factory's icon is `droid.png`); README/onboarding mascots are rendered from the same `PixelMascot` code to `docs/mascots/<id>.png`.

**Adding a provider** (see README "Contributing" for the checklist): `AIProvider` entry + `PixelMascot` shape/palette + a `ProviderInstaller.Descriptor` (or new `Format`) + bridge event-normalization (if its vocabulary differs) + `Resources/cli-icons/<id>.png`.

## IPC Flow

1. Agent fires hooks (SessionStart, Stop, PreToolUse, PostToolUse, PermissionRequest, etc.)
2. Hook calls the appropriate launcher in `~/.code-island/bin/` with JSON on stdin (some agents also pass `--event <name>` because their stdin omits the event)
3. Bridge stamps `source`, captures parent PID via `getppid()`, enriches with terminal env vars (process tree walk for bundle ID), and **normalizes each agent's event vocabulary to our canonical set** (e.g. Gemini `BeforeTool`→`PreToolUse`, Cursor `afterAgentResponse`→`Stop`)
4. Bridge sends JSON to Code Island app via Unix socket at `/tmp/code-island.sock`
5. For PermissionRequest: socket connection stays open, app sends response back, bridge outputs to stdout (translating to the agent's native response shape when it's a strict-approval gate — see below)

**Canonical event guard**: `SessionStore.handleMessage` drops any message whose `hookEvent` isn't in the canonical set (`SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Stop`, `Notification`, `SubagentStart`, `SubagentStop`, `PreCompact`). Every bridge normalizes to these before sending, so a raw camelCase name arriving means a foreign/misconfigured integration sharing the socket — ignore it (this fixed Cursor sessions getting mis-attributed to Claude by a phantom sender).

## Key Hook Payload Fields

- `hook_event_name` — event type (NOT `hook_event`)
- `prompt` — user's message (UserPromptSubmit)
- `last_assistant_message` — assistant's response (Stop, Claude only)
- `permission_mode` — "bypassPermissions" means auto-allow (Claude only, set at session startup)
- `transcript_path` — path to session .jsonl file
- `tool_name` — for `AskUserQuestion` (Claude) or `request_user_input` (Codex), show question UI
- `source` — provider identifier ("claude", "codex", "gemini", "cursor", "droid", …), stamped by the bridge from `--source`

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
- **Permission** — rate limit bar + tool details + **provider-aware buttons** (`AIProvider.permissionActions`): Claude/Codex get Deny·Allow Once·Allow All·Bypass; Qwen/Qoder/OpenCode drop Bypass; Cursor/Copilot show Deny·Allow Once·"Decide in <app>" (defers via behavior "ask" + jump); Gemini/Kimi show only Deny·Allow Once. Showing a button the tool can't honor (silent no-op) is worse than omitting it.
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

All mascots are Canvas-drawn pixel art in `PixelMascot.swift`, authored in a 52-unit-tall logical space. Each agent has its own `MascotShape` + idle/active `MascotPalette`:
- **Claude** crab, **Codex** terminal box (these two animate their legs/feet directly).
- **Gemini** star, **Qwen** gem, **Qoder** blob, **Factory** industrial bot, **CodeBuddy** cat, **Cursor** editor box, **Copilot** goggled bot, **Kimi** lunar orb, **OpenCode** monitor box, **Cline** rounded bot.

The provider mascots are drawn via the shared `drawShape(...)` helper, which applies a **whole-body bounce** when `animate` is true (the "thinking" liveliness) — no per-mascot leg rig. Color swaps via `mascotPalette` vs `activeMascotPalette`; transient statuses (thinking/error/waiting) override the provider palette so status reads at a glance (`SessionMascot.paletteFor`).

Brand-original mascots (no reference art): Qwen, Copilot, Kimi. The rest were ported from the reference repo's gifs into our pixel style.

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

Three installers run idempotently on every launch (`AppDelegate.applicationDidFinishLaunching` → `HookInstaller.install()`, `CodexInstaller.install()`, `ProviderInstaller.installAll()`). All preserve foreign hooks, back the original up to `.bak`, and skip the write when nothing changed.

### Claude (`HookInstaller`) — `~/.claude/settings.json`, all events with `matcher: "*"`, launcher `code-island-bridge`.
### Codex (`CodexInstaller`) — `~/.codex/hooks.json` (nested, no matcher) + `[features].hooks = true` in `config.toml`; launcher `code-island-codex-bridge`. Also persists Allow-All/Bypass as `prefix_rule(...)` (see Codex Permission Persistence).

### The other 10 (`ProviderInstaller`, Sources/CodeIsland/Utilities/ProviderInstaller.swift)
A single descriptor-driven engine. Each provider is a `Descriptor` (source, config path, `Format`, `TimeoutUnit`, events, `createDirIfMissing`, `detectPaths`). Only installs when the tool is present (config dir exists OR a `detectPaths` entry exists), except Factory which bootstraps. `Format` cases:
- `.claudeFork` — `{matcher:"*", hooks:[{type,command,timeout}]}` per event. **Gemini timeouts are ms**, the rest seconds. (Qwen/Qoder/Factory/CodeBuddy.)
- `.nested` — like claudeFork without `matcher` (Gemini).
- `.flat` — `[{command}]`, event via `--event` (Cursor).
- `.copilot` — `{version:1, hooks:{event:[{type,bash,timeoutSec}]}}`, event via `--event`.
- `.toml` — Kimi: marker-delimited `[[hooks]]` block appended to `~/.kimi/config.toml` (text merge, not JSON).
- `.opencodePlugin` — writes a JS plugin to `~/.config/opencode/plugins/codeisland.js` and registers it in `opencode.json`'s `plugin` array (JSONC-tolerant).
- `.clineScripts` — one executable bash script per event in `~/Documents/Cline/Hooks/` (chmod 0755), each pipes stdin → launcher `--event` and prints `{"cancel":false}`.

`installSource(_:)` force-installs one provider (Settings → Providers reinstall buttons). Returns `Bool` for the onboarding checkmark/retry UI.

## Permission Support per Provider

Only agents with a **selective** permission hook drive the in-notch approve/deny+question UI: **Claude, Codex, Qwen, Qoder** (Claude-shape `PermissionRequest`), and **OpenCode** (plugin handles `permission.asked`). Factory/CodeBuddy use the Claude-fork default event set that omits `PermissionRequest`; Gemini/Cursor/Copilot/Kimi only have blanket "before every tool" hooks (no native selective event); Cline's file hooks are observe-only. (Verified against the reference repo's tested config — don't subscribe forks to `PermissionRequest` speculatively; it risks a hook hang.)

## Strict Approval ("Review every action")

Opt-in, per provider, for the four blanket-hook tools (**Gemini, Cursor, Copilot, Kimi**) that lack a selective permission event. `SettingsStore.strictApproval: [String: Bool]` is persisted to UserDefaults AND mirrored to `~/.code-island/config.json`. The bridge reads that file each run; when a provider's flag is on and the event is one of its gate events (`permissionGateEvents` in main.swift — Gemini `BeforeTool`, Cursor `beforeShellExecution`/`beforeMCPExecution`, Copilot `preToolUse`, Kimi `PreToolUse`), it routes the event through the blocking `PermissionRequest` path and **translates** the app's Claude-shaped decision into the tool's native response (`{"permission":…}` / `{"decision":…}` / `{"permissionDecision":…}` / Kimi's `hookSpecificOutput`). Gate-event hook timeouts are installed long (~5 min) so the prompt has time; off → the bridge returns instantly (today's PreToolUse behavior). Settings → General → "Review every action".

## Onboarding & What's New

- **Onboarding** (`OnboardingWindow.swift`, full-screen cosmic) shows once, gated on `SettingsStore.hasSeenThemeOnboarding`. Has a provider mascot strip + Back button (`reverse`-aware slide).
- **What's New** (`WhatsNewView`/`WhatsNewWindowController`, same file) — a centered card with the bouncing mascot parade + release highlights. Shown once per version bump, gated on `SettingsStore.lastWhatsNewVersion != updateChecker.currentVersion`. Fresh installs get onboarding only (we stamp the version so they skip What's New). Re-openable anytime via the menu-bar "What's New" item (`MenuBarManager.onShowWhatsNew`).
