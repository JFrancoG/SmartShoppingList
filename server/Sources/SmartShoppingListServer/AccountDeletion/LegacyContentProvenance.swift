import Foundation
import FluentSQL

/// Infers historical field authors only from a complete sequence of successful server receipts.
/// A missing revision or a different final value leaves the field unknown rather than inventing an owner.
enum LegacyContentProvenance {
    struct Item: Decodable, Equatable, Sendable {
        let id: UUID
        let groupId: UUID
        let storeId: UUID
        let name: String
        let quantity: String?
        let status: String
        let version: Int64
        let createdBy: UUID?
        let purchasedBy: UUID?
    }

    struct Revision: Sendable {
        let actor: UUID
        let operation: String
        let item: Item
    }

    struct Authors: Equatable, Sendable {
        let name: UUID
        let quantity: UUID?
    }

    static func authors(of current: Item, revisions: [Revision]) -> Authors? {
        let sequence = revisions.filter { $0.item.id == current.id }.sorted { $0.item.version < $1.item.version }
        guard current.version > 0, Int64(sequence.count) == current.version,
              let first = sequence.first, first.operation == "addItems", first.item.version == 1,
              first.item.status == "pending", first.item.purchasedBy == nil,
              first.actor == first.item.createdBy, first.item.createdBy == current.createdBy,
              first.item.groupId == current.groupId
        else {
            return nil
        }
        var previous = first.item
        var name = first.actor
        var quantity = first.item.quantity == nil ? nil : first.actor
        for revision in sequence.dropFirst() {
            let item = revision.item
            guard item.version == previous.version + 1, item.groupId == current.groupId,
                  item.createdBy == current.createdBy, previous.status == "pending"
            else {
                return nil
            }
            switch revision.operation {
            case "editItem":
                guard item.status == "pending", item.purchasedBy == nil else { return nil }
                if item.name != previous.name {
                    name = revision.actor
                }
                if item.quantity == nil {
                    quantity = nil
                } else if item.quantity != previous.quantity {
                    quantity = revision.actor
                }
            case "cancelItem", "finalizePurchase":
                guard item.name == previous.name, item.quantity == previous.quantity,
                      item.storeId == previous.storeId,
                      item.status == (revision.operation == "cancelItem" ? "cancelled" : "purchased"),
                      item.purchasedBy == (revision.operation == "cancelItem" ? nil : revision.actor)
                else {
                    return nil
                }
            default:
                return nil
            }
            previous = item
        }
        guard previous == current else { return nil }
        return Authors(name: name, quantity: quantity)
    }

    static func revisions(group: UUID, on sql: any SQLDatabase) async throws -> [Revision] {
        let rows = try await sql.raw("""
            SELECT user_id,operation_type,body FROM mutation_receipts
            WHERE group_id = \(bind: group) AND status IN (200,201) AND body IS NOT NULL
                AND operation_type IN ('addItems','editItem','cancelItem','finalizePurchase')
            """).all()
        let decoder = JSONDecoder()
        var revisions: [Revision] = []
        for row in rows {
            let actor = try row.decode(column: "user_id", as: UUID.self)
            let operation = try row.decode(column: "operation_type", as: String.self)
            let body = Data(try row.decode(column: "body", as: String.self).utf8)
            let items: [Item]
            if operation == "addItems" || operation == "finalizePurchase" {
                guard let envelope = try? decoder.decode(ItemsEnvelope.self, from: body) else { continue }
                items = envelope.items
            } else {
                guard let item = try? decoder.decode(Item.self, from: body) else { continue }
                items = [item]
            }
            revisions += items.map { Revision(actor: actor, operation: operation, item: $0) }
        }
        return revisions
    }

    private struct ItemsEnvelope: Decodable {
        let items: [Item]
    }
}
