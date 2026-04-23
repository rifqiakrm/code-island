import SwiftUI

struct QuestionView: View {
    let session: Session
    let question: PendingQuestion
    let onSubmit: (String) -> Void
    @ObservedObject var rateLimitStore: RateLimitStore

    @State private var selections: [String: Set<String>] = [:]
    @State private var showWarning = false

    var allAnswered: Bool {
        question.questions.allSatisfy { q in
            !(selections[q.id] ?? []).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                RateLimitBar(rateLimitStore: rateLimitStore)
                Spacer()
            }
            .padding(.top, 8)
            .padding(.horizontal, 10)

            // Session header
            HStack(spacing: 8) {
                SessionMascot(status: .waitingPermission, size: 3.0)

                Text(session.projectName)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)

                if let prompt = session.firstPrompt {
                    Text("·")
                        .foregroundColor(.white.opacity(0.3))
                    Text(prompt)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 4) {
                    BadgePill(text: "Claude", color: .orange)
                    BadgePill(text: session.detectedTerminalApp, color: .blue)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Last user message
            if let userMsg = session.lastUserMessage {
                HStack(spacing: 4) {
                    Text("You:")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    Text(userMsg)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }

            // Question banner
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.purple)
                Text("Claude's Question")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.purple)
                Text("(\(question.questions.count) questions)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.purple.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.purple.opacity(0.08))

            // All questions with pill options
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(question.questions.enumerated()), id: \.element.id) { index, q in
                        VStack(alignment: .leading, spacing: 6) {
                            // Question number + text
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(index + 1).")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.6))
                                Text(q.question)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.9))
                            }

                            // Multi-select badge
                            if q.multiSelect {
                                Text("Multi-select")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(.orange.opacity(0.15))
                                    )
                            }

                            // Pill options (horizontal wrap)
                            FlowLayout(spacing: 6) {
                                ForEach(q.options) { option in
                                    let isSelected = selections[q.id]?.contains(option.id) ?? false

                                    Button(action: {
                                        toggleSelection(questionId: q.id, optionId: option.id, multiSelect: q.multiSelect)
                                    }) {
                                        HStack(spacing: 4) {
                                            if q.multiSelect {
                                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(isSelected ? .green : .white.opacity(0.4))
                                            }
                                            Text(option.label)
                                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular, design: .monospaced))
                                                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(isSelected ? Color.purple.opacity(0.5) : Color.white.opacity(0.08))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(isSelected ? Color.purple.opacity(0.8) : Color.clear, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            // Submit button
            VStack(spacing: 4) {
                if showWarning && !allAnswered {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("Please answer all questions")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }

                Button(action: {
                    if allAnswered {
                        let combined = question.questions.map { q in
                            (selections[q.id] ?? []).joined(separator: ", ")
                        }.joined(separator: "|")
                        onSubmit(combined)
                    } else {
                        showWarning = true
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 12))
                        Text("Submit All Answers")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(allAnswered ? .white : .white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(allAnswered ? Color.purple.opacity(0.5) : Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleSelection(questionId: String, optionId: String, multiSelect: Bool) {
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
