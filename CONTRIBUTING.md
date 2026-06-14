# Contributing to Code Island

Thanks for helping out! Code Island is a native macOS app that turns the notch
into a live dashboard for AI coding agents. This doc covers building, adding a
provider, testing, and the release process. See [CLAUDE.md](CLAUDE.md) for the
deep architecture notes.

## Building

```bash
swift build                 # debug
swift build -c release      # release
```

Run the debug build:

```bash
pkill -9 -f "Code Island.app/Contents/MacOS/Code Island"; pkill -9 -x CodeIsland
rm -f /tmp/code-island.sock
.build/debug/CodeIsland &
```

> The bundled app's process is **`Code Island`** (with a space); the `swift run`
> binary is **`CodeIsland`** (no space). Kill both forms when restarting.

Debug log: `tail -f ~/.code-island/debug.log`

## Adding a provider

Adding an agent is mostly data + a mascot:

1. **`AIProvider`** entry (id, accent color, mascot) — `Sources/CodeIsland/Session/AIProvider.swift`. `AIProvider.all` is the source of truth.
2. **`PixelMascot`** shape + idle/active palette — `Sources/CodeIsland/Notch/Views/PixelMascot.swift`.
3. **`ProviderInstaller.Descriptor`** (config path, `Format`, timeout unit, events) — `Sources/CodeIsland/Utilities/ProviderInstaller.swift`. Add a new `Format` case if the config layout is exotic (TOML, JS plugin, bash scripts, YAML all have precedents).
4. **Bridge event-name normalization** — `Sources/CodeIslandBridge/main.swift` — if the tool's hook vocabulary differs from the canonical set.
5. **CLI icon** at `Resources/cli-icons/<id>.png`.
6. A **Settings → Providers** reinstall row (`integrationsForm` in `SettingsView.swift`) and, if it has a blanket "before every tool" hook, a `strictApprovalProviders` entry.

## Testing & verifying agents — please do this

This is the single most useful contribution. **Verify each agent's real hook
config against its OFFICIAL docs before trusting it.** We have shipped wrong
integrations before (a "provider" that didn't exist, others with wrong paths or
event names) because we trusted a reference repo / assumptions instead of the
vendor docs.

For any agent you actually use, confirm against the vendor's docs/GitHub:

1. It's a real CLI agent with an **external shell-hook** mechanism (not a model/API provider, not a desktop-only app).
2. The **exact config file path** it reads.
3. The **format + event names**.
4. Whether a hook can **block**, and the **exact response shape** it expects (field names).

Then exercise it live: sessions, tool tracking, prompt/reply text, permission /
question flows, and terminal jump. Open an issue when something's off — real
reports on agents the maintainer can't run regularly are gold.

## Code style

- Match the surrounding code's idiom, comment density, and naming.
- **Commits: no `Co-Authored-By` trailer.** Keep messages concise and factual.
- Use a privacy-safe commit email (GitHub's `…@users.noreply.github.com` — enable *Settings → Emails → Keep my email addresses private*).

## Releasing (maintainers)

1. Make sure `main` is green and all the commits for the release are in.
2. Build the DMG (bakes the version into `Info.plist`):
   ```bash
   ./scripts/build-dmg.sh <version>     # e.g. 1.4.2 → build/Code-Island-<version>.dmg
   ```
3. Push `main`, then tag:
   ```bash
   git push origin main
   git tag -a v<version> -m "v<version>"
   git push origin v<version>
   ```
4. Create the GitHub release with the DMG attached. **The release notes MUST end
   with an Install section and a support line** (the build is unsigned, so users
   need the quarantine-clear step):

   ```bash
   gh release create v<version> build/Code-Island-<version>.dmg \
     --repo <owner>/code-island \
     --title "v<version> — <headline>" \
     --notes "## What's new in v<version>

   - …

   ### Install
   1. Download \`Code-Island-<version>.dmg\` below, open it, drag **Code Island** to Applications.
   2. Unsigned build — clear the quarantine flag first:
      \`\`\`
      xattr -cr \"/Applications/Code Island.app\"
      \`\`\`
   3. Launch — hooks auto-install for every detected agent.

   ☕ Free & open source. Support development: https://ko-fi.com/rifqiakrm"
   ```

5. Verify the release is live with its asset attached.

Large media (demo GIF/video) is hosted as a **GitHub release asset** (tag
`media`), not committed to the repo, so clones stay small.
