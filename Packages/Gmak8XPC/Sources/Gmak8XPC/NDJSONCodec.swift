import Foundation

public enum NDJSONCodec {
    public static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(value)
        if data.last != UInt8(ascii: "\n") {
            data.append(UInt8(ascii: "\n"))
        }
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, line: String) throws -> T {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8), !trimmed.isEmpty else {
            throw EngineErrorCode.invalidRequest
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw unwrapEngineCode(error)
        }
    }

    public static func decodeRequest(line: String) -> Result<EngineRequest, EngineErrorCode> {
        do {
            return .success(try decode(EngineRequest.self, line: line))
        } catch let code as EngineErrorCode {
            return .failure(code)
        } catch {
            return .failure(unwrapEngineCode(error))
        }
    }

    public static func decodeReply(line: String) throws -> EngineReply {
        try decode(EngineReply.self, line: line)
    }

    public static func decodeEvent(line: String) throws -> EngineEvent {
        try decode(EngineEvent.self, line: line)
    }

    private static func unwrapEngineCode(_ error: Error) -> EngineErrorCode {
        if let code = error as? EngineErrorCode {
            return code
        }
        if let decoding = error as? DecodingError {
            switch decoding {
            case .dataCorrupted(let context), .keyNotFound(_, let context), .typeMismatch(_, let context),
                .valueNotFound(_, let context):
                if let code = context.underlyingError as? EngineErrorCode {
                    return code
                }
            @unknown default:
                break
            }
        }
        return .invalidRequest
    }
}
