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
    // Computed properties so they re-evaluate when display parameters change.
    static var notchOverlap: CGFloat { ScreenDetector.hasNotch ? ScreenDetector.notchHeight : 0 }

    // Size adapts to the OS-reported notch cutout (safeAreaInsets.top + auxiliary
    // top areas). Width extends ~50pt beyond the notch on each side so the
    // mascot and session count have room. Height is notch height + small buffer.
    static var collapsedSize: NSSize {
        guard ScreenDetector.hasNotch else { return NSSize(width: 280, height: 5) }
        let width = max(280, ScreenDetector.notchWidth + 100)
        let height = ScreenDetector.notchHeight
        return NSSize(width: width, height: height)
    }
    // Expanded: compact, fits ~3 session cards
    static let expandedSize = NSSize(width: 600, height: 320)
    // Permission: wide enough for details
    static let permissionSize = NSSize(width: 600, height: 380)
    // Question: taller for multiple questions
    static let questionSize = NSSize(width: 600, height: 480)

    // Finished notification: compact, just one card
    static let finishedSize = NSSize(width: 600, height: 380)

    // Dynamic content height — set when showing permission/finished based on actual content
    @Published var dynamicPermissionHeight: CGFloat? = nil
    @Published var dynamicFinishedHeight: CGFloat? = nil

    var currentSize: NSSize {
        switch state {
        case .collapsed:
            return Self.collapsedSize
        case .expanded:
            return Self.expandedSize
        case .finished:
            return NSSize(width: 600, height: dynamicFinishedHeight ?? Self.finishedSize.height)
        case .permission:
            return NSSize(width: 600, height: dynamicPermissionHeight ?? Self.permissionSize.height)
        case .question:
            return Self.questionSize
        }
    }

    /// Compute the height needed for a permission view with the given content.
    static func computePermissionHeight(filePath: String?, contentLines: Int?, hasDescription: Bool) -> CGFloat {
        var h: CGFloat = 0
        h += 10 + 14   // top bar (rate limits/sound/gear) + spacing
        h += 12 + 22 + 10 // session header (mascot+title+badge) + spacing
        h += 22 + 10    // tool pill + subtitle row + spacing
        if filePath != nil {
            h += 30 + 8 // path row + spacing
        }
        if let lines = contentLines, lines > 0 {
            let bodyHeight = min(CGFloat(lines) * 14 + 20, 240)
            h += 24 + bodyHeight + 0 // content header + body
        } else if hasDescription {
            h += 24 + 50
        }
        h += 12 + 36 + 12 // spacer + buttons + bottom padding
        return min(max(h, 200), 600)
    }

    static func permissionHeight(for session: Session) -> CGFloat {
        guard let pending = session.pendingPermission else { return permissionSize.height }
        var contentLines: Int? = nil
        if let oldStr = pending.oldString, let newStr = pending.newString {
            contentLines = oldStr.components(separatedBy: "\n").count + newStr.components(separatedBy: "\n").count
        } else if let content = pending.content, !content.isEmpty {
            contentLines = estimateVisualLines(content)
        } else if pending.filePath == nil, let desc = pending.description, !desc.isEmpty {
            contentLines = estimateVisualLines(desc)
        }
        let hasDescription = (pending.description?.isEmpty == false) && pending.filePath == nil
        return computePermissionHeight(
            filePath: pending.filePath,
            contentLines: contentLines,
            hasDescription: hasDescription
        )
    }

    static func estimateVisualLinesPublic(_ text: String) -> Int {
        estimateVisualLines(text)
    }

    private static func estimateVisualLines(_ text: String) -> Int {
        let charsPerLine = 72
        var lines = 0
        for line in text.components(separatedBy: "\n") {
            lines += max(1, (line.count + charsPerLine - 1) / charsPerLine)
        }
        return lines
    }

    static func computeFinishedHeight(hasUser: Bool, replyLines: Int) -> CGFloat {
        var h: CGFloat = 0
        h += 10 + 14   // top bar
        h += 12 + 22 + 10 // session header
        h += 22 + 10    // tool pill (Done) row
        if hasUser {
            h += 30 + 8 // user row
        }
        if replyLines > 0 {
            let bodyHeight = min(CGFloat(replyLines) * 14 + 20, 260)
            h += 24 + bodyHeight
        }
        h += 12 + 36 + 12 // spacer + dismiss + bottom padding
        return min(max(h, 200), 600)
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

    func cancelAutoCollapse() {
        autoCollapseTask?.cancel()
    }

    func showFinished(sessionId: String, contentHeight: CGFloat? = nil) {
        autoCollapseTask?.cancel()
        dynamicFinishedHeight = contentHeight
        state = .finished(sessionId: sessionId)
        scheduleAutoCollapse(delay: 3.0)
    }

    func showPermission(sessionId: String, contentHeight: CGFloat? = nil) {
        autoCollapseTask?.cancel()
        dynamicPermissionHeight = contentHeight
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
            guard !Task.isCancelled, isExpanded else { return }
            if isHovered {
                // Re-arm with a short delay so the finished card eventually
                // collapses even if the cursor stays parked over the notch
                // (issue #27). Cap the total wait at ~15s as a hard ceiling.
                scheduleAutoCollapse(delay: 0.6)
            } else {
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
