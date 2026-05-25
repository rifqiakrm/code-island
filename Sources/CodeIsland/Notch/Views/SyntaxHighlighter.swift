import SwiftUI

/// Lightweight regex-based syntax highlighter for code preview.
/// Targets Swift / common C-family languages; degrades gracefully for unknown content.
enum SyntaxHighlighter {
    struct Theme {
        let plain: Color
        let keyword: Color
        let type: Color
        let string: Color
        let number: Color
        let comment: Color
        let diffPlus: Color
        let diffMinus: Color
        let lineNumber: Color

        static let dark = Theme(
            plain: .white.opacity(0.85),
            keyword: Color(red: 1.0, green: 0.45, blue: 0.55),       // pink/red
            type: Color(red: 1.0, green: 0.82, blue: 0.40),          // yellow
            string: Color(red: 0.95, green: 0.65, blue: 0.50),       // peach
            number: Color(red: 0.55, green: 0.80, blue: 0.95),       // light blue
            comment: .white.opacity(0.35),
            diffPlus: Color(red: 0.55, green: 0.95, blue: 0.65),     // light green
            diffMinus: Color(red: 1.0, green: 0.55, blue: 0.55),     // light red
            lineNumber: .white.opacity(0.3)
        )
    }

    /// Common keywords across Swift, JS, Python, Go, etc.
    private static let keywords: Set<String> = [
        "let", "var", "const", "func", "function", "def", "fn",
        "return", "if", "else", "elif", "for", "while", "do",
        "switch", "case", "break", "continue", "default",
        "class", "struct", "enum", "protocol", "extension", "interface",
        "import", "from", "package", "module", "use",
        "private", "public", "internal", "fileprivate", "open", "static",
        "true", "false", "nil", "null", "None", "undefined",
        "self", "this", "super", "new", "in", "of", "as", "is", "try", "throws", "throw", "catch",
        "async", "await", "actor", "@MainActor", "weak", "guard", "where", "lazy",
        "typealias", "init", "deinit", "subscript", "override", "final",
    ]

    /// Build a syntax-highlighted AttributedString with optional line numbers.
    /// `startLine` controls the first line number shown (default 1).
    static func highlight(_ source: String, theme: Theme = .dark, withLineNumbers: Bool = true, startLine: Int = 1) -> AttributedString {
        var out = AttributedString(source)
        out.foregroundColor = theme.plain

        // Comments (line + block)
        applyRegex(#"//[^\n]*"#, to: &out, in: source, color: theme.comment)
        applyRegex(#"#[^\n]*"#, to: &out, in: source, color: theme.comment)
        applyRegex(#"/\*[\s\S]*?\*/"#, to: &out, in: source, color: theme.comment)

        // Strings (double, single, backtick)
        applyRegex(#""(?:[^"\\]|\\.)*""#, to: &out, in: source, color: theme.string)
        applyRegex(#"'(?:[^'\\]|\\.)*'"#, to: &out, in: source, color: theme.string)
        applyRegex(#"`(?:[^`\\]|\\.)*`"#, to: &out, in: source, color: theme.string)

        // Numbers
        applyRegex(#"\b\d+(?:\.\d+)?\b"#, to: &out, in: source, color: theme.number)

        // Capitalized identifiers as types
        applyRegex(#"\b[A-Z][A-Za-z0-9_]*\b"#, to: &out, in: source, color: theme.type)

        // Keywords (whole-word)
        let keywordPattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
        applyRegex(keywordPattern, to: &out, in: source, color: theme.keyword)

        if !withLineNumbers { return out }
        return prependLineNumbers(out, source: source, theme: theme, startLine: startLine)
    }

    /// Prefix each line with a right-aligned line number in muted color.
    private static func prependLineNumbers(_ attributed: AttributedString, source: String, theme: Theme, startLine: Int = 1) -> AttributedString {
        let lines = source.components(separatedBy: "\n")
        let maxNum = startLine + lines.count - 1
        let width = String(maxNum).count
        var result = AttributedString("")
        var charOffset = 0
        for (idx, line) in lines.enumerated() {
            let num = String(idx + startLine).leftPad(to: width)
            var prefix = AttributedString("\(num)  ")
            prefix.foregroundColor = theme.lineNumber
            result += prefix

            // Slice the corresponding portion of the highlighted attributed string
            let lineLen = line.count
            let startIdx = attributed.index(attributed.startIndex, offsetByCharacters: charOffset)
            let endIdx = attributed.index(startIdx, offsetByCharacters: lineLen)
            result += AttributedString(attributed[startIdx..<endIdx])
            charOffset += lineLen
            if idx < lines.count - 1 {
                result += AttributedString("\n")
                charOffset += 1  // skip the newline in source
            }
        }
        return result
    }

    /// Build a highlighted attributed string representing an Edit diff (old → new).
    /// `startLine` is the line number of the first line in `old` within the source file.
    static func diff(old: String, new: String, theme: Theme = .dark, startLine: Int = 1) -> AttributedString {
        var out = AttributedString("")
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")
        let maxNum = startLine + max(oldLines.count, newLines.count) - 1
        let width = String(maxNum).count

        for (idx, line) in oldLines.enumerated() {
            let num = String(idx + startLine).leftPad(to: width)
            var prefix = AttributedString("\(num) ")
            prefix.foregroundColor = theme.lineNumber
            out += prefix
            var marker = AttributedString("-  ")
            marker.foregroundColor = theme.diffMinus
            out += marker
            var s = AttributedString(line + "\n")
            s.foregroundColor = theme.diffMinus
            s.backgroundColor = theme.diffMinus.opacity(0.08)
            out += s
        }
        for (idx, line) in newLines.enumerated() {
            let num = String(idx + startLine).leftPad(to: width)
            var prefix = AttributedString("\(num) ")
            prefix.foregroundColor = theme.lineNumber
            out += prefix
            var marker = AttributedString("+  ")
            marker.foregroundColor = theme.diffPlus
            out += marker
            var s = AttributedString(line + "\n")
            s.foregroundColor = theme.diffPlus
            s.backgroundColor = theme.diffPlus.opacity(0.08)
            out += s
        }
        return out
    }

    /// Find the 1-based line number where `needle` starts inside the file at `path`.
    /// Returns 1 if the file can't be read or the needle isn't found.
    static func findStartLine(filePath: String, needle: String) -> Int {
        guard !needle.isEmpty,
              let contents = try? String(contentsOfFile: filePath, encoding: .utf8),
              let range = contents.range(of: needle) else { return 1 }
        let prefix = contents[..<range.lowerBound]
        return prefix.components(separatedBy: "\n").count
    }

}

private extension String {
    func leftPad(to width: Int) -> String {
        if count >= width { return self }
        return String(repeating: " ", count: width - count) + self
    }
}

extension SyntaxHighlighter {
    private static func applyRegex(_ pattern: String, to attributed: inout AttributedString, in source: String, color: Color) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: (source as NSString).length)
        let matches = regex.matches(in: source, range: range)
        for match in matches {
            guard let swiftRange = Range(match.range, in: source) else { continue }
            let lowerInt = source.distance(from: source.startIndex, to: swiftRange.lowerBound)
            let upperInt = source.distance(from: source.startIndex, to: swiftRange.upperBound)
            let attrStart = attributed.index(attributed.startIndex, offsetByCharacters: lowerInt)
            let attrEnd = attributed.index(attributed.startIndex, offsetByCharacters: upperInt)
            attributed[attrStart..<attrEnd].foregroundColor = color
        }
    }
}

