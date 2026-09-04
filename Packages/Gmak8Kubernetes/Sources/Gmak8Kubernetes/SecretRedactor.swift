import Foundation

public enum SecretRedactor {
    public static let redacted = WorkloadsCopy.secretValue

    public static func redactJSONObject(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var copy: [String: Any] = [:]
            for (key, nested) in dict {
                if key == "data" || key == "stringData", nested is [String: Any] {
                    if let map = nested as? [String: Any] {
                        copy[key] = Dictionary(uniqueKeysWithValues: map.keys.map { ($0, redacted) })
                    } else {
                        copy[key] = redacted
                    }
                } else if key == "value", dict["name"] != nil {
                    copy[key] = redacted
                } else {
                    copy[key] = redactJSONObject(nested)
                }
            }
            return copy
        }
        if let array = value as? [Any] {
            return array.map { redactJSONObject($0) }
        }
        return value
    }

    public static func yaml<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let json = try JSONSerialization.jsonObject(with: data)
        return emitYAML(redactJSONObject(json), indent: 0)
    }

    private static func emitYAML(_ value: Any, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        if value is NSNull {
            return "null"
        }
        if let dict = value as? [String: Any] {
            if dict.isEmpty {
                return "{}"
            }
            let lines = dict.keys.sorted().map { key in
                let nested = dict[key]!
                let rendered = emitYAML(nested, indent: indent + 1)
                if nested is [String: Any] || nested is [Any] {
                    return "\(pad)\(key):\n\(rendered)"
                }
                return "\(pad)\(key): \(rendered)"
            }
            return lines.joined(separator: "\n")
        }
        if let array = value as? [Any] {
            if array.isEmpty {
                return "\(pad)[]"
            }
            return array.map { item in
                let rendered = emitYAML(item, indent: indent + 1)
                if item is [String: Any] || item is [Any] {
                    return "\(pad)-\n\(rendered)"
                }
                return "\(pad)- \(rendered)"
            }.joined(separator: "\n")
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.stringValue
        }
        let text = String(describing: value)
        if text.contains(":") || text.contains("#") || text.contains("\n") {
            return "\"\(text.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return text
    }

    public static func envDisplay(value: String?, secretName: String?, secretKey: String?) -> String {
        if let secretName, let secretKey {
            return "secret \(secretName)/\(secretKey)"
        }
        if value != nil {
            return redacted
        }
        return "—"
    }
}
