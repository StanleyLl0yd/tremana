import Foundation

public indirect enum RPCValue: Encodable, Sendable {
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case array([RPCValue])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        }
    }
}

struct RPCRequest: Encodable {
    let method: String
    let arguments: [String: RPCValue]
}

struct RPCReply<Value: Decodable>: Decodable {
    let result: String
    let arguments: Value?

    enum CodingKeys: String, CodingKey {
        case result
        case arguments
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        result = try values.decode(String.self, forKey: .result)
        // Error replies may contain incomplete or differently-shaped arguments.
        // Check result before attempting to decode the typed success payload.
        arguments = result == "success"
            ? try values.decodeIfPresent(Value.self, forKey: .arguments)
            : nil
    }
}
