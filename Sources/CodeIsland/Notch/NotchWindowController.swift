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

        // Reposition when dynamic content height changes (e.g. expand button)
        Publishers.CombineLatest(viewModel.$dynamicPermissionHeight, viewModel.$dynamicFinishedHeight)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
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
            // If the user is mid-decision on another prompt, leave the UI
            // alone — the queue drain after they respond will pick the next
            // pending one (sorted by enqueue time). Swapping mid-tap races
            // the button and applies the wrong decision to the wrong session
            // (issue #7).
            let isAlreadyDeciding: Bool = {
                if case .permission = viewModel.state { return true }
                if case .question = viewModel.state { return true }
                return false
            }()

            switch event {
            case .permissionRequested(let sessionId):
                guard !isAlreadyDeciding else { return }
                let height = computePermissionHeight(sessionId: sessionId)
                viewModel.showPermission(sessionId: sessionId, contentHeight: height)
            case .questionAsked(let sessionId):
                guard !isAlreadyDeciding else { return }
                viewModel.showQuestion(sessionId: sessionId)
            case .statusChanged(let sessionId, let status) where status == .idle:
                // Claude finished — show focused notification card
                if !viewModel.isExpanded {
                    let height = computeFinishedHeight(sessionId: sessionId)
                    viewModel.showFinished(sessionId: sessionId, contentHeight: height)
                }
            case .pendingDismissedExternally(let sessionId):
                // Permission/question was answered in the terminal — dismiss the notch
                switch viewModel.state {
                case .permission(let id) where id == sessionId,
                     .question(let id) where id == sessionId:
                    // Show next pending if any, else collapse
                    if let next = sessionStore.nextPendingPermission() {
                        let h = sessionStore.sessions[next].map { NotchViewModel.permissionHeight(for: $0) }
                        viewModel.showPermission(sessionId: next, contentHeight: h)
                    } else if let next = sessionStore.nextPendingQuestion() {
                        viewModel.showQuestion(sessionId: next)
                    } else {
                        viewModel.collapse()
                    }
                default:
                    break
                }
            default:
                break
            }
        }
    }

    private var animationDisplayLink: CADisplayLink?
    private var animationStart: CFTimeInterval = 0
    private var animationDuration: TimeInterval = 0.32
    private var animationStartSize: NSSize = .zero
    private var animationDeltaW: CGFloat = 0
    private var animationDeltaH: CGFloat = 0

    private func repositionWindow() {
        guard let panel = window else { return }
        let target = viewModel.currentSize
        // Always snap the window to the (possibly new) notch screen's
        // top-center first. Without this, a resolution change that
        // doesn't alter our panel size leaves the window pinned at its
        // old absolute coordinates — i.e. off-screen on the new
        // resolution. Then run the size animation as usual.
        let screen = ScreenDetector.notchScreen.frame
        let cur = panel.frame.size
        let x = screen.midX - cur.width / 2
        let y = screen.maxY - cur.height
        panel.setFrame(NSRect(x: x, y: y, width: cur.width, height: cur.height), display: true)
        animatePanelToSize(target, duration: 0.32)
    }

    /// Display-link-driven frame animation. Stays in lock-step with the
    /// screen's vsync (typically 60–120Hz depending on display) so we never
    /// schedule a frame the compositor can't show. Previously this was a
    /// `Timer.scheduledTimer` at 60Hz with `display: true`, which forced
    /// synchronous full-window redraws and could jank when anything else
    /// touched the main thread mid-expand.
    private func animatePanelToSize(_ targetSize: NSSize, duration: TimeInterval) {
        guard let panel = window else { return }
        animationDisplayLink?.invalidate()
        animationDisplayLink = nil

        let startSize = panel.frame.size
        let dw = targetSize.width - startSize.width
        let dh = targetSize.height - startSize.height
        if abs(dw) < 0.5 && abs(dh) < 0.5 { return }

        animationStart = CACurrentMediaTime()
        animationDuration = duration
        animationStartSize = startSize
        animationDeltaW = dw
        animationDeltaH = dh

        let link = panel.displayLink(target: self, selector: #selector(stepAnimation(_:)))
        link.add(to: .main, forMode: .common)
        animationDisplayLink = link
    }

    @objc private func stepAnimation(_ link: CADisplayLink) {
        guard let panel = window else {
            link.invalidate()
            animationDisplayLink = nil
            return
        }
        let elapsed = CACurrentMediaTime() - animationStart
        let t = min(elapsed / animationDuration, 1.0)
        // Smooth ease-out cubic — fast start, gentle settle
        let eased = 1.0 - pow(1.0 - t, 3.0)
        let w = animationStartSize.width + animationDeltaW * eased
        let h = animationStartSize.height + animationDeltaH * eased
        let screen = ScreenDetector.notchScreen.frame
        // Anchor TOP edge to screen top, expand width from center
        let x = screen.midX - w / 2
        let y = screen.maxY - h
        // `display: false` lets Core Animation coalesce drawing — the
        // compositor still paints in sync with the next vsync.
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: false)
        if t >= 1.0 {
            link.invalidate()
            animationDisplayLink = nil
        }
    }

    private func computePermissionHeight(sessionId: String) -> CGFloat {
        guard let session = sessionStore.sessions[sessionId],
              let pending = session.pendingPermission else {
            return NotchViewModel.permissionSize.height
        }
        let filePath = pending.filePath
        var contentLines: Int? = nil
        if let oldStr = pending.oldString, let newStr = pending.newString {
            contentLines = oldStr.components(separatedBy: "\n").count + newStr.components(separatedBy: "\n").count
        } else if let content = pending.content, !content.isEmpty {
            contentLines = estimateVisualLines(content)
        } else if filePath == nil, let desc = pending.description, !desc.isEmpty {
            // Bash command (or other) — estimate wrapped lines from char width
            contentLines = estimateVisualLines(desc)
        }
        let hasDescription = (pending.description?.isEmpty == false) && filePath == nil
        return NotchViewModel.computePermissionHeight(
            filePath: filePath,
            contentLines: contentLines,
            hasDescription: hasDescription
        )
    }

    /// Estimate the number of rendered lines accounting for wrap at ~72 chars
    /// (600pt window width minus padding/line numbers, 11pt monospaced font).
    private func estimateVisualLines(_ text: String) -> Int {
        let charsPerLine = 72
        var lines = 0
        for line in text.components(separatedBy: "\n") {
            lines += max(1, (line.count + charsPerLine - 1) / charsPerLine)
        }
        return lines
    }

    private func computeFinishedHeight(sessionId: String) -> CGFloat {
        guard let session = sessionStore.sessions[sessionId] else {
            return NotchViewModel.finishedSize.height
        }
        let hasUser = session.lastUserMessage != nil
        let replyLines = session.lastAssistantMessage.map { estimateVisualLines($0) } ?? 0
        return NotchViewModel.computeFinishedHeight(hasUser: hasUser, replyLines: replyLines)
    }
}
