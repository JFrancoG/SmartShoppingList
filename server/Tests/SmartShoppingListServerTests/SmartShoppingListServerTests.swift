@testable import SmartShoppingListServer
import Testing
import Vapor
import VaporTesting
import FluentKit
import FluentPostgresDriver
import Foundation

// The migration lifecycle resets one dedicated PostgreSQL database between tests.
@Suite("App Tests", .serialized, .withApp())
struct SmartShoppingListServerTests {
    @Test("Test Hello World Route")
    func helloWorld() async throws {
        let res = try await app.sendRequest(.GET, "/hello")
        #expect(res.status == .ok)
        #expect(res.body.string == "Hello, world!")
    }

    @Test("Getting all the Todos")
    func getAllTodos() async throws {
        let sampleTodos = [Todo(title: "sample1"), Todo(title: "sample2")]
        try await sampleTodos.create(on: database)

        let res = try await app.sendRequest(.GET, "/todos")
        #expect(res.status == .ok)
        let todos = try res.content.decode([TodoDTO].self)
        #expect(todos.compactMap(\.title).sorted() == ["sample1", "sample2"])
        #expect(Set(todos.compactMap(\.id)) == Set(try sampleTodos.map { try $0.requireID() }))
    }

    @Test("Creating a Todo")
    func createTodo() async throws {
        let newDTO = TodoDTO(id: nil, title: "test")

        let res = try await app.sendRequest(.POST, "/todos", beforeRequest: { request in
            try request.content.encode(newDTO)
        })
        try #require(res.status == .ok)
        let created = try res.content.decode(TodoDTO.self)
        let createdID = try #require(created.id)
        let models = try await Todo.query(on: database).all()
        #expect(models.map(\.title) == ["test"])
        #expect(models.map(\.id) == [createdID])

        let response = try await app.sendRequest(.GET, "/todos")
        try #require(response.status == .ok)
        let persisted = try response.content.decode([TodoDTO].self)
        #expect(persisted.compactMap(\.title) == ["test"])
        #expect(persisted.compactMap(\.id) == [createdID])
    }

    @Test("Deleting a Todo")
    func deleteTodo() async throws {
        let testTodos = [Todo(title: "test1"), Todo(title: "test2")]
        try await testTodos.create(on: database)

        let res = try await app.sendRequest(.DELETE, "/todos/\(testTodos[0].requireID())")
        #expect(res.status == .noContent)
        let model = try await Todo.find(testTodos[0].id, on: database)
        #expect(model == nil)
        let remaining = try await Todo.query(on: database).all()
        #expect(remaining.map(\.title) == ["test2"])
    }

    @Test
    func `committed transaction persists every record`() async throws {
        try await database.transaction { transaction in
            try await Todo(title: "Leche sin lactosa").create(on: transaction)
            try await Todo(title: "Pan integral").create(on: transaction)
        }

        let response = try await app.sendRequest(.GET, "/todos")
        try #require(response.status == .ok)
        let todos = try response.content.decode([TodoDTO].self)
        #expect(todos.compactMap(\.title).sorted() == ["Leche sin lactosa", "Pan integral"])
        #expect(Set(todos.compactMap(\.id)).count == 2)
    }

    @Test
    func `failed transaction preserves previous data without partial writes`() async throws {
        let existing = Todo(title: "Compra anterior")
        try await existing.create(on: database)
        let existingID = try existing.requireID()

        await #expect {
            try await database.transaction { transaction in
                try await Todo(title: "No debe persistir").create(on: transaction)
                try await Todo(id: existingID, title: "Identificador duplicado").create(on: transaction)
            }
        } throws: { error in
            (error as? any DatabaseError)?.isConstraintFailure == true
        }

        let response = try await app.sendRequest(.GET, "/todos")
        try #require(response.status == .ok)
        let todos = try response.content.decode([TodoDTO].self)
        #expect(todos.compactMap(\.title) == ["Compra anterior"])
        #expect(todos.compactMap(\.id) == [existingID])
    }

    @Test
    func `a failed migration prevents application boot`() async throws {
        let application = try await Application.make(.testing)
        let databases = Databases(threadPool: .singleton, on: .singletonMultiThreadedEventLoopGroup)
        do {
            databases.use(try TestDatabaseConfiguration.make(), as: .psql)
            application.lifecycle.use(MigrateLifecycleHandler(databases: databases, migrations: FailingMigration()))
            await #expect(throws: ExpectedMigrationFailure.self) {
                try await application.asyncBoot()
            }
        } catch {
            await databases.shutdownAsync()
            try await application.asyncShutdown()
            throw error
        }
        try await application.asyncShutdown()
    }
}

private enum ExpectedMigrationFailure: Error {
    case rejected
}

private struct FailingMigration: AsyncMigration {
    var name: String { "Issue1ExpectedFailingMigration" }

    func prepare(on database: any Database) async throws {
        throw ExpectedMigrationFailure.rejected
    }

    func revert(on database: any Database) async throws {}
}

extension TodoDTO: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title
    }
}
