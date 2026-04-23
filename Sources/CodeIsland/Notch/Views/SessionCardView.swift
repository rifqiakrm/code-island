import SwiftUI

struct SessionCardView: View {
    let session: Session
    var onDone: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: mascot + project · prompt + badges + time
            HStack(spacing: 8) {
                SessionMascot(status: session.status, size: 3.0)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(session.projectName)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                        if let prompt = session.firstPrompt ?? session.lastUserMessage {
                            Text("·")
                                .foregroundColor(.white.opacity(0.3))
                            Text(prompt)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }

                    // Brief status line
                    if session.status == .thinking || session.status == .toolUse {
                        HStack(spacing: 4) {
                            Text("You:")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                            if let msg = session.lastUserMessage {
                                Text(msg)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                        }
                    }

                    if let resp = session.lastAssistantMessage, session.status == .idle || session.status == .completed {
                        Text(resp)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                // Badges
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        BadgePill(text: "Claude", color: .orange)
                        BadgePill(text: session.detectedTerminalApp, color: .blue)
                        Text(session.durationText)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Thinking indicator
            if session.status == .thinking || session.status == .toolUse {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text(session.status == .toolUse ? (session.currentTool ?? "Working...") : "Thinking...")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.8))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            // Finished: show last exchange in highlighted sub-card
            if session.status == .idle, session.lastUserMessage != nil || session.lastAssistantMessage != nil {
                VStack(alignment: .leading, spacing: 4) {
                    // User message + floating Done on same line
                    HStack(alignment: .top) {
                        if let msg = session.lastUserMessage {
                            HStack(spacing: 4) {
                                Text("You:")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                                Text(msg)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Button(action: { onDone?() }) {
                            Text("Done")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(.white.opacity(0.12))
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Assistant response below — scrollable
                    if let resp = session.lastAssistantMessage {
                        ScrollView {
                            Text(resp)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 80)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.04))
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.04))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            TerminalJumper.jump(to: session)
        }
    }
}

struct BadgePill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.opacity(0.15))
            )
    }
}
