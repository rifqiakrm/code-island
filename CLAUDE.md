# Code Island

A native macOS Swift app that turns your MacBook's notch into a live dashboard for Claude Code. Inspired by [Vibe Island](https://vibeisland.app). See [README.md](README.md) for user-facing docs.

## Architecture

```
Code Island.app/
├── Contents/
│   ├── MacOS/code-island              ← Main SwiftUI app (menu bar, notch panel)
│   ├── Helpers/CodeIslandBridge       ← CLI bridge (reads Claude Code hooks via stdin)
│   └── Info.plist                     ← LSUIElement=true (no dock icon)
└── ~/.code-island/
    ├── bin/code-island-bridge         ← Shell launcher that finds the bridge binary
    ├── run/code-island.pid
    ├── cache/rl.json                  ← Rate limits (written by code-island-statusline)
    ├── debug.log                      ← Runtime debug log
    └── sound-packs/                   ← User sound packs (future)
```

**Tech stack**: Swift 5.9+, SwiftUI + AppKit, macOS 14.0+, SPM

## IPC Flow

1. Claude Code fires hooks (SessionStart, Stop, PreToolUse, PostToolUse, PermissionRequest, etc.)
2. Hook calls `~/.code-island/bin/code-island-bridge` with JSON on stdin
3. Bridge enriches with env vars (terminal detection via process tree walk)
4. Bridge sends JSON to Code Island app via Unix socket at `/tmp/code-island.sock`
5. For PermissionRequest: socket connection stays open, app sends response back, bridge outputs to stdout

## Key Hook Payload Fields

- `hook_event_name` — event type (NOT `hook_event`)
- `prompt` — user's message (in UserPromptSubmit)
- `last_assistant_message` — Claude's response (in Stop)
- `permission_mode` — "bypassPermissions" means auto-allow (only set at session startup, can't be set mid-session)
- `transcript_path` — path to session .jsonl file
- `tool_name` — for AskUserQuestion, show question UI instead of permission UI

## Permission Modes (mid-session setMode)

- `bypassPermissions` — **cannot be set mid-session**, only at Claude Code startup via `--dangerously-skip-permissions`. Mid-session setMode requests are silently ignored.
- `dontAsk` — works mid-session, suppresses future permission prompts for the session. This is what our "Bypass" button actually sends.
- `default` — normal mode, prompts for permissions.

## Bridge Terminal Detection

The bridge walks up the process tree (ppid chain) to find the first GUI app with a bundle ID. This is fully dynamic — works with any terminal/IDE without hardcoding. iTerm2 gets special treatment (AppleScript tab jump via ITERM_SESSION_ID, but only when TERM_PROGRAM=iTerm.app to avoid inherited env vars).

## Permission Response Format

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow|deny",
      "updatedPermissions": [
        {"type": "addRules", "rules": [{"toolName": "Bash"}], "behavior": "allow", "destination": "session"},
        {"type": "setMode", "mode": "bypassPermissions", "destination": "session"}
      ]
    }
  }
}
```

## Question (AskUserQuestion) Response Format

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

## Notch Window

- Layer 27 (same as Vibe Island, just above menu bar at 25)
- `constrainFrameRect` override to render in notch area
- `ClickThroughHostingView` with `acceptsFirstMouse` for click-through
- Collapsed: 280x34 on notch Macs, 280x5 on non-notch Macs (just a hover strip)
- Expanded: 520x320, Permission: 520x300, Question: 520x420, Finished: 520x200

## States

- **Collapsed** — mascot left, session count right
- **Expanded** (hover) — rate limits header + sound toggle + settings gear + session cards + footer
- **Finished** (Stop event) — rate limit bar + session card with scrollable response + Done button, auto-collapses in 3s
- **Permission** — rate limit bar + tool details + 4 buttons (Deny, Allow Once, Allow All, Bypass)
- **Question** — rate limit bar + all questions shown, pill buttons, multi-select support, Submit All Answers

## Permission/Question Queue

- `SessionStore.nextPendingPermission()` and `nextPendingQuestion()` return the next pending session
- After responding to one, the content view automatically shows the next pending permission/question
- On hover from collapsed state, if any permission/question is pending, it shows instead of expanding to the session list
- Permission/question states don't auto-collapse on mouse exit — user must respond
- `pendingPermission` / `pendingQuestion` cleared **synchronously** in `respondToPermission()` / `respondToQuestion()` before invoking the response closure, so the queue check sees accurate state

## Mascot

13x8 pixel grid from the official Claude Code mascot generator (https://claude-code-mascot-generator.replit.app/). Colors change by status: terracotta (default), cyan (thinking), green (idle), red (error). Animated bounce when thinking.

## Building

```bash
swift build                    # Debug
swift build -c release         # Release
```

## Creating DMG

```bash
brew install create-dmg
# See build script or run the create-dmg command from the conversation
```

## Development Tips

- Process name is `CodeIsland` (no space) — use `pkill -9 CodeIsland` not `pkill -f "Code Island"` (the latter matches other processes)
- Kill and relaunch: `pkill -9 CodeIsland; sleep 1; rm -f /tmp/code-island.sock; .build/debug/CodeIsland &`
- Reset onboarding/prefs: `defaults delete dev.codeisland.macos` (the bundle ID, not "CodeIsland")
- Full uninstall: `pkill -9 CodeIsland; rm -rf "/Applications/Code Island.app" ~/.code-island; defaults delete dev.codeisland.macos; rm -f /tmp/code-island.sock`
- Debug log: `tail -f ~/.code-island/debug.log`
- Test bridge: `echo '{"session_id":"test","hook_event_name":"SessionStart","cwd":"/tmp"}' | .build/debug/CodeIslandBridge`

## Sounds

Per-sound toggles in Settings + onboarding `SoundEngine`:
- `sessionStart` / `sessionEnd`
- `completion` (fired on `Stop` → status `.idle`)
- `toolUse` (fired on `PreToolUse` — **off by default**, gets spammy)
- `error`
- `approvalNeeded` / `approvalGranted` / `approvalDenied`

Generated at runtime by `SoundSynthesizer` (8-bit square/triangle/sawtooth waves). No audio files bundled.

## Hook Installer

`HookInstaller.install()` is idempotent and creates `~/.claude/settings.json` if missing (so first-time Claude Code users work). It:
1. Creates `~/.claude/` directory if needed
2. Adds/updates hook entries for all event types with `matcher: "*"`
3. Sets `statusLine` to our script at `~/.code-island/bin/code-island-statusline`
4. Writes the bridge launcher script (a zsh shim that locates the binary in Applications or dev build)
5. Writes the statusline script (caches `rate_limits` field from statusLine input to `~/.code-island/cache/rl.json`)

Returns `Bool` for success/failure — onboarding shows a checkmark or retry UI based on this.
