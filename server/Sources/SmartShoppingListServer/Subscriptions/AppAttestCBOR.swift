import Foundation

/// The small, bounded CBOR subset used by Apple's attestation and authenticator objects.
/// Indefinite lengths, duplicate map keys and unconsumed bytes are rejected.
indirect enum AppAttestCBOR {
    enum Key: Hashable {
        case text(String), integer(Int64)
    }

    case bytes(Data), text(String), integer(Int64), array([Self]), map([Key: Self])

    var bytes: Data? { if case .bytes(let value) = self { value } else { nil } }
    var text: String? { if case .text(let value) = self { value } else { nil } }
    var integer: Int64? { if case .integer(let value) = self { value } else { nil } }
    var array: [Self]? { if case .array(let value) = self { value } else { nil } }
    var map: [Key: Self]? { if case .map(let value) = self { value } else { nil } }

    subscript(_ name: String) -> Self? { map?[.text(name)] }
    subscript(_ number: Int64) -> Self? { map?[.integer(number)] }

    struct Reader {
        private let data: [UInt8]
        private(set) var offset = 0


        var isAtEnd: Bool { offset == data.count }

        mutating func read(depth: Int = 0) throws -> AppAttestCBOR {
            guard depth < 8 else { throw AppStoreGatewayError.rejected }
            guard let head = try take(1).first else { throw AppStoreGatewayError.rejected }
            let major = head >> 5
            let additional = head & 31
            let count: UInt64
            switch additional {
            case 0...23: count = UInt64(additional)
            case 24: count = try number(1)
            case 25: count = try number(2)
            case 26: count = try number(4)
            case 27: count = try number(8)
            default: throw AppStoreGatewayError.rejected
            }
            guard count <= UInt64(Int64.max) else { throw AppStoreGatewayError.rejected }
            switch major {
            case 0: return .integer(Int64(count))
            case 1: return .integer(-1 - Int64(count))
            case 2:
                return .bytes(Data(try take(Int(count))))
            case 3:
                guard count <= 2_048, let value = String(bytes: try take(Int(count)), encoding: .utf8) else {
                    throw AppStoreGatewayError.rejected
                }
                return .text(value)
            case 4:
                guard count <= 16 else { throw AppStoreGatewayError.rejected }
                var values: [AppAttestCBOR] = []
                for _ in 0..<count {
                    values.append(try read(depth: depth + 1))
                }
                return .array(values)
            case 5:
                guard count <= 32 else { throw AppStoreGatewayError.rejected }
                var values: [Key: AppAttestCBOR] = [:]
                for _ in 0..<count {
                    let key: Key
                    switch try read(depth: depth + 1) {
                    case .text(let value): key = .text(value)
                    case .integer(let value): key = .integer(value)
                    default: throw AppStoreGatewayError.rejected
                    }
                    guard values[key] == nil else { throw AppStoreGatewayError.rejected }
                    values[key] = try read(depth: depth + 1)
                }
                return .map(values)
            default: throw AppStoreGatewayError.rejected
            }
        }

        private mutating func number(_ count: Int) throws -> UInt64 {
            try take(count).reduce(0) { ($0 << 8) | UInt64($1) }
        }

        private mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
            guard count <= data.count - offset else { throw AppStoreGatewayError.rejected }
            defer { offset += count }
            return data[offset..<(offset + count)]
        }
    }
}

extension AppAttestCBOR.Reader {
    init(_ data: Data) throws {
        guard !data.isEmpty, data.count <= 65_536 else { throw AppStoreGatewayError.rejected }
        self.data = Array(data)
    }
}
