@testable import SmartShoppingListServer
import FluentKit
import FluentPostgresDriver
import Foundation
import NIOCore
import SQLKit
import Testing
import Vapor

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("Graceful application shutdown")
struct LifecycleTests {
    @Test(.timeLimit(.minutes(1)))
    func `an active HTTP request can finish its database query during shutdown`() async throws {
        let environment = Environment(name: "testing", arguments: [
            "LifecycleTests", "serve", "--hostname", "127.0.0.1", "--port", "0"
        ])
        let application = try await Application.make(environment)
        let databases = Databases(threadPool: .singleton, on: .singletonMultiThreadedEventLoopGroup)
        let requestEntered = ShutdownGate()
        let shutdownStarted = ShutdownGate()
        var didShutdown = false

        do {
            databases.use(try TestDatabaseConfiguration.make(), as: .psql)
            // Exercise production shutdown without migrating schemas used by the other test suite.
            application.lifecycle.use(DatabaseShutdownProbe(databases: databases))
            application.get("pending-query") { _ async throws -> String in
                await requestEntered.open()
                await shutdownStarted.wait()
                guard let sql = try databases.database() as? any SQLDatabase else { throw Abort(.internalServerError) }
                guard let row = try await sql.raw("SELECT 42 AS value").first() else {
                    throw Abort(.internalServerError)
                }
                return try String(row.decode(column: "value", as: Int.self))
            }

            let httpServer = application.http.server.shared
            let server = ShutdownObservingServer(underlying: httpServer, shutdownStarted: shutdownStarted)
            application.servers.use { _ in server }
            try await application.startup()
            let port = try #require(httpServer.localAddress?.port)
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/pending-query"))

            async let response = sendRequest(to: url, requestEntered: requestEntered)
            await requestEntered.wait()
            didShutdown = true
            try await application.asyncShutdown()

            let (body, responseMetadata) = try await response
            let httpResponse = try #require(responseMetadata as? HTTPURLResponse)
            try #require(httpResponse.statusCode == 200)
            #expect(String(decoding: body, as: UTF8.self) == "42")
        } catch {
            await shutdownStarted.open()
            if !didShutdown {
                try await application.asyncShutdown()
            }
            await databases.shutdownAsync()
            throw error
        }
    }

    private func sendRequest(to url: URL, requestEntered: ShutdownGate) async throws -> (Data, URLResponse) {
        do {
            let response = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
            await requestEntered.open()
            return response
        } catch {
            // A transport failure must release the test coordinator so it can clean up the server.
            await requestEntered.open()
            throw error
        }
    }
}

private struct DatabaseShutdownProbe: LifecycleHandler {
    let databases: Databases

    func shutdownAsync(_ application: Application) async {
        await MigrateLifecycleHandler(databases: databases).shutdownAsync(application)
    }
}

private struct ShutdownObservingServer: Server {
    let underlying: HTTPServer
    let shutdownStarted: ShutdownGate

    var onShutdown: EventLoopFuture<Void> { underlying.onShutdown }

    @available(*, noasync)
    func start(address: BindAddress?) throws {
        try underlying.start(address: address)
    }

    func start(address: BindAddress?) async throws {
        try await underlying.start(address: address)
    }

    @available(*, noasync)
    func shutdown() {
        underlying.shutdown()
    }

    func shutdown() async {
        await shutdownStarted.open()
        await underlying.shutdown()
    }
}

private actor ShutdownGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}
