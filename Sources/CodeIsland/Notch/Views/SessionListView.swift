import SwiftUI

struct SessionListView: View {
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var rateLimitStore: RateLimitStore
    @ObservedObject var settingsStore: SettingsStore
    let onCollapse: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.notchTheme) private var theme

    /// nil = "ALL"; otherwise filter to a single provider.
    @State private var selectedProvider: AIProvider? = nil
    /// Provider ids that the user has collapsed — their cards are hidden
    /// behind the section header until expanded again.
    @State private var collapsedProviders: Set<String> = []

    /// Which provider's rate limits to render in the bar. When a filter is
    /// active we follow it; otherwise we show the provider whose session most
    /// recently saw activity (or fall back to Claude if there are no sessions).
    private var rateLimitProvider: AIProvider {
        if let sel = selectedProvider { return sel }
        if let latest = sessionStore.activeSessions.values
            .sorted(by: { $0.lastActivityAt > $1.lastActivityAt }).first {
            return latest.provider
        }
        return .claude
    }

    /// Tapping the rate limit bar cycles selectedProvider through every
    /// provider that actually has data to show, skipping ones that would
    /// just render as "—" (no auth / no data). If no provider has data we
    /// fall through to the default cycle so the user can still flip away
    /// from a stale state.
    private func cycleRateLimitProvider() {
        let providers = AIProvider.all
        let withData = providers.filter { p in
            let snap = rateLimitStore.snapshot(for: p)
            return snap.fiveHour != nil || snap.sevenDay != nil
        }
        let cycleList = withData.isEmpty ? providers : withData
        let current = rateLimitProvider
        guard let idx = cycleList.firstIndex(of: current) else {
            selectedProvider = cycleList.first
            return
        }
        selectedProvider = cycleList[(idx + 1) % cycleList.count]
    }

    /// Providers that actually have at least one active session — used to render
    /// section headers AND drive which filter chips are visible.
    private var presentProviders: [AIProvider] {
        let ids = Set(sessionStore.activeSessions.values.map { $0.source })
        return AIProvider.all.filter { ids.contains($0.id) }
    }

    private func sessions(for provider: AIProvider) -> [Session] {
        sessionStore.activeSessions.values
            .filter { $0.source == provider.id }
            .sorted(by: { $0.startedAt > $1.startedAt })
    }

    private var visibleProviders: [AIProvider] {
        if let sel = selectedProvider { return [sel] }
        return presentProviders
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top row: rate limits + sound + gear
            HStack(spacing: 8) {
                RateLimitBar(
                    rateLimitStore: rateLimitStore,
                    provider: rateLimitProvider,
                    onTap: cycleRateLimitProvider
                )
                Spacer()
                Button(action: { settingsStore.soundEnabled.toggle() }) {
                    Image(systemName: settingsStore.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(settingsStore.soundEnabled ? 0.6 : 0.3))
                }
                .buttonStyle(.plain)
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Filter chips — only show when there are >=2 providers active
            if presentProviders.count >= 2 {
                HStack(spacing: 5) {
                    filterChip(provider: nil, label: "ALL", count: sessionStore.activeSessions.count, color: .white)
                    ForEach(presentProviders) { p in
                        filterChip(provider: p, label: p.displayName.uppercased(), count: sessions(for: p).count, color: p.accentColor)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }

            if sessionStore.activeSessions.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.3))
                    Text("No active sessions")
                        .font(theme.font(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                    Text("Start Claude Code to begin")
                        .font(theme.font(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(visibleProviders) { provider in
                            let cards = sessions(for: provider)
                            if !cards.isEmpty {
                                let isCollapsed = collapsedProviders.contains(provider.id)
                                VStack(alignment: .leading, spacing: 6) {
                                    // Section header — also the collapse toggle.
                                    // Shown when we're displaying more than one
                                    // provider OR a filter is active.
                                    if visibleProviders.count >= 2 || selectedProvider != nil {
                                        sectionHeader(
                                            provider: provider,
                                            count: cards.count,
                                            collapsed: isCollapsed
                                        )
                                        .padding(.horizontal, 4)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            withAnimation(.easeInOut(duration: 0.18)) {
                                                if isCollapsed {
                                                    collapsedProviders.remove(provider.id)
                                                } else {
                                                    collapsedProviders.insert(provider.id)
                                                }
                                            }
                                        }
                                    }
                                    if !isCollapsed {
                                        VStack(spacing: 6) {
                                            ForEach(cards, id: \.id) { session in
                                                SessionCardView(session: session)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }

                Divider()
                    .background(Color.white.opacity(0.1))

                Button(action: onCollapse) {
                    Text("Show all \(sessionStore.sessions.count) sessions")
                        .font(theme.font(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func filterChip(provider: AIProvider?, label: String, count: Int, color: Color) -> some View {
        let isSelected = selectedProvider?.id == provider?.id
        Button(action: { selectedProvider = provider }) {
            HStack(spacing: 5) {
                if let p = provider {
                    Circle()
                        .fill(p.accentColor)
                        .frame(width: 6, height: 6)
                }
                Text(label)
                    .font(theme.font(size: 10, weight: .heavy))
                    .foregroundColor(isSelected ? color : color.opacity(0.55))
                    .kerning(0.8)
                Text("\(count)")
                    .font(theme.font(size: 9, weight: .bold))
                    .foregroundColor(isSelected ? color.opacity(0.85) : color.opacity(0.4))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .notchPill(theme, fill: isSelected ? color.opacity(0.14) : color.opacity(0.05), stroke: isSelected ? color.opacity(0.4) : nil, base: 6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sectionHeader(provider: AIProvider, count: Int, collapsed: Bool) -> some View {
        HStack(spacing: 8) {
            ProviderIcon(provider: provider, size: 14)
            Text(provider.displayName.uppercased())
                .font(theme.font(size: 9, weight: .heavy))
                .foregroundColor(provider.accentColor.opacity(0.85))
                .kerning(1.2)
            Text("(\(count))")
                .font(theme.font(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
                .rotationEffect(.degrees(collapsed ? 0 : 90))
        }
    }
}

/// Renders the provider's CLI icon from `Resources/cli-icons/<id>.png`, with a
/// monochrome circle fallback so it always renders even if the asset is missing.
struct ProviderIcon: View {
    let provider: AIProvider
    var size: CGFloat = 14

    var body: some View {
        if let image = Self.loadIcon(for: provider) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Circle()
                .fill(provider.accentColor)
                .frame(width: size, height: size)
        }
    }

    /// Look up `cli-icons/<id>.png` from the main bundle (SPM copies the directory in).
    /// We avoid `Bundle.module` (executable targets don't get it auto-generated)
    /// and just scan the main bundle's resource locations.
    private static let iconCache = IconCache()

    private static func loadIcon(for provider: AIProvider) -> NSImage? {
        iconCache.image(for: provider.id)
    }
}

/// In-memory icon cache backed by the main bundle's `cli-icons` directory.
final class IconCache {
    private var cache: [String: NSImage] = [:]
    private let lock = NSLock()

    func image(for id: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[id] { return cached }
        let bundle = Bundle.main
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates: [URL?] = [
            bundle.url(forResource: id, withExtension: "png", subdirectory: "cli-icons"),
            bundle.resourceURL?.appendingPathComponent("cli-icons/\(id).png"),
            bundle.bundleURL.appendingPathComponent("Contents/Resources/cli-icons/\(id).png"),
            // Dev fallback: project root Resources dir when running .build/debug/CodeIsland
            URL(fileURLWithPath: "\(home)/Projects/code-island/Resources/cli-icons/\(id).png"),
        ]
        for case let url? in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let image = NSImage(contentsOf: url) {
                cache[id] = image
                return image
            }
        }
        return nil
    }
}
