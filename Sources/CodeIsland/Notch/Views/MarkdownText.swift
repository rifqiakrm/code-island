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
                case .table(let headers, let rows):
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                        GridRow {
                            ForEach(headers.indices, id: \.self) { i in
                                Text(Self.inline(headers[i])).bold()
                            }
                        }
                        Divider().background(color.opacity(0.25))
                        ForEach(rows.indices, id: \.self) { r in
                            GridRow {
                                ForEach(rows[r].indices, id: \.self) { c in
                                    Text(Self.inline(rows[r][c]))
                                }
                            }
                        }
                    }
                    .font(.system(size: fontSize))
                    .foregroundColor(color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(codeBackground.opacity(0.5)))
                case .header(let level, let title):
                    Text(Self.inline(title))
                        .font(.system(size: Self.headerSize(level, base: fontSize), weight: .bold))
                        .foregroundColor(color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, level <= 2 ? 2 : 0)
                        .textSelection(.enabled)
                case .quote(let q):
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(color.opacity(0.4))
                            .frame(width: 3)
                        Text(Self.inline(q))
                            .font(.system(size: fontSize))
                            .foregroundColor(color.opacity(0.75))
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private static func headerSize(_ level: Int, base: CGFloat) -> CGFloat {
        switch level {
        case 1: return base + 6   // 17 at base 11
        case 2: return base + 3.5
        case 3: return base + 2
        default: return base + 1
        }
    }

    enum Block {
        case code(String)
        case text(String)
        case table(headers: [String], rows: [[String]])
        case header(level: Int, text: String)
        case quote(String)
    }

    /// Split into fenced-code blocks vs prose blocks.
    static func blocks(from text: String) -> [Block] {
        var blocks: [Block] = []
        var prose: [String] = []
        var code: [String] = []
        var inCode = false
        func flushProse() {
            blocks.append(contentsOf: proseBlocks(prose))
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

    /// Split prose lines into paragraphs and pipe-tables.
    static func proseBlocks(_ lines: [String]) -> [Block] {
        var out: [Block] = []
        var para: [String] = []
        func flushPara() {
            let s = para.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { out.append(.text(s)) }
            para = []
        }
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // A table = a row with "|" immediately followed by a |---|--- separator.
            if line.contains("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flushPara()
                let headers = tableCells(line)
                var rows: [[String]] = []
                i += 2
                while i < lines.count,
                      lines[i].contains("|"),
                      !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(tableCells(lines[i]))
                    i += 1
                }
                out.append(.table(headers: headers, rows: rows))
                continue
            }
            // ATX header (#, ##, …) → its own sized block.
            if let r = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                flushPara()
                let level = trimmed.prefix(while: { $0 == "#" }).count
                out.append(.header(level: level, text: String(trimmed[r.upperBound...])))
                i += 1
                continue
            }
            // Blockquote — consume consecutive `>` lines.
            if trimmed.hasPrefix(">") {
                flushPara()
                var quoted: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var q = lines[i].trimmingCharacters(in: .whitespaces)
                    q.removeFirst()                              // drop leading ">"
                    quoted.append(q.trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                out.append(.quote(quoted.joined(separator: "\n")))
                continue
            }
            para.append(line)
            i += 1
        }
        flushPara()
        return out
    }

    private static func isTableSeparator(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.allSatisfy({ "|-: ".contains($0) }) else { return false }
        return t.contains("|") || t.filter({ $0 == "-" }).count >= 3
    }

    private static func tableCells(_ line: String) -> [String] {
        var parts = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.first == "" { parts.removeFirst() }
        if parts.last == "" { parts.removeLast() }
        return parts
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
            // Task list: `- [x]` / `- [ ]` → ☑ / ☐ (check before the bullet rule).
            if let r = line.range(of: #"^(\s*)[-*+]\s+\[[ xX]\]\s+"#, options: .regularExpression) {
                let indent = line.prefix(while: { $0 == " " })
                let checked = line.contains("[x]") || line.contains("[X]")
                return indent + (checked ? "☑ " : "☐ ") + String(line[r.upperBound...])
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
