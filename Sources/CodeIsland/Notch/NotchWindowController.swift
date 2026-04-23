import AppKit
import SwiftUI
import Combine

final class NotchWindowController: NSWindowController {
    private let viewModel: NotchViewModel
    private let sessionStore: SessionStore
    private let settingsStore: SettingsStore
    private let rateLimitStore: RateLimitStore
    private var cancellables = Set<AnyCancellable>()
    private var trackingArea: NSTrackingArea?

    init(sessionStore: SessionStore, settingsStore: SettingsStore, rateLimitStore: RateLimitStore) {
        self.sessionStore = sessionStore
        self.settingsStore = settingsStore
        self.rateLimitStore = rateLimitStore
        self.viewModel = NotchViewModel()

        let initialFrame = ScreenDetector.notchPanelFrame(
            panelSize: NotchViewModel.collapsedSize
        )
        let panel = NotchPanel(contentRect: initialFrame)
        super.init(window: panel)

        print("[CodeIsland] Notch screen: \(ScreenDetector.notchScreen.frame), hasNotch: \(ScreenDetector.hasNotch)")
        print("[CodeIsland] Panel frame: \(initialFrame)")

        let contentView = NotchContentView(
            viewModel: viewModel,
            sessionStore: sessionStore,
            rateLimitStore: rateLimitStore,
            settingsStore: settingsStore,
            onPermissionRespond: { [weak self] sessionId, action in
                self?.sessionStore.respondToPermission(sessionId: sessionId, action: action)
            },
            onOpenSettings: {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
        )

        // Set the hosting view as the panel's content view directly
        let hostingView = ClickThroughHostingView(rootView: contentView)
        panel.contentView = hostingView

        // Force the window to the front and make it visible
        panel.orderFrontRegardless()
        panel.isReleasedWhenClosed = false

        // Set level AFTER ordering front so it sticks above menu bar
        panel.applyNotchLevel()

        // Set frame AFTER ordering front, bypassing constraint
        let frame = ScreenDetector.notchPanelFrame(panelSize: NotchViewModel.collapsedSize)
        panel.setFrame(frame, display: true)
        Log.info("Panel frame after setFrame: \(panel.frame)")

        // Reposition window when state changes
        viewModel.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.repositionWindow()
            }
            .store(in: &cancellables)

        // Watch for display changes
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.repositionWindow()
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func handleSessionEvent(_ event: SessionEvent) {
        Task { @MainActor in
            switch event {
            case .permissionRequested(let sessionId):
                viewModel.showPermission(sessionId: sessionId)
            case .questionAsked(let sessionId):
                viewModel.showQuestion(sessionId: sessionId)
            case .statusChanged(let sessionId, let status) where status == .idle:
                // Claude finished — show focused notification card
                if !viewModel.isExpanded {
                    viewModel.showFinished(sessionId: sessionId)
                }
            default:
                break
            }
        }
    }

    private func repositionWindow() {
        guard let panel = window else { return }
        let newFrame = ScreenDetector.notchPanelFrame(panelSize: viewModel.currentSize)
        panel.setFrame(newFrame, display: true, animate: true)
    }
}
