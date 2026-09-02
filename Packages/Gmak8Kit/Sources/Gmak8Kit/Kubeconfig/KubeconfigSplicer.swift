import Foundation
import Yams

/// Byte-preserving splice of the `gmak8` cluster/user/context list items.
///
/// Yams is used only to locate those items. Other keys, comments, and `exec` plugin
/// blocks are copied through as original bytes.
public enum KubeconfigSplicer {
    public static let stanzaName = "gmak8"

    public static func standaloneDocument(material: KubeconfigMaterial, setCurrentContext: Bool) -> String {
        var parts: [String] = [
            "apiVersion: v1",
            "kind: Config",
            "\(ListKey.clusters.rawValue):",
            renderItem(.clusters, material: material, dashIndent: 0),
            "\(ListKey.users.rawValue):",
            renderItem(.users, material: material, dashIndent: 0),
            "\(ListKey.contexts.rawValue):",
            renderItem(.contexts, material: material, dashIndent: 0),
        ]
        if setCurrentContext {
            parts.append("current-context: \(stanzaName)")
        }
        return parts.joined(separator: "\n") + "\n"
    }

    public static func splice(
        existing: String,
        material: KubeconfigMaterial,
        setCurrentContext: Bool
    ) throws -> String {
        if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return standaloneDocument(material: material, setCurrentContext: setCurrentContext)
        }

        let root: Node
        do {
            guard let node = try Yams.compose(yaml: existing) else {
                return standaloneDocument(material: material, setCurrentContext: setCurrentContext)
            }
            root = node
        } catch {
            throw KubeconfigSpliceError.notYAML
        }

        guard let mapping = root.mapping else {
            throw KubeconfigSpliceError.notYAML
        }
        if mapping.style == .flow {
            throw KubeconfigSpliceError.unspliceable
        }

        let source = YAMLSource(text: existing)
        let lists = try locateLists(in: mapping)
        var replacements: [Replacement] = []
        var suffix: [String] = []

        for key in ListKey.allCases {
            if let located = lists[key] {
                replacements.append(
                    contentsOf: try spliceList(
                        key, located: located, mapping: mapping, material: material, source: source)
                )
            } else {
                suffix.append("\(key.rawValue):")
                suffix.append(renderItem(key, material: material, dashIndent: 0))
            }
        }

        if setCurrentContext {
            if let pair = currentContextPair(in: mapping) {
                replacements.append(try replaceCurrentContext(pair: pair, source: source))
            } else {
                suffix.append("current-context: \(stanzaName)")
            }
        }

        var result = apply(replacements, to: existing)
        if !suffix.isEmpty {
            if !result.isEmpty && !result.hasSuffix("\n") {
                result.append("\n")
            }
            result.append(suffix.joined(separator: "\n"))
            result.append("\n")
        }
        return result
    }
}

private enum ListKey: String, CaseIterable {
    case clusters
    case users
    case contexts
}

private struct LocatedList {
    var key: ListKey
    var keyNode: Node
    var valueNode: Node
    var sequence: Node.Sequence?
}

private struct Replacement {
    var range: Range<String.Index>
    var text: String
}

private struct YAMLSource {
    let text: String
    let lines: [Line]

    struct Line {
        let start: String.Index
        let contentEnd: String.Index
        let end: String.Index

        func content(in text: String) -> Substring {
            text[start..<contentEnd]
        }

        func ending(in text: String) -> Substring {
            text[contentEnd..<end]
        }
    }

    init(text: String) {
        self.text = text
        var lines: [Line] = []
        var i = text.startIndex
        while i < text.endIndex {
            let start = i
            var contentEnd = i
            while i < text.endIndex && text[i] != "\n" && text[i] != "\r" {
                i = text.index(after: i)
                contentEnd = i
            }
            if i < text.endIndex {
                if text[i] == "\r" {
                    i = text.index(after: i)
                    if i < text.endIndex, text[i] == "\n" {
                        i = text.index(after: i)
                    }
                } else {
                    i = text.index(after: i)
                }
            }
            lines.append(Line(start: start, contentEnd: contentEnd, end: i))
        }
        self.lines = lines
    }

    func lineIndex(of mark: Mark) throws -> Int {
        let index = mark.line - 1
        guard index >= 0, index < lines.count else {
            throw KubeconfigSpliceError.unspliceable
        }
        return index
    }
}

private func locateLists(in mapping: Node.Mapping) throws -> [ListKey: LocatedList] {
    var result: [ListKey: LocatedList] = [:]
    for (keyNode, valueNode) in mapping {
        guard let name = keyNode.string, let key = ListKey(rawValue: name) else {
            continue
        }
        if let sequence = valueNode.sequence {
            if sequence.style == .flow && !sequence.isEmpty {
                throw KubeconfigSpliceError.unspliceable
            }
            result[key] = LocatedList(key: key, keyNode: keyNode, valueNode: valueNode, sequence: sequence)
        } else if valueNode.mapping != nil {
            throw KubeconfigSpliceError.unspliceable
        } else if valueNode.tag == Tag(.null) {
            result[key] = LocatedList(key: key, keyNode: keyNode, valueNode: valueNode, sequence: nil)
        } else {
            throw KubeconfigSpliceError.unspliceable
        }
    }
    return result
}

private func spliceList(
    _ key: ListKey,
    located: LocatedList,
    mapping: Node.Mapping,
    material: KubeconfigMaterial,
    source: YAMLSource
) throws -> [Replacement] {
    guard let keyMark = located.keyNode.mark else {
        throw KubeconfigSpliceError.unspliceable
    }
    let keyLine = try source.lineIndex(of: keyMark)
    let stopLine = try exclusiveStopLine(after: located.keyNode, mapping: mapping, source: source)

    if let sequence = located.sequence, sequence.style == .flow, sequence.isEmpty {
        return [try replaceEmptyFlowSequence(located.valueNode, key: key, material: material, source: source)]
    }

    guard let sequence = located.sequence, !sequence.isEmpty else {
        let insertion = source.lines[keyLine].end
        var text = renderItem(key, material: material, dashIndent: 0)
        if insertion == source.text.endIndex {
            if !source.text.hasSuffix("\n") {
                text = "\n" + text + "\n"
            } else {
                text += "\n"
            }
        } else if !text.hasSuffix("\n") {
            text += "\n"
        }
        return [Replacement(range: insertion..<insertion, text: text)]
    }

    var dashLines: [Int] = []
    dashLines.reserveCapacity(sequence.count)
    for item in sequence {
        guard let mark = item.mark else {
            throw KubeconfigSpliceError.unspliceable
        }
        dashLines.append(try dashLineIndex(from: mark, source: source, notBeforeLine: keyLine + 1))
    }

    let gmak8Indices = sequence.enumerated().compactMap { index, node -> Int? in
        node.mapping?["name"]?.string == KubeconfigSplicer.stanzaName ? index : nil
    }

    var replacements: [Replacement] = []
    if let first = gmak8Indices.first {
        let range = try itemRange(
            dashLine: dashLines[first],
            nextDashLine: first + 1 < dashLines.count ? dashLines[first + 1] : nil,
            stopLine: stopLine,
            source: source
        )
        let dashIndent = try dashIndent(at: dashLines[first], source: source)
        let rendered = renderItem(
            key,
            material: material,
            dashIndent: dashIndent,
            matching: range,
            source: source
        )
        replacements.append(Replacement(range: range, text: rendered))
        for extra in gmak8Indices.dropFirst() {
            let extraRange = try itemRange(
                dashLine: dashLines[extra],
                nextDashLine: extra + 1 < dashLines.count ? dashLines[extra + 1] : nil,
                stopLine: stopLine,
                source: source
            )
            replacements.append(Replacement(range: extraRange, text: ""))
        }
    } else {
        let lastIndex = dashLines.count - 1
        let lastRange = try itemRange(
            dashLine: dashLines[lastIndex],
            nextDashLine: nil,
            stopLine: stopLine,
            source: source
        )
        let dashIndent = try dashIndent(at: dashLines[lastIndex], source: source)
        var text = renderItem(key, material: material, dashIndent: dashIndent)
        if !text.hasSuffix("\n") {
            text += "\n"
        }
        if lastRange.upperBound == source.text.endIndex, !source.text.hasSuffix("\n") {
            text = "\n" + text
        }
        replacements.append(Replacement(range: lastRange.upperBound..<lastRange.upperBound, text: text))
    }
    return replacements
}

private func replaceEmptyFlowSequence(
    _ valueNode: Node,
    key: ListKey,
    material: KubeconfigMaterial,
    source: YAMLSource
) throws -> Replacement {
    guard let mark = valueNode.mark else {
        throw KubeconfigSpliceError.unspliceable
    }
    let startLine = try source.lineIndex(of: mark)
    let line = source.lines[startLine]
    let content = line.content(in: source.text)
    guard let open = content.firstIndex(of: "["), let close = content[open...].firstIndex(of: "]") else {
        throw KubeconfigSpliceError.unspliceable
    }
    let rangeStart = open
    let rangeEnd = content.index(after: close)
    var text = "\n" + renderItem(key, material: material, dashIndent: 0)
    if rangeEnd != line.contentEnd || line.end != line.contentEnd {
        text += "\n"
    } else if line.end == source.text.endIndex {
        text += "\n"
    }
    return Replacement(range: rangeStart..<rangeEnd, text: text)
}

private func itemRange(
    dashLine: Int,
    nextDashLine: Int?,
    stopLine: Int,
    source: YAMLSource
) throws -> Range<String.Index> {
    let dashIndent = try dashIndent(at: dashLine, source: source)
    let exclusive = nextDashLine ?? stopLine
    var lastContentLine = dashLine
    if dashLine + 1 < exclusive {
        for lineIdx in (dashLine + 1)..<exclusive {
            let content = source.lines[lineIdx].content(in: source.text)
            let trimmed = content.trimmingCharacters(in: .whitespaces)
            let indent = leadingWhitespaceCount(content)
            if trimmed.isEmpty {
                continue
            }
            if indent <= dashIndent {
                break
            }
            lastContentLine = lineIdx
        }
    }
    return source.lines[dashLine].start..<source.lines[lastContentLine].end
}

private func dashIndent(at line: Int, source: YAMLSource) throws -> Int {
    guard let indent = listItemDashIndent(source.lines[line].content(in: source.text)) else {
        throw KubeconfigSpliceError.unspliceable
    }
    return indent
}

private func dashLineIndex(from mark: Mark, source: YAMLSource, notBeforeLine: Int) throws -> Int {
    var idx = try source.lineIndex(of: mark)
    let minimum = min(max(notBeforeLine, 0), source.lines.count)
    while idx >= minimum {
        if listItemDashIndent(source.lines[idx].content(in: source.text)) != nil {
            return idx
        }
        if idx == 0 {
            break
        }
        idx -= 1
    }
    throw KubeconfigSpliceError.unspliceable
}

private func exclusiveStopLine(after keyNode: Node, mapping: Node.Mapping, source: YAMLSource) throws -> Int {
    guard let line = keyNode.mark?.line else {
        throw KubeconfigSpliceError.unspliceable
    }
    var next: Int?
    for (otherKey, _) in mapping {
        guard let otherLine = otherKey.mark?.line, otherLine > line else {
            continue
        }
        next = min(next ?? otherLine, otherLine)
    }
    if let next {
        return next - 1
    }
    return source.lines.count
}

private func currentContextPair(in mapping: Node.Mapping) -> (key: Node, value: Node)? {
    for (key, value) in mapping where key.string == "current-context" {
        return (key, value)
    }
    return nil
}

private func replaceCurrentContext(pair: (key: Node, value: Node), source: YAMLSource) throws -> Replacement {
    guard let keyMark = pair.key.mark else {
        throw KubeconfigSpliceError.unspliceable
    }
    let startLine = try source.lineIndex(of: keyMark)
    let endLine: Int
    if let valueMark = pair.value.mark, let valueLine = try? source.lineIndex(of: valueMark) {
        endLine = max(startLine, valueLine)
    } else {
        endLine = startLine
    }
    let start = source.lines[startLine].start
    let end = source.lines[endLine].end
    let indent = String(repeating: " ", count: leadingWhitespaceCount(source.lines[startLine].content(in: source.text)))
    var text = "\(indent)current-context: \(KubeconfigSplicer.stanzaName)"
    let ending = source.lines[endLine].ending(in: source.text)
    if ending.isEmpty {
        if end != source.text.endIndex {
            text += "\n"
        }
    } else {
        text += ending
    }
    return Replacement(range: start..<end, text: text)
}

private func apply(_ replacements: [Replacement], to text: String) -> String {
    let ordered = replacements.sorted { lhs, rhs in
        if lhs.range.lowerBound == rhs.range.lowerBound {
            return lhs.range.upperBound > rhs.range.upperBound
        }
        return lhs.range.lowerBound > rhs.range.lowerBound
    }
    var result = text
    for replacement in ordered {
        result.replaceSubrange(replacement.range, with: replacement.text)
    }
    return result
}

private func renderItem(
    _ key: ListKey,
    material: KubeconfigMaterial,
    dashIndent: Int,
    matching range: Range<String.Index>,
    source: YAMLSource
) -> String {
    var text = renderItem(key, material: material, dashIndent: dashIndent)
    let hadNewline =
        range.upperBound > range.lowerBound && source.text[source.text.index(before: range.upperBound)].isNewline
    if hadNewline {
        if let lastLine = source.lines.last(where: { $0.start < range.upperBound && $0.start >= range.lowerBound }) {
            text += lastLine.ending(in: source.text)
            if text.last?.isNewline != true {
                text += "\n"
            }
        } else if !text.hasSuffix("\n") {
            text += "\n"
        }
    }
    return text
}

private func renderItem(_ key: ListKey, material: KubeconfigMaterial, dashIndent: Int) -> String {
    let dash = String(repeating: " ", count: dashIndent) + "- "
    let pad = String(repeating: " ", count: dashIndent + 2)
    let nest = String(repeating: " ", count: dashIndent + 4)
    switch key {
    case .clusters:
        return """
            \(dash)cluster:
            \(nest)certificate-authority-data: \(material.certificateAuthorityData)
            \(nest)server: \(material.server)
            \(pad)name: \(KubeconfigSplicer.stanzaName)
            """
    case .users:
        return """
            \(dash)name: \(KubeconfigSplicer.stanzaName)
            \(pad)user:
            \(nest)client-certificate-data: \(material.clientCertificateData)
            \(nest)client-key-data: \(material.clientKeyData)
            """
    case .contexts:
        return """
            \(dash)context:
            \(nest)cluster: \(KubeconfigSplicer.stanzaName)
            \(nest)user: \(KubeconfigSplicer.stanzaName)
            \(pad)name: \(KubeconfigSplicer.stanzaName)
            """
    }
}

private func listItemDashIndent(_ line: Substring) -> Int? {
    var indent = 0
    var i = line.startIndex
    while i < line.endIndex && (line[i] == " " || line[i] == "\t") {
        indent += 1
        i = line.index(after: i)
    }
    guard i < line.endIndex, line[i] == "-" else {
        return nil
    }
    let next = line.index(after: i)
    if next == line.endIndex {
        return indent
    }
    let character = line[next]
    guard character == " " || character == "\t" else {
        return nil
    }
    return indent
}

private func leadingWhitespaceCount(_ line: Substring) -> Int {
    var count = 0
    for character in line {
        if character == " " || character == "\t" {
            count += 1
        } else {
            break
        }
    }
    return count
}
