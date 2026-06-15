import SwiftUI

/// Lightweight markdown renderer for agent replies in the notch. It is NOT a
/// full CommonMark engine — just enough to make replies read nicely in a small
/// space: fenced code blocks (```), `inline code`, **bold**, *italic*, [links],
/// and lightly-styled headers (# → bold) and bullet lists (-/*/+ → •).
struct MarkdownText: View {
    let text: String
    var color: Color = .white.opacity(0.9)
    var codeBackground: Color = .black.opacity(0.35)
    var fontSize: CGFloat = 11
    var codeFontSize: CGFloat = 10.5

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(Self.blocks(from: text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .code(let code):
                    Text(code)
                        .font(.system(size: codeFontSize, design: .monospaced))
                        .foregroundColor(color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(codeBackground))
                        .textSelection(.enabled)
                case .text(let md):
                    Text(Self.inline(md))
                        .font(.system(size: fontSize))
                        .foregroundColor(color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }

    enum Block { case code(String); case text(String) }

    /// Split into fenced-code blocks vs prose blocks.
    static func blocks(from text: String) -> [Block] {
        var blocks: [Block] = []
        var prose: [String] = []
        var code: [String] = []
        var inCode = false
        func flushProse() {
            let s = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { blocks.append(.text(s)) }
            prose = []
        }
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    blocks.append(.code(code.joined(separator: "\n")))
                    code = []; inCode = false
                } else {
                    flushProse(); inCode = true
                }
                continue
            }
            if inCode { code.append(line) } else { prose.append(line) }
        }
        if inCode, !code.isEmpty { blocks.append(.code(code.joined(separator: "\n"))) }
        flushProse()
        return blocks
    }

    /// Inline markdown (bold/italic/`code`/links) preserving line breaks. Headers
    /// and bullet markers are pre-converted since the inline parser leaves them
    /// literal. Used directly (capped) on glance cards too.
    static func inline(_ s: String) -> AttributedString {
        let prepped = s.split(separator: "\n", omittingEmptySubsequences: false).map { raw -> String in
            var line = String(raw)
            if let m = line.range(of: #"^\s{0,3}#{1,6}\s+"#, options: .regularExpression) {
                return "**" + line[m.upperBound...].trimmingCharacters(in: .whitespaces) + "**"
            }
            line = line.replacingOccurrences(of: #"^(\s*)[-*+]\s+"#, with: "$1• ", options: .regularExpression)
            return line
        }.joined(separator: "\n")
        var opts = AttributedString.MarkdownParsingOptions()
        opts.interpretedSyntax = .inlineOnlyPreservingWhitespace
        opts.failurePolicy = .returnPartiallyParsedIfPossible
        return (try? AttributedString(markdown: prepped, options: opts)) ?? AttributedString(s)
    }
}
