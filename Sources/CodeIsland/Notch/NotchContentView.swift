import SwiftUI

struct NotchContentView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var rateLimitStore: RateLimitStore
    @ObservedObject var settingsStore: SettingsStore
    let onPermissionRespond: (String, PermissionAction) -> Void
    let onOpenSettings: () -> Void

    private var theme: NotchTheme { settingsStore.notchThemeID.theme }

    /// The backdrop spider's lenses double as a status readout, so they reflect
    /// the *worst* thing happening across every session — errors outrank pending
    /// approvals, which outrank work in progress.
    private var spiderLens: SpiderLens {
        let statuses = sessionStore.activeSessions.values.map(\.status)
        if statuses.contains(.error) { return .symbiote }
        if statuses.contains(.waitingPermission) { return .alarmed }
        if statuses.contains(.thinking) || statuses.contains(.toolUse) { return .narrow }
        return .wide
    }

    var body: some View {
        ZStack {
            NotchBackground(
                theme: theme,
                isExpanded: viewModel.isExpanded,
                cornerRadius: viewModel.isExpanded ? 20 : 17,
                drawBorder: false,
                creatureLens: spiderLens,
                // Legs only twitch while something is actually running — an idle
                // notch stays perfectly still (this is a transparent overlay, so
                // every animated frame recomposites the whole window area).
                creatureAnimates: spiderLens == .narrow
            )

            content
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(NotchShape(cornerRadius: viewModel.isExpanded ? 20 : 14))
        // Window edge border ON TOP of the content so cards/wells that reach the
        // panel bottom tuck under it instead of spilling over the rounded edge
        // (z-order fix — most visible with the thick Pixel/Brutalist borders).
        .overlay {
            if viewModel.isExpanded, theme.windowStroke != nil {
                NotchBorderShape(cornerRadius: viewModel.isExpanded ? 20 : 14)
                    .stroke(theme.windowStroke ?? .clear, lineWidth: theme.windowStrokeWidth * 2)
            }
        }
        .environment(\.notchTheme, theme)
        .onHover { hovering in
            if hovering {
                viewModel.mouseEntered()
                if case .collapsed = viewModel.state {
                    // Surface a pending plan/permission/question first, else expand
                    if !showNextPending() { viewModel.expand() }
                }
            } else {
                viewModel.mouseExited()
            }
        }
    }

    /// Surface the next queued decision (oldest-first): a plan routes to PlanView,
    /// a regular permission to PermissionView, otherwise a question. Returns false
    /// when nothing is pending so callers can fall back (collapse / expand).
    @discardableResult
    private func showNextPending() -> Bool {
        let store = sessionStore
        if let next = store.nextPendingPermission() {
            if store.sessions[next]?.pendingPermission?.isPlan == true {
                viewModel.showPlan(sessionId: next)
            } else {
                let h = store.sessions[next].map { NotchViewModel.permissionHeight(for: $0) }
                viewModel.showPermission(sessionId: next, contentHeight: h)
            }
            return true
        } else if let next = store.nextPendingQuestion() {
            viewModel.showQuestion(sessionId: next)
            return true
        }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .collapsed:
            CollapsedNotchView(sessionStore: sessionStore, rateLimitStore: rateLimitStore)

        case .expanded:
            SessionListView(
                sessionStore: sessionStore,
                rateLimitStore: rateLimitStore,
                settingsStore: settingsStore,
                onCollapse: { viewModel.collapse() },
                onOpenSettings: onOpenSettings
            )

        case .finished(let sessionId):
            if let session = sessionStore.sessions[sessionId] {
                FinishedView(
                    session: session,
                    onDismiss: { viewModel.collapse() },
                    rateLimitStore: rateLimitStore,
                    settingsStore: settingsStore,
                    onOpenSettings: onOpenSettings,
                    onToggleExpand: { expanded in
                        if expanded {
                            viewModel.cancelAutoCollapse()
                            viewModel.dynamicFinishedHeight = 560
                        } else {
                            let hasUser = session.lastUserMessage != nil
                            let replyLines = session.lastAssistantMessage.map { NotchViewModel.estimateVisualLinesPublic($0) } ?? 0
                            viewModel.dynamicFinishedHeight = NotchViewModel.computeFinishedHeight(hasUser: hasUser, replyLines: replyLines)
                        }
                    }
                )
            } else {
                CollapsedNotchView(sessionStore: sessionStore, rateLimitStore: rateLimitStore)
            }

        case .permission(let sessionId):
            if let session = sessionStore.sessions[sessionId],
               let pending = session.pendingPermission {
                PermissionView(
                    session: session,
                    permission: pending,
                    onRespond: { action in
                        onPermissionRespond(sessionId, action)
                        if !showNextPending() { viewModel.dismissPermission() }
                    },
                    rateLimitStore: rateLimitStore,
                    settingsStore: settingsStore,
                    onOpenSettings: onOpenSettings,
                    onToggleExpand: { expanded in
                        // Expanded mode = give the window enough room for the bigger ScrollView
                        if expanded {
                            viewModel.dynamicPermissionHeight = 560
                        } else if let s = sessionStore.sessions[sessionId] {
                            viewModel.dynamicPermissionHeight = NotchViewModel.permissionHeight(for: s)
                        }
                    }
                )
            } else {
                CollapsedNotchView(sessionStore: sessionStore, rateLimitStore: rateLimitStore)
            }

        case .plan(let sessionId):
            if let session = sessionStore.sessions[sessionId],
               let pending = session.pendingPermission, pending.isPlan {
                PlanView(
                    session: session,
                    permission: pending,
                    onRespond: { action in
                        onPermissionRespond(sessionId, action)
                        if !showNextPending() { viewModel.dismissPlan() }
                    },
                    rateLimitStore: rateLimitStore,
                    settingsStore: settingsStore,
                    onOpenSettings: onOpenSettings
                )
            } else {
                CollapsedNotchView(sessionStore: sessionStore, rateLimitStore: rateLimitStore)
            }

        case .question(let sessionId):
            if let session = sessionStore.sessions[sessionId],
               let question = session.pendingQuestion {
                QuestionView(
                    session: session,
                    question: question,
                    onSubmit: { answers in
                        sessionStore.respondToQuestion(sessionId: sessionId, answersByQuestionId: answers)
                        if !showNextPending() { viewModel.dismissQuestion() }
                    },
                    onDeferToTerminal: {
                        sessionStore.deferQuestionToTerminal(sessionId: sessionId)
                        if !showNextPending() { viewModel.dismissQuestion() }
                    },
                    rateLimitStore: rateLimitStore,
                    settingsStore: settingsStore,
                    onOpenSettings: onOpenSettings
                )
            } else {
                CollapsedNotchView(sessionStore: sessionStore, rateLimitStore: rateLimitStore)
            }
        }
    }
}
