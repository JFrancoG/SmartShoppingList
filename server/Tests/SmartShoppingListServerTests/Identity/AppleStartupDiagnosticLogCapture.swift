import Logging
import Synchronization
import Testing

final class AppleStartupDiagnosticLogCapture: Sendable {
    private struct Entry: Sendable {
        let level: Logger.Level
        let message: String
        let metadata: [String: String]
        let underlyingError: String?
    }

    private let storage = Mutex<[Entry]>([])

    var logger: Logger {
        Logger(label: "test.apple-startup") { _ in Handler(capture: self) }
    }

    var isEmpty: Bool { storage.withLock { $0.isEmpty } }

    func expectSingleDiagnostic(field: String, rule: String) throws {
        let entries = storage.withLock { $0 }
        try #require(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.level == .error)
        #expect(entry.message == "Invalid Apple startup configuration: \(field) \(rule)")
        #expect(entry.metadata == ["field": field])
        #expect(entry.underlyingError == nil)
        let exposed = ([entry.message] + Array(entry.metadata.values) + [entry.underlyingError ?? ""]).joined()
        #expect(!exposed.contains("DIAGNOSTIC_SENTINEL_SECRET"))
        #expect(!exposed.contains("MIGHAgEAMBMGByqGSM49AgEGCCqGSM49"))
        #expect(!exposed.contains("NSCocoaErrorDomain"))
        #expect(!exposed.contains("NSPOSIXErrorDomain"))
    }

    private struct Handler: LogHandler {
        let capture: AppleStartupDiagnosticLogCapture
        var metadata: Logger.Metadata = [:]
        var metadataProvider: Logger.MetadataProvider?
        var logLevel: Logger.Level = .trace

        subscript(metadataKey key: String) -> Logger.Metadata.Value? {
            get { metadata[key] }
            set { metadata[key] = newValue }
        }

        func log(event: LogEvent) {
            var combined = metadata
            if let provided = metadataProvider?.get() {
                combined.merge(provided) { _, new in new }
            }
            if let supplied = event.metadata {
                combined.merge(supplied) { _, new in new }
            }
            let entry = Entry(
                level: event.level,
                message: event.message.description,
                metadata: combined.mapValues(\.description),
                underlyingError: event.error.map { String(reflecting: $0) }
            )
            capture.storage.withLock { $0.append(entry) }
        }
    }
}
