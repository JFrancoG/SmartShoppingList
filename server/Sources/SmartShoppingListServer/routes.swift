import FluentKit
import RoutingKit
import Vapor

func routes(_ app: Application, databases: Databases) async throws {
    app.get { req async in
        "It works!"
    }

    app.get("hello") { req async -> String in
        "Hello, world!"
    }

    try await app.register(collection: TodoController(databases: databases))
}
