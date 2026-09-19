import Foundation
import Testing
@testable import SmartShoppingList

@Suite(.tags(.integration))
struct DraftPersistenceTests {
    @Test
    func `Reopening a saved draft preserves corrected text identity and incomplete rows`() async throws {
        let directory = try makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appending(path: "Application Support/AddItems/draft.json")
        let writer = FileDraftPersistence(fileURL: fileURL)
        #expect(try await writer.load() == nil)
        let draft = ShoppingDraftSnapshot(
            text: "  dos briks de leche sin lactosa y pan\n",
            items: [
                ShoppingDraftItem(id: identifier(1), name: "leche SIN LACTOSA", quantity: "2 briks", store: "Día Norte"),
                ShoppingDraftItem(id: identifier(2), name: "pan integral", quantity: "", store: "")
            ],
            interpretedText: "dos briks de leche y pan"
        )

        try await writer.save(draft)
        let reader = FileDraftPersistence(fileURL: fileURL)
        let restored = try #require(try await reader.load())

        #expect(restored.text == "  dos briks de leche sin lactosa y pan\n")
        #expect(restored.interpretedText == "dos briks de leche y pan")
        #expect(restored.items.map(\.id) == [identifier(1), identifier(2)])
        #expect(restored.items.map(\.name) == ["leche SIN LACTOSA", "pan integral"])
        #expect(restored.items.map(\.quantity) == ["2 briks", ""])
        #expect(restored.items.map(\.store) == ["Día Norte", ""])
    }

    @Test
    func `Saving a corrected legacy draft replaces all earlier content`() async throws {
        let directory = try makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appending(path: "draft.json")
        let legacy = Data("""
        {"text":"leche y pan en Mercadona","items":[
          {"id":"00000000-0000-0000-0000-000000000001","name":"leche","quantity":"1 litro","store":"Mercadona"},
          {"id":"00000000-0000-0000-0000-000000000002","name":"pan","quantity":"","store":"Mercadona"}
        ]}
        """.utf8)
        try legacy.write(to: fileURL)
        let writer = FileDraftPersistence(fileURL: fileURL)
        var corrected = try #require(try await writer.load())
        #expect(corrected.interpretedText == nil)
        corrected.text = "leche sin lactosa en Día"
        corrected.interpretedText = "leche sin lactosa en Día"
        corrected.items = [
            ShoppingDraftItem(id: identifier(1), name: "leche sin lactosa", quantity: "3 briks", store: "Día")
        ]

        try await writer.save(corrected)
        let reader = FileDraftPersistence(fileURL: fileURL)
        let latest = try #require(try await reader.load())

        #expect(latest.text == "leche sin lactosa en Día")
        #expect(latest.interpretedText == "leche sin lactosa en Día")
        #expect(latest.items.map(\.id) == [identifier(1)])
        #expect(latest.items.map(\.name) == ["leche sin lactosa"])
        #expect(latest.items.map(\.quantity) == ["3 briks"])
        #expect(latest.items.map(\.store) == ["Día"])
    }

    @Test(arguments: InvalidDraftFile.allCases)
    func `Invalid stored drafts fail explicitly and preserve the original bytes`(fixture: InvalidDraftFile) async throws {
        let directory = try makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appending(path: "draft.json")
        let originalBytes = fixture.data
        try originalBytes.write(to: fileURL)
        let reader = FileDraftPersistence(fileURL: fileURL)

        await #expect(throws: fixture.error) {
            try await reader.load()
        }

        #expect(try Data(contentsOf: fileURL) == originalBytes)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DraftPersistenceTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func identifier(_ number: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number))
    }
}

enum InvalidDraftFile: CaseIterable {
    case malformedJSON
    case exceedsByteLimit
    case exceedsItemLimit

    var error: DraftPersistenceError {
        switch self {
        case .malformedJSON: .corruptFile
        case .exceedsByteLimit: .fileTooLarge
        case .exceedsItemLimit: .tooManyItems
        }
    }

    var data: Data {
        switch self {
        case .malformedJSON:
            return Data("{\"text\":\"leche\",\"items\":[".utf8)
        case .exceedsByteLimit:
            return Data(repeating: 0x20, count: 128 * 1_024 + 1)
        case .exceedsItemLimit:
            let items = (1...51).map { number in
                """
                {"id":"00000000-0000-0000-0000-0000000000\(String(format: "%02d", number))",\
                "name":"producto \(number)","quantity":"","store":""}
                """
            }.joined(separator: ",")
            return Data("{\"text\":\"51 productos\",\"items\":[\(items)]}".utf8)
        }
    }
}
