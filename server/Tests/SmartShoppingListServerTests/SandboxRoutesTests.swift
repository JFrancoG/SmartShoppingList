@testable import SmartShoppingListServer
import Testing
import Vapor
import VaporTesting
import FluentKit

// Keep database cases under the existing suite's serialization and migration lifecycle.
extension SmartShoppingListServerTests {
    @Test(arguments: ["sandbox", "production"])
    func `deployed environments preserve product routes without publishing local todos`(
        environmentName: String
    ) async throws {
        let existing = Todo(title: "Local infrastructure record")
        try await existing.create(on: database)
        let existingID = try existing.requireID()
        let databases = try testDatabases
        let arguments = ["SmartShoppingListServer", "serve", "--env", environmentName]
        let environment = try Environment.detect(arguments: arguments)
        let application = try await Application.make(environment)
        application.middleware.use(APIErrorMiddleware(), at: .end)

        do {
            try routes(application, databases: databases)
            try await application.asyncBoot()

            let get = try await application.sendRequest(.GET, "/todos")
            #expect(get.status == .notFound)
            let create = try await application.sendRequest(
                .POST,
                "/todos",
                headers: ["Content-Type": "application/json"],
                body: ByteBuffer(string: "{\"title\":\"Must not be created remotely\"}")
            )
            #expect(create.status == .notFound)
            let delete = try await application.sendRequest(.DELETE, "/todos/\(existingID)")
            #expect(delete.status == .notFound)
            let persisted = try await Todo.query(on: database).all()
            #expect(persisted.map(\.id) == [existingID])

            let hello = try await application.sendRequest(.GET, "/hello")
            #expect(hello.status == .ok)
            #expect(hello.body.string == "Hello, world!")
            let account = try await application.sendRequest(.GET, "/v1/me")
            #expect(account.status == .unauthorized)
            #expect(try ShoppingFixture.object(account)["code"] == .string("invalid_session"))
            let subscription = try await application.sendRequest(.GET, "/v1/account/subscription")
            #expect(subscription.status == .unauthorized)
            #expect(try ShoppingFixture.object(subscription)["code"] == .string("invalid_session"))
        } catch {
            try await application.asyncShutdown()
            throw error
        }
        try await application.asyncShutdown()
    }
}
