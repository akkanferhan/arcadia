import Foundation

/// Edits INI-style files (also RetroArch .cfg and flat TOML) in place: only the keys
/// Arcadia sets are touched, everything else the emulator wrote is kept.
struct INIFile {
    private var lines: [String]
    private let separator: String

    /// - Parameter separator: written between key and value, e.g. `" = "` or `"="`.
    init(url: URL, separator: String = " = ") {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        self.separator = separator
    }

    /// Sets `key` inside `[section]`; a nil section means the top of the file.
    mutating func set(_ key: String, _ value: String, section: String? = nil) {
        func trimmed(_ index: Int) -> String { lines[index].trimmingCharacters(in: .whitespaces) }
        let entry = key + separator + value

        var start = 0
        if let section {
            guard let header = lines.indices.first(where: { trimmed($0) == "[\(section)]" }) else {
                if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("") }
                lines += ["[\(section)]", entry]
                return
            }
            start = header + 1
        }
        let end = (start..<lines.count).first { trimmed($0).hasPrefix("[") } ?? lines.count

        for index in start..<end {
            let line = trimmed(index)
            if let equals = line.firstIndex(of: "="), line[..<equals].trimmingCharacters(in: .whitespaces) == key {
                lines[index] = entry
                return
            }
        }
        var insertAt = end
        while insertAt > start, trimmed(insertAt - 1).isEmpty { insertAt -= 1 }
        lines.insert(entry, at: insertAt)
    }

    /// Replaces a whole section, which allows repeated keys (one binding per line).
    mutating func replaceSection(_ section: String, with entries: [(String, String)]) {
        let body = entries.map { $0.0 + separator + $0.1 }
        guard let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[\(section)]" }) else {
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("") }
            lines += ["[\(section)]"] + body
            return
        }
        let start = header + 1
        var end = (start..<lines.count).first { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
        while end > start, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
        lines.replaceSubrange(start..<end, with: body)
    }

    mutating func set(_ values: [String: String], section: String? = nil) {
        for (key, value) in values.sorted(by: { $0.key < $1.key }) { set(key, value, section: section) }
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Opens, edits and saves a file in one go.
    static func update(_ url: URL, separator: String = " = ", _ edit: (inout INIFile) -> Void) throws {
        var file = INIFile(url: url, separator: separator)
        edit(&file)
        try file.write(to: url)
    }
}

/// Edits block-style YAML files such as RPCS3's config.yml, addressed by key paths
/// like `["Video", "Renderer"]`. Only mappings are supported, which is all RPCS3 needs.
struct YAMLFile {
    private var lines: [String]

    init(url: URL) {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
    }

    mutating func set(_ path: [String], _ value: String) {
        var start = 0, end = lines.count
        for (level, key) in path.enumerated() {
            let indent = String(repeating: "  ", count: level)
            let isLeaf = level == path.count - 1
            let found = (start..<end).first { index in
                let line = lines[index]
                return line.hasPrefix(indent + key + ":") && !line.dropFirst(indent.count).hasPrefix(" ")
            }
            guard let index = found else {
                // Create the missing mapping keys and the value at the end of the parent.
                let missing = path[level...].enumerated().map { offset, name -> String in
                    let pad = String(repeating: "  ", count: level + offset)
                    return level + offset == path.count - 1 ? "\(pad)\(name): \(value)" : "\(pad)\(name):"
                }
                lines.insert(contentsOf: missing, at: end)
                return
            }
            if isLeaf {
                lines[index] = "\(indent)\(key): \(value)"
                return
            }
            // The child block ends at the next line indented at this level or less.
            start = index + 1
            end = (start..<end).first { i in
                let line = lines[i]
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
                return line.prefix(while: { $0 == " " }).count <= level * 2
            } ?? end
        }
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func update(_ url: URL, _ edit: (inout YAMLFile) -> Void) throws {
        var file = YAMLFile(url: url)
        edit(&file)
        try file.write(to: url)
    }
}

/// Edits simple XML settings files such as Cemu's settings.xml by element path.
enum XMLSettings {
    static func update(_ url: URL, root: String, _ values: [(path: String, value: String)]) throws {
        let document = (try? XMLDocument(contentsOf: url, options: [.nodePreserveAll]))
            ?? XMLDocument(rootElement: XMLElement(name: root))
        document.characterEncoding = "UTF-8"
        guard let rootElement = document.rootElement() else { return }
        for (path, value) in values {
            var element = rootElement
            for name in path.split(separator: "/").map(String.init) {
                if let child = element.elements(forName: name).first {
                    element = child
                } else {
                    let child = XMLElement(name: name)
                    element.addChild(child)
                    element = child
                }
            }
            element.stringValue = value
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try document.xmlData(options: [.nodePrettyPrint]).write(to: url, options: .atomic)
    }
}
