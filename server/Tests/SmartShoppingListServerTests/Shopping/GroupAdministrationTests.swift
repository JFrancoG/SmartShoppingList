@testable import SmartShoppingListServer
import Foundation
import FluentKit
import FluentSQL
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test("Accepting a transfer changes authority and preserves the creator and shopping history")
    func transferPreservesHistory() async throws {
        let owner = try await ShoppingFixture.user()
        let successor = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(successor, group: group)
        let history = try await AdministrationFixture.seedHistory(owner, group: group)
        let invitation = try await ShoppingFixture.invitation(group)
        let proposal = try await AdministrationFixture.propose(owner, recipient: successor, group: group)
        let operation = AdministrationFixture.operation()
        let path = "/v1/groups/\(group)/administration-transfers/\(proposal)/accept"
        let accepted = try await ShoppingFixture.request(
            .POST,
            path,
            successor,
            operation
        )
        try #require(accepted.status == .ok)
        guard case .object(let updated) = try ShoppingFixture.object(accepted)["group"] else {
            throw APIProblem.invalidRequest
        }
        #expect(updated["administratorUserId"] == .string(successor.id.uuidString.lowercased()))
        #expect(updated["creatorUserId"] == .string(owner.id.uuidString.lowercased()))
        let replay = try await ShoppingFixture.request(
            .POST,
            path,
            successor,
            operation
        )
        #expect(replay.body.string == accepted.body.string)
        let original = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/invitations", owner)
        #expect(original.status == .forbidden)
        #expect(try ShoppingFixture.object(original)["code"] == .string("administrator_required"))
        let revoked = try await ShoppingFixture.request(
            .DELETE,
            "/v1/groups/\(group)/invitations/\(invitation.id.uuidString.lowercased())",
            successor
        )
        #expect(revoked.status == .noContent)
        let membership = try await ShoppingFixture.request(.GET, "/v1/me", owner)
        guard case .object(let retained) = try ShoppingFixture.object(membership)["group"] else {
            throw APIProblem.invalidRequest
        }
        #expect(retained["id"] == .string(group))
        #expect(try await AdministrationFixture.itemSnapshot(group: group) == history)
        let snapshot = try await AdministrationFixture.snapshot(successor, group: group)
        guard case .object(let capabilities) = snapshot["capabilities"] else { throw APIProblem.invalidRequest }
        #expect(capabilities["capacityOwnerUserId"] == .string(successor.id.uuidString.lowercased()))
        #expect(capabilities["canManageInvitations"] == .bool(true))
        #expect(snapshot["pendingTransfer"] == .null)
        try await ShoppingFixture.depart(owner, group: group)
        let newGroup = try await ShoppingFixture.group(owner)
        #expect(newGroup != group)
        let preserved = try await AdministrationFixture.snapshot(successor, group: group)
        #expect(preserved["memberCount"] == .integer(1))
    }

    @Test(
        "Rejecting or withdrawing frees the proposal slot without changing administration",
        arguments: ["reject", "withdraw"]
    )
    func proposalResolution(action: String) async throws {
        let owner = try await ShoppingFixture.user()
        let recipient = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(recipient, group: group)
        let id = try await AdministrationFixture.propose(owner, recipient: recipient, group: group)
        let pending = try await AdministrationFixture.snapshot(recipient, group: group)
        guard case .object(let capabilities) = pending["capabilities"] else { throw APIProblem.invalidRequest }
        #expect(capabilities["canAcceptTransfer"] == .bool(true))
        #expect(capabilities["canRejectTransfer"] == .bool(true))
        let another = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/administration-transfers",
            owner,
            AdministrationFixture.proposalBody(recipient)
        )
        #expect(another.status == .conflict)
        #expect(try ShoppingFixture.object(another)["code"] == .string("transfer_pending"))
        let resolved = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/administration-transfers/\(id)/\(action)",
            action == "reject" ? recipient : owner,
            AdministrationFixture.operation()
        )
        try #require(resolved.status == .ok)
        guard case .object(let transfer) = try ShoppingFixture.object(resolved)["transfer"] else {
            throw APIProblem.invalidRequest
        }
        #expect(transfer["status"] == .string(action == "reject" ? "rejected" : "withdrawn"))
        let late = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/administration-transfers/\(id)/accept",
            recipient,
            AdministrationFixture.operation()
        )
        #expect(late.status == .conflict)
        #expect(try ShoppingFixture.object(late)["code"] == .string("transfer_not_pending"))
        _ = try await AdministrationFixture.propose(owner, recipient: recipient, group: group)
    }

    @Test("Transfer authorization rejects foreign, self and nonmember recipients without changing responsibility")
    func transferAuthorization() async throws {
        let owner = try await ShoppingFixture.user()
        let recipient = try await ShoppingFixture.user()
        let outsider = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(recipient, group: group)
        for target in [owner, outsider] {
            let denied = try await ShoppingFixture.request(
                .POST,
                "/v1/groups/\(group)/administration-transfers",
                owner,
                AdministrationFixture.proposalBody(target)
            )
            #expect(denied.status == .conflict)
            #expect(try ShoppingFixture.object(denied)["code"] == .string("invalid_transfer_recipient"))
        }
        let deniedMember = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/administration-transfers",
            recipient,
            AdministrationFixture.proposalBody(owner)
        )
        #expect(deniedMember.status == .forbidden)
        let id = try await AdministrationFixture.propose(owner, recipient: recipient, group: group)
        let deniedOwner = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/administration-transfers/\(id)/accept",
            owner,
            AdministrationFixture.operation()
        )
        #expect(deniedOwner.status == .forbidden)
        #expect(try ShoppingFixture.object(deniedOwner)["code"] == .string("transfer_recipient_required"))
        let deniedOutsider = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/administration", outsider)
        #expect(deniedOutsider.status == .notFound)
        let snapshot = try await AdministrationFixture.snapshot(owner, group: group)
        #expect(snapshot["memberCount"] == .integer(2))
    }

    @Test("Persisted expiry prevents acceptance and permits a new proposal without a scheduled worker")
    func transferExpiry() async throws {
        let owner = try await ShoppingFixture.user()
        let recipient = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(recipient, group: group)
        let id = try await AdministrationFixture.propose(owner, recipient: recipient, group: group)
        let sql = try shoppingSQL(database)
        let duration = try #require(try await sql.raw("""
            SELECT EXTRACT(EPOCH FROM expires_at - created_at)::bigint AS seconds
            FROM group_administration_transfers WHERE id = \(bind: id)::uuid
            """).first())
        #expect(try duration.decode(column: "seconds", as: Int64.self) == 604_800)
        try await sql.raw("""
            UPDATE group_administration_transfers SET created_at = clock_timestamp() - INTERVAL '8 days',
                expires_at = clock_timestamp() - INTERVAL '1 day' WHERE id = \(bind: id)::uuid
            """).run()
        let expired = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/administration-transfers/\(id)/accept",
            recipient,
            AdministrationFixture.operation()
        )
        #expect(expired.status == .conflict)
        let snapshot = try await AdministrationFixture.snapshot(recipient, group: group)
        #expect(snapshot["pendingTransfer"] == .null)
        guard case .object(let capabilities) = snapshot["capabilities"] else { throw APIProblem.invalidRequest }
        #expect(capabilities["canAcceptTransfer"] == .bool(false))
        _ = try await AdministrationFixture.propose(owner, recipient: recipient, group: group)
        let previous = try #require(try await sql.raw("""
            SELECT status, resolved_at FROM group_administration_transfers WHERE id = \(bind: id)::uuid
            """).first())
        #expect(try previous.decode(column: "status", as: String.self) == "expired")
        #expect(try previous.decode(column: "resolved_at", as: Date?.self) != nil)
    }

    @Test("Departure preserves responsibility and atomically invalidates the departing recipients proposal")
    func departureInvalidatesProposal() async throws {
        let owner = try await ShoppingFixture.user()
        let recipient = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(recipient, group: group)
        let id = try await AdministrationFixture.propose(owner, recipient: recipient, group: group)
        let denialBody = AdministrationFixture.departureBody(confirmClosure: true)
        let denied = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/departure",
            owner,
            denialBody
        )
        #expect(denied.status == .conflict)
        #expect(try ShoppingFixture.object(denied)["code"] == .string("transfer_required"))
        try await ShoppingFixture.depart(recipient, group: group)
        let repeated = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/departure",
            owner,
            denialBody
        )
        #expect(repeated.body.string == denied.body.string)
        let after = try await AdministrationFixture.snapshot(owner, group: group)
        #expect(after["memberCount"] == .integer(1))
        #expect(after["pendingTransfer"] == .null)
        guard case .object(let capabilities) = after["capabilities"] else { throw APIProblem.invalidRequest }
        #expect(capabilities["canLeave"] == .bool(true))
        #expect(capabilities["requiresClosureConfirmation"] == .bool(true))
        let late = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/administration-transfers/\(id)/accept",
            recipient,
            AdministrationFixture.operation()
        )
        #expect(late.status == .notFound)
        let sql = try shoppingSQL(database)
        let row = try #require(try await sql.raw("""
            SELECT status FROM group_administration_transfers WHERE id = \(bind: id)::uuid
            """).first())
        #expect(try row.decode(column: "status", as: String.self) == "invalidated")
    }
}

enum AdministrationFixture {
    static func seedHistory(_ user: ShoppingFixture.User, group: String) async throws -> [String] {
        let fixture = try await PurchaseFixture.items(user, group: group)
        let purchase = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/purchases",
            user,
            PurchaseFixture.body(store: fixture.store, ids: [fixture.ids[0]])
        )
        try #require(purchase.status == .ok)
        let cancellation = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/items/\(fixture.ids[1])/cancellation",
            user,
            .object(["operationId": .string(UUID().uuidString.lowercased()), "expectedVersion": .integer(1)])
        )
        try #require(cancellation.status == .ok)
        let snapshot = try await itemSnapshot(group: group)
        try #require(snapshot.count == 6)
        return snapshot
    }

    static func itemSnapshot(group: String) async throws -> [String] {
        let sql = try shoppingSQL(database)
        let rows = try await sql.raw("""
            SELECT to_jsonb(items)::text AS snapshot FROM items WHERE group_id = \(bind: group)::uuid ORDER BY id
            """).all()
        return try rows.map { try $0.decode(column: "snapshot", as: String.self) }
    }

    static func operation() -> APIJSON {
        .object(["operationId": .string(UUID().uuidString.lowercased())])
    }

    static func proposalBody(_ recipient: ShoppingFixture.User) -> APIJSON {
        .object([
            "operationId": .string(UUID().uuidString.lowercased()),
            "recipientUserId": .string(recipient.id.uuidString.lowercased())
        ])
    }

    static func departureBody(confirmClosure: Bool) -> APIJSON {
        .object(["operationId": .string(UUID().uuidString.lowercased()), "confirmClosure": .bool(confirmClosure)])
    }

    static func propose(
        _ owner: ShoppingFixture.User,
        recipient: ShoppingFixture.User,
        group: String
    ) async throws -> String {
        let response = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/administration-transfers",
            owner,
            proposalBody(recipient)
        )
        try #require(response.status == .created)
        guard case .object(let transfer) = try ShoppingFixture.object(response)["transfer"] else {
            throw APIProblem.invalidRequest
        }
        return try #require(transfer["id"]?.string)
    }

    static func snapshot(_ user: ShoppingFixture.User, group: String) async throws -> [String: APIJSON] {
        let response = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/administration", user)
        try #require(response.status == .ok)
        return try ShoppingFixture.object(response)
    }
}

extension ShoppingFixture {
    static func depart(_ user: User, group: String) async throws {
        let response = try await request(
            .POST,
            "/v1/groups/\(group)/departure",
            user,
            AdministrationFixture.departureBody(confirmClosure: true)
        )
        try #require(response.status == .ok)
    }
}
