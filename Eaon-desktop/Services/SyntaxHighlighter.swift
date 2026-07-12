import SwiftUI

/// A lightweight, dependency-free syntax highlighter — a keyword table plus
/// a single generic tokenizer shared across every language, not a full
/// grammar/LSP. Good enough to stop a code block reading as flat, undifferentiated
/// text; not trying to be more than that.
enum SyntaxLanguage {
    case python, javascript, typescript, swift, bash, json, go, rust, ruby, php
    case html, css, c, cpp, java, sql, yaml, plain

    static func detect(tag: String?) -> SyntaxLanguage {
        guard let tag = tag?.lowercased().trimmingCharacters(in: .whitespaces), !tag.isEmpty else { return .plain }
        switch tag {
        case "py", "python", "python3": return .python
        case "js", "javascript", "jsx", "mjs", "cjs", "node": return .javascript
        case "ts", "typescript", "tsx": return .typescript
        case "swift": return .swift
        case "sh", "bash", "zsh", "shell", "shell-script", "console": return .bash
        case "json", "jsonc": return .json
        case "go", "golang": return .go
        case "rust", "rs": return .rust
        case "rb", "ruby": return .ruby
        case "php": return .php
        case "html", "htm", "xml", "svg": return .html
        case "css", "scss", "sass", "less": return .css
        case "c", "h": return .c
        case "cpp", "c++", "cc", "hpp", "cxx": return .cpp
        case "java", "kotlin", "kt": return .java
        case "sql": return .sql
        case "yaml", "yml": return .yaml
        default: return .plain
        }
    }

    static func detect(fileExtension: String) -> SyntaxLanguage {
        switch fileExtension.lowercased() {
        case "py": return .python
        case "js", "mjs", "cjs", "jsx": return .javascript
        case "ts", "tsx": return .typescript
        case "swift": return .swift
        case "sh", "bash", "zsh": return .bash
        case "json": return .json
        case "go": return .go
        case "rs": return .rust
        case "rb": return .ruby
        case "php": return .php
        case "html", "htm": return .html
        case "css": return .css
        case "c", "h": return .c
        case "cpp", "cc", "hpp", "cxx": return .cpp
        case "java", "kt": return .java
        case "sql": return .sql
        case "yaml", "yml": return .yaml
        default: return .plain
        }
    }

    fileprivate var rule: SyntaxRule? {
        switch self {
        case .plain:
            return nil

        case .python:
            return SyntaxRule(
                keywords: [
                    "def", "class", "return", "if", "elif", "else", "for", "while", "in", "not", "and", "or",
                    "import", "from", "as", "try", "except", "finally", "raise", "with", "pass", "break",
                    "continue", "lambda", "yield", "global", "nonlocal", "assert", "del", "is", "async", "await",
                    "True", "False", "None", "self",
                ],
                lineComment: ["#"], blockCommentStart: nil, blockCommentEnd: nil,
                stringDelimiters: ["\"", "'"], supportsNumbers: true
            )

        case .javascript, .typescript:
            return SyntaxRule(
                keywords: [
                    "function", "return", "if", "else", "for", "while", "do", "switch", "case", "default",
                    "break", "continue", "var", "let", "const", "new", "delete", "typeof", "instanceof", "in",
                    "of", "class", "extends", "super", "this", "import", "export", "from", "as", "try", "catch",
                    "finally", "throw", "async", "await", "yield", "true", "false", "null", "undefined", "void",
                    "static", "get", "set", "interface", "type", "enum", "implements", "public", "private",
                    "protected", "readonly", "namespace",
                ],
                lineComment: ["//"], blockCommentStart: "/*", blockCommentEnd: "*/",
                stringDelimiters: ["\"", "'", "`"], supportsNumbers: true
            )

        case .swift:
            return SyntaxRule(
                keywords: [
                    "func", "return", "if", "else", "for", "while", "repeat", "switch", "case", "default",
                    "break", "continue", "var", "let", "class", "struct", "enum", "protocol", "extension",
                    "import", "try", "catch", "throw", "throws", "async", "await", "guard", "in", "is", "as",
                    "nil", "true", "false", "self", "Self", "super", "init", "deinit", "static", "final",
                    "private", "fileprivate", "internal", "public", "open", "mutating", "override", "required",
                    "convenience", "lazy", "weak", "unowned", "where", "some", "any", "typealias",
                    "associatedtype", "inout", "rethrows", "defer",
                ],
                lineComment: ["//"], blockCommentStart: "/*", blockCommentEnd: "*/",
                stringDelimiters: ["\""], supportsNumbers: true
            )

        case .bash:
            return SyntaxRule(
                keywords: [
                    "if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac",
                    "function", "return", "break", "continue", "export", "local", "readonly", "shift", "in",
                    "echo", "exit", "set", "unset", "source", "alias", "true", "false",
                ],
                lineComment: ["#"], blockCommentStart: nil, blockCommentEnd: nil,
                stringDelimiters: ["\"", "'"], supportsNumbers: true
            )

        case .json:
            return SyntaxRule(
                keywords: ["true", "false", "null"],
                lineComment: [], blockCommentStart: nil, blockCommentEnd: nil,
                stringDelimiters: ["\""], supportsNumbers: true
            )

        case .go:
            return SyntaxRule(
                keywords: [
                    "func", "return", "if", "else", "for", "range", "switch", "case", "default", "break",
                    "continue", "var", "const", "type", "struct", "interface", "package", "import", "go",
                    "defer", "chan", "select", "map", "make", "new", "nil", "true", "false", "fallthrough",
                    "goto",
                ],
                lineComment: ["//"], blockCommentStart: "/*", blockCommentEnd: "*/",
                stringDelimiters: ["\"", "`"], supportsNumbers: true
            )

        case .rust:
            return SyntaxRule(
                keywords: [
                    "fn", "return", "if", "else", "for", "while", "loop", "match", "break", "continue", "let",
                    "mut", "const", "static", "struct", "enum", "trait", "impl", "pub", "use", "mod", "crate",
                    "self", "Self", "super", "where", "as", "in", "move", "ref", "dyn", "async", "await",
                    "unsafe", "true", "false", "None", "Some", "Ok", "Err",
                ],
                lineComment: ["//"], blockCommentStart: "/*", blockCommentEnd: "*/",
                stringDelimiters: ["\""], supportsNumbers: true
            )

        case .ruby:
            return SyntaxRule(
                keywords: [
                    "def", "end", "return", "if", "elsif", "else", "unless", "for", "while", "until", "case",
                    "when", "break", "next", "class", "module", "require", "require_relative", "include",
                    "attr_accessor", "attr_reader", "attr_writer", "begin", "rescue", "ensure", "raise",
                    "yield", "true", "false", "nil", "self", "do", "then", "in",
                ],
                lineComment: ["#"], blockCommentStart: nil, blockCommentEnd: nil,
                stringDelimiters: ["\"", "'"], supportsNumbers: true
            )

        case .php:
            return SyntaxRule(
                keywords: [
                    "function", "return", "if", "else", "elseif", "endif", "for", "foreach", "while", "do",
                    "switch", "case", "default", "break", "continue", "class", "interface", "extends",
                    "implements", "public", "private", "protected", "static", "new", "echo", "print", "require",
                    "require_once", "include", "include_once", "namespace", "use", "try", "catch", "finally",
                    "throw", "true", "false", "null", "this", "array",
                ],
                lineComment: ["//", "#"], blockCommentStart: "/*", blockCommentEnd: "*/",
                stringDelimiters: ["\"", "'"], supportsNumbers: true
            )

        case .html:
            return SyntaxRule(
                keywords: [],
                lineComment: [], blockCommentStart: "<!--", blockCommentEnd: "-->",
                stringDelimiters: ["\"", "'"], supportsNumbers: false
            )

        case .css:
            return SyntaxRule(
                keywords: ["important", "from", "to"],
                lineComment: [], blockCommentStart: "/*", blockCommentEnd: "*/",
                stringDelimiters: ["\"", "'"], supportsNumbers: true
            )

        case .c, .cpp:
            return SyntaxRule(
                keywords: [
                    "int", "float", "double", "char", "void", "return", "if", "else", "for", "while", "do",
                    "switch", "case", "default", "break", "continue", "struct", "typedef", "enum", "union",
                    "const", "static", "extern", "sizeof", "include", "define", "ifdef", "ifndef", "endif",
                    "namespace", "class", "public", "private", "protected", "template", "new", "delete",
                    "this", "true", "false", "nullptr", "NULL", "virtual", "override", "using",
                ],
                lineComment: ["//"], blockCommentStart: "/*", blockCommentEnd: "*/",
                stringDelimiters: ["\"", "'"], supportsNumbers: true
            )

        case .java:
            return SyntaxRule(
                keywords: [
                    "public", "private", "protected", "class", "interface", "extends", "implements", "static",
                    "final", "void", "int", "float", "double", "boolean", "char", "long", "short", "byte",
                    "return", "if", "else", "for", "while", "do", "switch", "case", "default", "break",
                    "continue", "new", "this", "super", "try", "catch", "finally", "throw", "throws", "import",
                    "package", "true", "false", "null", "enum", "abstract", "synchronized",
                ],
                lineComment: ["//"], blockCommentStart: "/*", blockCommentEnd: "*/",
                stringDelimiters: ["\""], supportsNumbers: true
            )

        case .sql:
            let clauses = [
                "select", "from", "where", "insert", "into", "values", "update", "set", "delete", "join",
                "left", "right", "inner", "outer", "on", "group", "by", "order", "having", "limit", "as",
                "and", "or", "not", "null", "is", "in", "like", "create", "table", "alter", "drop", "index",
                "primary", "key", "foreign", "references", "default", "unique", "distinct", "union", "all",
                "exists", "case", "when", "then", "end",
            ]
            return SyntaxRule(
                keywords: Set(clauses + clauses.map { $0.uppercased() }),
                lineComment: ["--"], blockCommentStart: "/*", blockCommentEnd: "*/",
                stringDelimiters: ["'"], supportsNumbers: true
            )

        case .yaml:
            return SyntaxRule(
                keywords: ["true", "false", "null"],
                lineComment: ["#"], blockCommentStart: nil, blockCommentEnd: nil,
                stringDelimiters: ["\"", "'"], supportsNumbers: true
            )
        }
    }
}

private struct SyntaxRule {
    let keywords: Set<String>
    let lineComment: [String]
    let blockCommentStart: String?
    let blockCommentEnd: String?
    let stringDelimiters: Set<Character>
    let supportsNumbers: Bool
}

private enum SyntaxTokenKind {
    case keyword, string, comment, number
}

private enum SyntaxTokenizer {
    /// Single forward pass over the character array. Every branch fully
    /// consumes what it starts (a whole string, a whole comment, a whole
    /// identifier) before the loop continues, so there's no backtracking
    /// and no risk of double-matching the same span.
    static func tokenize(_ chars: [Character], rule: SyntaxRule) -> [(range: Range<Int>, kind: SyntaxTokenKind)] {
        var result: [(Range<Int>, SyntaxTokenKind)] = []
        var i = 0
        let n = chars.count

        func matches(_ s: String, at index: Int) -> Bool {
            let sChars = Array(s)
            guard index + sChars.count <= n else { return false }
            for (offset, ch) in sChars.enumerated() where chars[index + offset] != ch { return false }
            return true
        }

        while i < n {
            let c = chars[i]

            if let lc = rule.lineComment.first(where: { matches($0, at: i) }) {
                let start = i
                i += lc.count
                while i < n, chars[i] != "\n" { i += 1 }
                result.append((start..<i, .comment))
                continue
            }

            if let bcs = rule.blockCommentStart, let bce = rule.blockCommentEnd, matches(bcs, at: i) {
                let start = i
                i += bcs.count
                while i < n, !matches(bce, at: i) { i += 1 }
                i = min(i + bce.count, n)
                result.append((start..<i, .comment))
                continue
            }

            if rule.stringDelimiters.contains(c) {
                let start = i
                let triple = String(repeating: c, count: 3)
                if matches(triple, at: i) {
                    i += 3
                    while i < n, !matches(triple, at: i) { i += 1 }
                    i = min(i + 3, n)
                } else {
                    let quote = c
                    i += 1
                    while i < n, chars[i] != quote {
                        if chars[i] == "\\", i + 1 < n { i += 2 } else { i += 1 }
                    }
                    i = min(i + 1, n)
                }
                result.append((start..<i, .string))
                continue
            }

            if rule.supportsNumbers, c.isNumber {
                let start = i
                while i < n, chars[i].isHexDigit || chars[i] == "." || chars[i] == "_" || chars[i] == "x" || chars[i] == "X" {
                    i += 1
                }
                result.append((start..<i, .number))
                continue
            }

            if c.isLetter || c == "_" {
                let start = i
                while i < n, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" { i += 1 }
                if rule.keywords.contains(String(chars[start..<i])) {
                    result.append((start..<i, .keyword))
                }
                continue
            }

            i += 1
        }

        return result
    }
}

enum SyntaxHighlighter {
    static func highlight(_ code: String, language: SyntaxLanguage, colors: ThemeColors) -> AttributedString {
        var attributed = AttributedString(code)
        attributed.foregroundColor = colors.textCode

        guard let rule = language.rule else { return attributed }
        let chars = Array(code)
        let tokens = SyntaxTokenizer.tokenize(chars, rule: rule)
        guard !tokens.isEmpty else { return attributed }

        // Walk both the character array and the AttributedString indices
        // forward together — a single linear pass rather than repeated
        // random-access index(_:offsetBy:) calls, which are O(n) each on
        // AttributedString and would make this O(n·tokens).
        var attrIndex = attributed.startIndex
        var charIndex = 0

        for (range, kind) in tokens.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            while charIndex < range.lowerBound {
                attrIndex = attributed.index(afterCharacter: attrIndex)
                charIndex += 1
            }
            let start = attrIndex
            while charIndex < range.upperBound {
                attrIndex = attributed.index(afterCharacter: attrIndex)
                charIndex += 1
            }
            attributed[start..<attrIndex].foregroundColor = color(for: kind, colors: colors)
        }

        return attributed
    }

    private static func color(for kind: SyntaxTokenKind, colors: ThemeColors) -> Color {
        let isDark = colors == .dark
        switch kind {
        case .keyword: return Color(hex: isDark ? "#C678DD" : "#A626A4")
        case .string: return Color(hex: isDark ? "#98C379" : "#50A14F")
        case .number: return Color(hex: isDark ? "#D19A66" : "#986801")
        case .comment: return colors.textTertiary
        }
    }
}
