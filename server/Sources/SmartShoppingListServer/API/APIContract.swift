import Foundation
import FluentKit
import FluentSQL
import Vapor

/// A bounded JSON boundary preserves nulls and detects unknown fields before mapping domain values.
enum APIJSON: Codable, Equatable, Sendable {
    case object([String: APIJSON])
    case array([APIJSON])
    case string(String)
    case integer(Int64)
    case bool(Bool)
    case null

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    static func optional(_ string: String?) -> Self { string.map(Self.string) ?? .null }
}

extension APIJSON {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode([String: APIJSON].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([APIJSON].self))
        }
    }
}

struct APIProblem: Error, Sendable {
    let status: HTTPStatus
    let code: String
    let message: String

    var json: APIJSON {
        .object([
            "code": .string(code), "message": .string(message),
            "requestId": .string(UUID().uuidString.lowercased())
        ])
    }

    static let invalidRequest = Self(
        status: .badRequest,
        code: "invalid_request",
        message: "La petición no cumple el contrato."
    )
    static let notFound = Self(status: .notFound, code: "not_found", message: "Recurso no encontrado.")
    static let unavailable = Self(
        status: .serviceUnavailable,
        code: "service_unavailable",
        message: "El servicio no está disponible temporalmente."
    )
}

struct APIReply: Sendable {
    let status: HTTPStatus
    let body: Data

    func response() -> Response {
        Response(status: status, headers: ["Content-Type": "application/json; charset=utf-8"], body: .init(data: body))
    }
}

extension APIReply {
    init(status: HTTPStatus, json: APIJSON) throws {
        self.status = status
        self.body = try APIEncoding.data(json)
    }
}

enum APIEncoding {
    static func data(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func response(_ value: some Encodable, status: HTTPStatus = .ok) throws -> Response {
        APIReply(status: status, body: try data(value)).response()
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

/// Applied to API routes so failures never expose database statements, Apple tokens or other users.
struct APIErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch let problem as APIProblem {
            return try APIEncoding.response(problem.json, status: problem.status)
        } catch let abort as any AbortError {
            let problem: APIProblem
            if abort.status == .payloadTooLarge {
                problem = .init(status: .payloadTooLarge, code: "body_too_large", message: "El cuerpo excede 128 KiB.")
            } else if abort.status == .notFound {
                problem = .notFound
            } else if abort.status == .badRequest || abort.status == .unsupportedMediaType {
                problem = .invalidRequest
            } else {
                problem = .unavailable
            }
            return try APIEncoding.response(problem.json, status: problem.status)
        } catch {
            return try APIEncoding.response(APIProblem.unavailable.json, status: .serviceUnavailable)
        }
    }
}

struct APIObject: Sendable {
    private let validatedValues: [String: APIJSON]

    var values: [String: APIJSON] { validatedValues }

    func string(_ key: String) throws -> String {
        guard case .string(let value) = values[key] else { throw APIProblem.invalidRequest }
        return value
    }

    func uuid(_ key: String) throws -> UUID {
        try Self.uuid(string(key))
    }

    func optionalString(_ key: String) throws -> String? {
        guard let value = values[key] else { throw APIProblem.invalidRequest }
        if value == .null {
            return nil
        }
        guard case .string(let result) = value else { throw APIProblem.invalidRequest }
        return result
    }

    static func uuid(_ value: String) throws -> UUID {
        guard let id = UUID(uuidString: value), id.uuidString.lowercased() == value else {
            throw APIProblem.invalidRequest
        }
        return id
    }

    static func body(_ request: Request, allowed: Set<String>, required: Set<String>) throws -> Self {
        guard let mediaType = request.headers.contentType,
            mediaType.type.lowercased() == "application", mediaType.subType.lowercased() == "json",
            let buffer = request.body.data
        else {
            throw APIProblem.invalidRequest
        }
        guard buffer.readableBytes <= 131_072 else {
            throw APIProblem(status: .payloadTooLarge, code: "body_too_large", message: "El cuerpo excede 128 KiB.")
        }
        do {
            let value = try JSONDecoder().decode(APIJSON.self, from: Data(buffer.readableBytesView))
            return try Self(value, allowed: allowed, required: required)
        } catch let problem as APIProblem {
            throw problem
        } catch {
            throw APIProblem.invalidRequest
        }
    }
}

extension APIObject {
    init(_ value: APIJSON, allowed: Set<String>, required: Set<String>) throws {
        guard case .object(let fields) = value,
            Set(fields.keys).isSubset(of: allowed), required.isSubset(of: Set(fields.keys))
        else {
            throw APIProblem.invalidRequest
        }
        validatedValues = fields
    }
}

func shoppingSQL(_ database: any Database) throws -> any SQLDatabase {
    guard let sql = database as? any SQLDatabase else { throw APIProblem.unavailable }
    return sql
}

func databaseClock(_ sql: any SQLDatabase) async throws -> Date {
    guard let row = try await sql.raw("SELECT clock_timestamp() AS now").first() else {
        throw APIProblem.unavailable
    }
    return try row.decode(column: "now", as: Date.self)
}
