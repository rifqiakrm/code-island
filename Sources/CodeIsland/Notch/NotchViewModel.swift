import SwiftUI
import Combine

enum NotchState: Equatable {
    case collapsed
    case expanded
    case finished(sessionId: String)
    case permission(sessionId: String)
    case question(sessionId: String)
}

@MainActor
final class NotchViewModel: ObservableObject {
    // MARK: - Published State
    @Published var state: NotchState = .collapsed
    @Published var isHovered = false

    // MARK: - Dimensions
    // Vibe Island uses Y=0 (screen top) with large windows.
    // Heights INCLUDE the notch/menu bar overlap (~32pt on top).
    static let notchOverlap: CGFloat = ScreenDetector.hasNotch ? ScreenDetector.notchHeight : 0

    static let collapsedSize = NSSize(width: 280, height: ScreenDetector.hasNotch ? 34 : 5)
    // Expanded: compact, fits ~3 session cards
    static let expandedSize = NSSize(width: 520, height: 320)
    // Permission: wide enough for details
    static let permissionSize = NSSize(width: 520, height: 300)
    // Question: taller for multiple questions
    static let questionSize = NSSize(width: 520, height: 420)

    // Finished notification: compact, just one card
    static let finishedSize = NSSize(width: 520, height: 200)

    var currentSize: NSSize {
        switch state {
        case .collapsed:
            return Self.collapsedSize
        case .expanded:
            return Self.expandedSize
        case .finished:
            return Self.finishedSize
        case .permission:
            return Self.permissionSize
        case .question:
            return Self.questionSize
        }
    }

    var isExpanded: Bool {
        state != .collapsed
    }

    // MARK: - Auto-collapse
    private var autoCollapseTask: Task<Void, Never>?

    func expand(holdSeconds: Double? = nil) {
        guard state == .collapsed else { return }
        state = .expanded
        scheduleAutoCollapse(delay: holdSeconds ?? 0.6)
    }

    func collapse() {
        guard state != .collapsed else { return }
        state = .collapsed
        autoCollapseTask?.cancel()
    }

    func toggle() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }

    func showFinished(sessionId: String) {
        autoCollapseTask?.cancel()
        state = .finished(sessionId: sessionId)
        scheduleAutoCollapse(delay: 3.0)
    }

    func showPermission(sessionId: String) {
        autoCollapseTask?.cancel()
        state = .permission(sessionId: sessionId)
    }

    func dismissPermission() {
        state = .collapsed
    }

    func showQuestion(sessionId: String) {
        autoCollapseTask?.cancel()
        state = .question(sessionId: sessionId)
    }

    func dismissQuestion() {
        state = .collapsed
    }

    private func scheduleAutoCollapse(delay: Double = 0.6) {
        autoCollapseTask?.cancel()
        autoCollapseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            if !Task.isCancelled && isExpanded && !isHovered {
                collapse()
            }
        }
    }

    func mouseEntered() {
        isHovered = true
        // Don't cancel auto-collapse for finished notifications — they should always auto-dismiss
        if case .finished = state { return }
        autoCollapseTask?.cancel()
    }

    func mouseExited() {
        isHovered = false
        // Never auto-collapse permission or question states — user must respond
        switch state {
        case .permission, .question:
            return
        default:
            break
        }
        if isExpanded {
            scheduleAutoCollapse()
        }
    }
}
