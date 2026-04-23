# Code Island

A native macOS app that turns your MacBook's notch into a live dashboard for Claude Code sessions. Approve permissions, answer questions, track rate limits, and jump between terminals — all from the notch.

![Code Island](design/logo.png)

## Features

- **Live session tracking** — see all running Claude Code sessions at a glance in the notch
- **Permission UI** — approve, deny, allow-all, or bypass from the notch without switching apps
- **Question UI** — answer `AskUserQuestion` prompts with pill buttons, multi-select support
- **Finished notifications** — see Claude's response inline when a task completes
- **Rate limit display** — 5h and 7d usage with color-coded warnings
- **Multi-session queue** — multiple agents' permissions queue up automatically
- **Terminal jump** — click a session card to jump back to the terminal running it
- **Dynamic terminal detection** — works with iTerm2, Ghostty, Terminal.app, VS Code, JetBrains, etc.
- **8-bit sound effects** — per-event toggles (session, completion, error, permission)
- **Pixel-art mascot** — animated Claude Code character that changes color with status

## Requirements

- macOS 14 (Sonoma) or later
- Claude Code installed

## Installation

1. Download the latest DMG from [Releases](https://github.com/YOUR_USERNAME/code-island/releases)
2. Drag `Code Island.app` to Applications
3. **For unsigned builds**, run this first to bypass Gatekeeper:
   ```bash
   xattr -cr /Applications/Code\ Island.app
   ```
4. Launch Code Island — the onboarding will install the required Claude Code hooks automatically
5. Start a new Claude Code session and watch the notch come alive

## How It Works

1. Claude Code fires hooks (`SessionStart`, `Stop`, `PreToolUse`, `PermissionRequest`, etc.)
2. Hook calls `~/.code-island/bin/code-island-bridge` with JSON on stdin
3. Bridge enriches the payload (terminal detection via process tree walk) and forwards to the app via Unix socket at `/tmp/code-island.sock`
4. For `PermissionRequest`: the socket connection stays open, the app sends a response back, and the bridge outputs it to stdout for Claude Code

## Architecture

```
Code Island.app/
├── Contents/
│   ├── MacOS/Code Island           ← Main SwiftUI app (menu bar + notch panel)
│   ├── Helpers/CodeIslandBridge    ← CLI bridge for Claude Code hooks
│   └── Info.plist                  ← LSUIElement=true (no dock icon)
└── ~/.code-island/
    ├── bin/code-island-bridge      ← Shell launcher (installed by hook installer)
    ├── bin/code-island-statusline  ← StatusLine script (caches rate limits)
    ├── cache/rl.json               ← Rate limit data
    └── debug.log                   ← Runtime log
```

**Tech stack:** Swift 5.9+, SwiftUI + AppKit, macOS 14.0+, Swift Package Manager, POSIX sockets, `AVAudioEngine` for 8-bit sound synthesis.

## Building from Source

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run debug
.build/debug/CodeIsland
```

To build the DMG installer (requires `create-dmg`):

```bash
brew install create-dmg
./scripts/build-dmg.sh 0.6.0   # produces build/Code-Island-0.6.0.dmg
```

## Development

- **Kill and relaunch:** `pkill -9 CodeIsland; rm -f /tmp/code-island.sock; .build/debug/CodeIsland &`
- **Reset onboarding:** `defaults delete dev.codeisland.macos`
- **Debug log:** `tail -f ~/.code-island/debug.log`
- **Test bridge:** `echo '{"session_id":"test","hook_event_name":"SessionStart","cwd":"/tmp"}' | .build/debug/CodeIslandBridge`

See [CLAUDE.md](CLAUDE.md) for detailed architecture notes and IPC payload formats.

## Contributing

PRs welcome! Areas that could use work:

- Code signing and notarization (so users don't need `xattr` workaround)
- Custom sound packs
- Session history view
- Multi-display notch support
- Windows/Linux terminal detection

## License

**Personal, non-commercial use only. No redistribution.** See [LICENSE](LICENSE) for full terms.

For commercial licensing, please contact the copyright holder.

## Credits

Inspired by [Vibe Island](https://vibeisland.app). Pixel mascot adapted from the [Claude Code Mascot Generator](https://claude-code-mascot-generator.replit.app/).
