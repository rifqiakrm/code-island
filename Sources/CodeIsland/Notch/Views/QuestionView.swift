import SwiftUI

struct QuestionView: View {
    let session: Session
    let question: PendingQuestion
    let onSubmit: (String) -> Void
    let onDeferToTerminal: () -> Void
    @ObservedObject var rateLimitStore: RateLimitStore
    @ObservedObject var settingsStore: SettingsStore
    let onOpenSettings: () -> Void

    @State private var selections: [String: Set<String>] = [:]
    @State private var customAnswers: [String: String] = [:]
    @State private var showWarning = false
    @FocusState private var inputFocused: Bool

    private var hasAnyAnswer: Bool {
        question.questions.allSatisfy { q in
            !(selections[q.id] ?? []).isEmpty || !(customAnswers[q.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar: rate limits + controls
            HStack(spacing: 10) {
                RateLimitBar(rateLimitStore: rateLimitStore)
                Spacer()
                Button(action: { settingsStore.soundEnabled.toggle() }) {
                    Image(systemName: settingsStore.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(settingsStore.soundEnabled ? 0.6 : 0.3))
                }
                .buttonStyle(.plain)
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Session header + waiting badge
            HStack(spacing: 8) {
                SessionMascot(status: .waitingPermission, size: 18)
                Text(session.displayName)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 9))
                    Text("Waiting for answer")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(.pink)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.pink.opacity(0.15))
                )
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(question.questions.enumerated()), id: \.element.id) { index, q in
                        questionBlock(q: q, index: index)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }

            Divider().background(Color.white.opacity(0.08))

            // Bottom action row
            VStack(spacing: 8) {
                if showWarning && !hasAnyAnswer {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("Pick an option or type a custom answer")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }

                HStack(spacing: 10) {
                    Button(action: onDeferToTerminal) {
                        HStack(spacing: 7) {
                            Image(systemName: "terminal")
                                .font(.system(size: 12))
                            Text("Answer in terminal")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: submit) {
                        HStack(spacing: 7) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 11))
                            Text("Submit Answer")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(hasAnyAnswer ? .black : .white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(hasAnyAnswer ? Color.cyan : Color.white.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func questionBlock(q: QuestionItem, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Question text
            Text(q.question)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(3)

            // Counter chip
            HStack(spacing: 5) {
                Text("\(index + 1) / \(question.questions.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                Text("·")
                    .foregroundColor(.white.opacity(0.2))
                Text(q.multiSelect ? "multi select" : "single select")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white.opacity(0.05))
            )

            // Option pills
            FlowLayout(spacing: 6) {
                ForEach(q.options) { option in
                    let isSelected = selections[q.id]?.contains(option.id) ?? false

                    Button(action: {
                        toggleSelection(questionId: q.id, optionId: option.id, multiSelect: q.multiSelect)
                    }) {
                        HStack(spacing: 5) {
                            if isSelected {
                                Image(systemName: q.multiSelect ? "checkmark.square.fill" : "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            Text(option.label)
                                .font(.system(size: 11, weight: isSelected ? .bold : .regular, design: .monospaced))
                        }
                        .foregroundColor(isSelected ? .cyan : .white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(isSelected ? Color.cyan.opacity(0.12) : Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(isSelected ? Color.cyan.opacity(0.7) : Color.white.opacity(0.12), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // "or type your own" divider
            HStack(spacing: 10) {
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(height: 1)
                Text("or type your own")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .kerning(0.3)
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(height: 1)
            }
            .padding(.top, 4)

            // Text input
            HStack(spacing: 8) {
                Text("›")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.7))
                TextField("", text: Binding(
                    get: { customAnswers[q.id] ?? "" },
                    set: { customAnswers[q.id] = $0; showWarning = false }
                ), prompt: Text("Type a custom answer...").foregroundColor(.white.opacity(0.3)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .focused($inputFocused)
                    .onSubmit { submit() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    )
            )
        }
    }

    private func toggleSelection(questionId: String, optionId: String, multiSelect: Bool) {
        // Selecting a pill clears the custom answer for that question
        customAnswers[questionId] = ""
        if multiSelect {
            var current = selections[questionId] ?? []
            if current.contains(optionId) {
                current.remove(optionId)
            } else {
                current.insert(optionId)
            }
            selections[questionId] = current
        } else {
            selections[questionId] = [optionId]
        }
        showWarning = false
    }

    private func submit() {
        guard hasAnyAnswer else {
            showWarning = true
            return
        }
        // For each question, prefer custom answer if non-empty, else joined selections
        let combined = question.questions.map { q -> String in
            let custom = (customAnswers[q.id] ?? "").trimmingCharacters(in: .whitespaces)
            if !custom.isEmpty { return custom }
            return (selections[q.id] ?? []).joined(separator: ", ")
        }.joined(separator: "|")
        onSubmit(combined)
    }
}

/// Simple horizontal flow layout for pills
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
