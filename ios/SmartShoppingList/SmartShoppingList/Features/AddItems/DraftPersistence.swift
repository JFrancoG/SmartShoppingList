import Foundation

protocol DraftPersisting: Sendable {
    func load() async throws -> ShoppingDraftSnapshot?
    func save(_ draft: ShoppingDraftSnapshot) async throws
}

enum DraftPersistenceError: Error, Equatable {
    case corruptFile
    case fileTooLarge
    case tooManyItems
    case readFailed
    case writeFailed
}

actor FileDraftPersistence: DraftPersisting {
    private static let maximumBytes = 128 * 1_024
    private static let maximumItems = 50
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() async throws -> ShoppingDraftSnapshot? {
        try Task.checkCancellation()
        guard let data = try readFile() else { return nil }
        let draft: ShoppingDraftSnapshot
        do {
            draft = try JSONDecoder().decode(ShoppingDraftSnapshot.self, from: data)
        } catch {
            throw DraftPersistenceError.corruptFile
        }
        guard draft.items.count <= Self.maximumItems else { throw DraftPersistenceError.tooManyItems }
        return draft
    }

    func save(_ draft: ShoppingDraftSnapshot) async throws {
        try Task.checkCancellation()
        guard draft.items.count <= Self.maximumItems else { throw DraftPersistenceError.tooManyItems }
        let data: Data
        do {
            data = try JSONEncoder().encode(draft)
        } catch {
            throw DraftPersistenceError.writeFailed
        }
        guard data.count <= Self.maximumBytes else { throw DraftPersistenceError.fileTooLarge }
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw DraftPersistenceError.writeFailed
        }
    }

    private func readFile() throws -> Data? {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        } catch let error as POSIXError where error.code == .ENOENT {
            return nil
        } catch {
            throw DraftPersistenceError.readFailed
        }
        defer {
            try? handle.close()
        }

        var data = Data()
        // Bound the read itself, including files that grow after opening, before attempting JSON decoding.
        while data.count <= Self.maximumBytes {
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: Self.maximumBytes + 1 - data.count)
            } catch {
                throw DraftPersistenceError.readFailed
            }
            guard let chunk, !chunk.isEmpty else { return data }
            data.append(chunk)
        }
        throw DraftPersistenceError.fileTooLarge
    }
}

actor MemoryDraftPersistence: DraftPersisting {
    private var draft: ShoppingDraftSnapshot?

    func load() async throws -> ShoppingDraftSnapshot? { draft }

    func save(_ draft: ShoppingDraftSnapshot) async throws {
        self.draft = draft
    }
}
