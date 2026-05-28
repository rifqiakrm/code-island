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
    /// Strips common prefix/suffix lines (unchanged context) so only the actual
    /// removed/added lines are colored. Context lines appear in neutral plain text.
    /// `startLine` is the line number of the first line in `old` within the source file.
    static func diff(old: String, new: String, theme: Theme = .dark, startLine: Int = 1) -> AttributedString {
        var out = AttributedString("")
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")

        // Find longest common prefix
        var prefixCount = 0
        while prefixCount < oldLines.count, prefixCount < newLines.count,
              oldLines[prefixCount] == newLines[prefixCount] {
            prefixCount += 1
        }
        // Find longest common suffix (not overlapping with prefix)
        var suffixCount = 0
        while suffixCount < (oldLines.count - prefixCount),
              suffixCount < (newLines.count - prefixCount),
              oldLines[oldLines.count - 1 - suffixCount] == newLines[newLines.count - 1 - suffixCount] {
            suffixCount += 1
        }

        let oldMiddle = Array(oldLines[prefixCount..<(oldLines.count - suffixCount)])
        let newMiddle = Array(newLines[prefixCount..<(newLines.count - suffixCount)])
        let prefixLines = Array(oldLines[0..<prefixCount])
        let suffixLines = Array(oldLines[(oldLines.count - suffixCount)...])

        let maxNum = startLine + max(oldLines.count, newLines.count) - 1
        let width = String(maxNum).count

        // Show context prefix
        for (idx, line) in prefixLines.enumerated() {
            out += diffLine(line, number: idx + startLine, width: width,
                            marker: " ", accentColor: theme.plain, bgOpacity: 0, theme: theme)
        }
        // Show removed middle
        for (idx, line) in oldMiddle.enumerated() {
            out += diffLine(line, number: idx + startLine + prefixCount, width: width,
                            marker: "-", accentColor: theme.diffMinus, bgOpacity: 0.10, theme: theme)
        }
        // Show added middle (numbered relative to NEW file)
        for (idx, line) in newMiddle.enumerated() {
            out += diffLine(line, number: idx + startLine + prefixCount, width: width,
                            marker: "+", accentColor: theme.diffPlus, bgOpacity: 0.10, theme: theme)
        }
        // Show context suffix (numbered relative to NEW file, after the new middle lines)
        let suffixStart = startLine + prefixCount + newMiddle.count
        for (idx, line) in suffixLines.enumerated() {
            out += diffLine(line, number: idx + suffixStart, width: width,
                            marker: " ", accentColor: theme.plain, bgOpacity: 0, theme: theme)
        }
        return out
    }

    /// Build a single diff line: syntax-highlighted code with diff bg + prefix.
    private static func diffLine(_ line: String, number: Int, width: Int, marker: String, accentColor: Color, bgOpacity: Double, theme: Theme) -> AttributedString {
        var out = AttributedString("")

        // Line number prefix (no bg)
        let num = String(number).leftPad(to: width)
        var numPart = AttributedString("\(num) ")
        numPart.foregroundColor = theme.lineNumber
        out += numPart

        // Marker (-/+) tinted with accent, no bg
        var markerPart = AttributedString("\(marker)  ")
        markerPart.foregroundColor = accentColor
        out += markerPart

        // Syntax-highlight the line, then apply diff background
        var lineAttr = highlight(line, theme: theme, withLineNumbers: false)
        lineAttr.backgroundColor = accentColor.opacity(bgOpacity)
        out += lineAttr

        out += AttributedString("\n")
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

