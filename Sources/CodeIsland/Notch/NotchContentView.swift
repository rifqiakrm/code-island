import SwiftUI

struct NotchContentView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var rateLimitStore: RateLimitStore
    @ObservedObject var settingsStore: SettingsStore
    let onPermissionRespond: (String, PermissionAction) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            NotchBackground(
                isExpanded: viewModel.isExpanded,
                cornerRadius: viewModel.isExpanded ? 20 : 17
            )

            content
                .clipped()
        }
        .frame(
            width: viewModel.currentSize.width,
            height: viewModel.currentSize.height
        )
        .clipShape(NotchShape(cornerRadius: viewModel.isExpanded ? 20 : 14))
        .shadow(color: .black.opacity(0.4), radius: viewModel.isExpanded ? 16 : 6, y: 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.state)
        .onHover { hovering in
            if hovering {
                viewModel.mouseEntered()
                if case .collapsed = viewModel.state {
                    // Check for pending permissions/questions first
                    let store = sessionStore
                    if let pending = store.nextPendingPermission() {
                        let h = store.sessions[pending].map { NotchViewModel.permissionHeight(for: $0) }
                        viewModel.showPermission(sessionId: pending, contentHeight: h)
                    } else if let pending = store.nextPendingQuestion() {
                        viewModel.showQuestion(sessionId: pending)
                    } else {
                        viewModel.expand()
                    }
                }
            } else {
                viewModel.mouseExited()
            }
        }
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
                    onOpenSettings: onOpenSettings
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
                        let store = sessionStore
                        if let next = store.nextPendingPermission() {
                            let h = store.sessions[next].map { NotchViewModel.permissionHeight(for: $0) }
                            viewModel.showPermission(sessionId: next, contentHeight: h)
                        } else if let next = store.nextPendingQuestion() {
                            viewModel.showQuestion(sessionId: next)
                        } else {
                            viewModel.dismissPermission()
                        }
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
                        sessionStore.respondToQuestion(sessionId: sessionId, answer: answers)
                        let store = sessionStore
                        if let next = store.nextPendingPermission() {
                            let h = store.sessions[next].map { NotchViewModel.permissionHeight(for: $0) }
                            viewModel.showPermission(sessionId: next, contentHeight: h)
                        } else if let next = store.nextPendingQuestion() {
                            viewModel.showQuestion(sessionId: next)
                        } else {
                            viewModel.dismissQuestion()
                        }
                    },
                    onDeferToTerminal: {
                        sessionStore.deferQuestionToTerminal(sessionId: sessionId)
                        let store = sessionStore
                        if let next = store.nextPendingPermission() {
                            let h = store.sessions[next].map { NotchViewModel.permissionHeight(for: $0) }
                            viewModel.showPermission(sessionId: next, contentHeight: h)
                        } else if let next = store.nextPendingQuestion() {
                            viewModel.showQuestion(sessionId: next)
                        } else {
                            viewModel.dismissQuestion()
                        }
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
