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
}
