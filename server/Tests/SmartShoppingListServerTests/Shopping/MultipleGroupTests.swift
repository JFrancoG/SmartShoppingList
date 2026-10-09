@testable import SmartShoppingListServer
import FluentKit
import FluentSQL
import Foundation
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test("An expanded account administers two groups and pages only its memberships with account-bound cursors")
    func multipleGroupsAndAccountCapacity() async throws {
        try await MembershipFixture.withCapacity(2) {
            let owner = try await ShoppingFixture.user()
            let outsider = try await ShoppingFixture.user()
            let empty = try await ShoppingFixture.request(.GET, "/v1/me", owner)
            #expect(try MembershipFixture.capabilities(empty)["membershipCount"] == .integer(0))
            #expect(try MembershipFixture.capabilities(empty)["canCreateGroup"] == .bool(true))
            let first = try await ShoppingFixture.group(owner)
            let second = try await ShoppingFixture.group(owner)
            let me = try await ShoppingFixture.request(.GET, "/v1/me", owner)
            let capabilities = try MembershipFixture.capabilities(me)
            #expect(capabilities["membershipCount"] == .integer(2))
            #expect(capabilities["canCreateGroup"] == .bool(false))
            #expect(capabilities["canJoinGroup"] == .bool(false))
            #expect(try MembershipFixture.legacyGroup(me) == first)
            let page = try await ShoppingFixture.request(.GET, "/v1/groups?limit=1", owner)
            #expect(try MembershipFixture.groupIDs(page) == [first])
            let cursor = try #require(try ShoppingFixture.object(page)["nextCursor"]?.string)
            let next = try await ShoppingFixture.request(.GET, "/v1/groups?limit=1&cursor=\(cursor)", owner)
            #expect(try MembershipFixture.groupIDs(next) == [second])
            #expect(try ShoppingFixture.object(next)["nextCursor"] == .null)
            let foreign = try await ShoppingFixture.request(.GET, "/v1/groups?cursor=\(cursor)", outsider)
            #expect(foreign.status == .badRequest)
            let emptyGroups = try await ShoppingFixture.request(.GET, "/v1/groups", outsider)
            #expect(try MembershipFixture.groupIDs(emptyGroups).isEmpty)
            for group in [first, second] {
                let admin = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/administration", owner)
                guard case .object(let fields) = try ShoppingFixture.object(admin)["group"] else {
                    throw APIProblem.invalidRequest
                }
                #expect(fields["administratorUserId"] == .string(owner.id.uuidString.lowercased()))
                let denied = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/stores", outsider)
                #expect(denied.status == .notFound)
            }
            let closed = try await MembershipFixture.depart(owner, group: first)
            #expect(closed.status == .ok)
            let remaining = try await ShoppingFixture.request(.GET, "/v1/groups", owner)
            #expect(try MembershipFixture.groupIDs(remaining) == [second])
            let after = try await ShoppingFixture.request(.GET, "/v1/me", owner)
            #expect(try MembershipFixture.legacyGroup(after) == nil)
            #expect(try MembershipFixture.capabilities(after)["membershipCount"] == .integer(1))
            #expect(try MembershipFixture.capabilities(after)["canCreateGroup"] == .bool(true))
            let stillAccessible = try await ShoppingFixture.request(.GET, "/v1/groups/\(second)/administration", owner)
            #expect(stillAccessible.status == .ok)
        }
    }

    @Test("Admission quotas persist creation conflicts but leave invitations available for a later free slot")
    func groupAdmissionQuotaAndRetry() async throws {
        let user = try await ShoppingFixture.user()
        let inviter = try await ShoppingFixture.user()
        let own = try await ShoppingFixture.group(user)
        let destination = try await ShoppingFixture.group(inviter)
        let invitation = try await ShoppingFixture.invitation(destination)
        let intention = MembershipFixture.creationBody()
        let denied = try await ShoppingFixture.request(
            .POST,
            "/v1/groups",
            user,
            intention
        )
        #expect(denied.status == .conflict)
        #expect(try ShoppingFixture.object(denied)["code"] == .string("group_limit_reached"))
        let join = try await MembershipFixture.accept(invitation, user: user)
        #expect(join.status == .conflict)
        #expect(try ShoppingFixture.object(join)["code"] == .string("group_limit_reached"))
        let sql = try shoppingSQL(database)
        let unconsumed = try #require(try await sql.raw("""
            SELECT accepted_by FROM invitations WHERE id = \(bind: invitation.id)
            """).first())
        #expect(try unconsumed.decode(column: "accepted_by", as: UUID?.self) == nil)
        _ = try await MembershipFixture.depart(user, group: own)
        let repeated = try await ShoppingFixture.request(
            .POST,
            "/v1/groups",
            user,
            intention
        )
        #expect(repeated.body.string == denied.body.string)
        let accepted = try await MembershipFixture.accept(invitation, user: user)
        #expect(accepted.status == .ok)
        let me = try await ShoppingFixture.request(.GET, "/v1/me", user)
        #expect(try MembershipFixture.legacyGroup(me) == destination)
        #expect(try MembershipFixture.capabilities(me)["membershipCount"] == .integer(1))
        let another = try await ShoppingFixture.invitation(destination)
        #expect(try await MembershipFixture.accept(another, user: user).status == .ok)
        let after = try await ShoppingFixture.request(.GET, "/v1/me", user)
        #expect(try MembershipFixture.capabilities(after)["membershipCount"] == .integer(1))
        _ = try await MembershipFixture.depart(user, group: destination)
        #expect(try await MembershipFixture.accept(another, user: user).status == .gone)
    }

    @Test("Replays use explicit membership and leaving the legacy group never mutates another group")
    func multipleGroupReplayAndDeparture() async throws {
        try await MembershipFixture.withCapacity(2) {
            let user = try await ShoppingFixture.user()
            let first = try await ShoppingFixture.group(user)
            let creation = MembershipFixture.creationBody()
            let created = try await ShoppingFixture.request(
                .POST,
                "/v1/groups",
                user,
                creation
            )
            let second = try #require(try ShoppingFixture.object(created)["id"]?.string)
            let path = "/v1/groups/\(second)/item-batches"
            let batch = ShoppingFixture.batch(names: ["Pan"], stores: ["Tienda"])
            let addition = try await ShoppingFixture.request(
                .POST,
                path,
                user,
                batch
            )
            try #require(addition.status == .created)
            let before = try await AdministrationFixture.itemSnapshot(group: second)
            let departure = AdministrationFixture.departureBody(confirmClosure: true)
            let departed = try await ShoppingFixture.request(
                .POST,
                "/v1/groups/\(first)/departure",
                user,
                departure
            )
            #expect(departed.status == .ok)
            let replay = try await ShoppingFixture.request(
                .POST,
                "/v1/groups",
                user,
                creation
            )
            #expect(replay.body.string == created.body.string)
            let replayItems = try await ShoppingFixture.request(
                .POST,
                path,
                user,
                batch
            )
            #expect(replayItems.body.string == addition.body.string)
            let me = try await ShoppingFixture.request(.GET, "/v1/me", user)
            #expect(try MembershipFixture.legacyGroup(me) == nil)
            let third = try await ShoppingFixture.group(user)
            let departureReplay = try await ShoppingFixture.request(
                .POST,
                "/v1/groups/\(first)/departure",
                user,
                departure
            )
            #expect(departureReplay.body.string == departed.body.string)
            let current = try await ShoppingFixture.request(.GET, "/v1/groups", user)
            #expect(Set(try MembershipFixture.groupIDs(current)) == [second, third])
            #expect(try await AdministrationFixture.itemSnapshot(group: second) == before)
            let crossGroup = try await ShoppingFixture.request(
                .POST,
                "/v1/groups/\(third)/item-batches",
                user,
                batch
            )
            #expect(crossGroup.status == .conflict)
            #expect(try ShoppingFixture.object(crossGroup)["code"] == .string("idempotency_key_reused"))
            _ = try await MembershipFixture.depart(user, group: second)
            #expect(try await ShoppingFixture.request(
                .POST,
                "/v1/groups",
                user,
                creation
            ).status == .notFound)
            #expect(try await ShoppingFixture.request(
                .POST,
                path,
                user,
                batch
            ).status == .notFound)
        }
    }

    @Test(
        "An existing member can receive another administration at capacity without changing membership or its legacy group"
    )
    func multipleAdministrationsStayGroupScoped() async throws {
        try await MembershipFixture.withCapacity(2) {
            let owner = try await ShoppingFixture.user()
            let recipient = try await ShoppingFixture.user()
            let own = try await ShoppingFixture.group(recipient)
            let shared = try await ShoppingFixture.group(owner)
            let invitation = try await ShoppingFixture.invitation(shared)
            #expect(try await MembershipFixture.accept(invitation, user: recipient).status == .ok)
            let before = try await ShoppingFixture.request(.GET, "/v1/groups/\(shared)/invitations", recipient)
            #expect(before.status == .forbidden)
            let transfer = try await AdministrationFixture.propose(owner, recipient: recipient, group: shared)
            let accepted = try await ShoppingFixture.request(
                .POST,
                "/v1/groups/\(shared)/administration-transfers/\(transfer)/accept",
                recipient,
                AdministrationFixture.operation()
            )
            #expect(accepted.status == .ok)
            let me = try await ShoppingFixture.request(.GET, "/v1/me", recipient)
            #expect(try MembershipFixture.legacyGroup(me) == own)
            #expect(try MembershipFixture.capabilities(me)["membershipCount"] == .integer(2))
            for group in [own, shared] {
                #expect(
                    try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/invitations", recipient).status == .ok
                )
            }
            #expect(
                try await ShoppingFixture.request(.GET, "/v1/groups/\(shared)/invitations", owner).status == .forbidden
            )
            #expect(try await ShoppingFixture.request(.GET, "/v1/groups/\(own)/invitations", owner).status == .notFound)
            _ = try await MembershipFixture.depart(owner, group: shared)
            let remaining = try await ShoppingFixture.request(.GET, "/v1/groups", recipient)
            #expect(Set(try MembershipFixture.groupIDs(remaining)) == [own, shared])
        }
    }
}

enum MembershipFixture {
    static func withCapacity(
        _ maximum: Int64,
        perform: @Sendable () async throws -> Void
    ) async throws {
        let application = try await Application.make(.testing)
        application.middleware.use(APIErrorMiddleware(), at: .end)
        do {
            try routes(
                application,
                databases: testDatabases,
                accountCapacity: AccountCapacityPolicy(maximumGroups: { _ in maximum })
            )
            try await application.asyncBoot()
            try await $_application.withValue(application) {
                try await perform()
            }
            try await application.asyncShutdown()
        } catch {
            try await application.asyncShutdown()
            throw error
        }
    }

    static func creationBody() -> APIJSON {
        .object(["operationId": .string(UUID().uuidString.lowercased()), "name": .string("Otro grupo")])
    }

    static func capabilities(_ response: TestingHTTPResponse) throws -> [String: APIJSON] {
        guard case .object(let fields) = try ShoppingFixture.object(response)["accountCapabilities"] else {
            throw APIProblem.invalidRequest
        }
        return fields
    }

    static func legacyGroup(_ response: TestingHTTPResponse) throws -> String? {
        guard case .object(let fields) = try ShoppingFixture.object(response)["group"] else { return nil }
        return fields["id"]?.string
    }

    static func groupIDs(_ response: TestingHTTPResponse) throws -> [String] {
        guard case .array(let values) = try ShoppingFixture.object(response)["data"] else {
            throw APIProblem.invalidRequest
        }
        return try values.map { value in
            guard case .object(let fields) = value, let id = fields["id"]?.string else {
                throw APIProblem.invalidRequest
            }
            return id
        }
    }

    static func accept(
        _ invitation: ShoppingFixture.Invitation,
        user: ShoppingFixture.User
    ) async throws -> TestingHTTPResponse {
        try await ShoppingFixture.request(
            .POST,
            "/v1/invitations/\(invitation.id.uuidString.lowercased())/accept",
            user,
            .object(["token": .string(invitation.secret)])
        )
    }

    static func depart(_ user: ShoppingFixture.User, group: String) async throws -> TestingHTTPResponse {
        try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/departure",
            user,
            AdministrationFixture.departureBody(confirmClosure: true)
        )
    }
}
