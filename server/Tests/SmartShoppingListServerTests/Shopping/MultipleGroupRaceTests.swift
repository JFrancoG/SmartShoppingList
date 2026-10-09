@testable import SmartShoppingListServer
import FluentKit
import FluentSQL
import Foundation
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test("Concurrent admissions to different groups share one account allowance", .timeLimit(.minutes(1)))
    func concurrentGroupAdmissionsRespectAccountCapacity() async throws {
        let firstOwner = try await ShoppingFixture.user()
        let secondOwner = try await ShoppingFixture.user()
        let joining = try await ShoppingFixture.user()
        let firstGroup = try await ShoppingFixture.group(firstOwner)
        let secondGroup = try await ShoppingFixture.group(secondOwner)
        let firstInvite = try await ShoppingFixture.invitation(firstGroup)
        let secondInvite = try await ShoppingFixture.invitation(secondGroup)
        let responses = try await ShoppingFixture.overlappingRequests(
            lockedBy: "SELECT id FROM users WHERE id = \(bind: joining.id) FOR UPDATE",
            waitingQuery: "%FROM users%FOR NO KEY UPDATE%",
            first: {
                try await MembershipFixture.accept(firstInvite, user: joining)
            },
            second: {
                try await MembershipFixture.accept(secondInvite, user: joining)
            }
        )
        #expect(responses.0.status == .ok)
        #expect(responses.1.status == .conflict)
        #expect(try ShoppingFixture.object(responses.1)["code"] == .string("group_limit_reached"))
        let groups = try await ShoppingFixture.request(.GET, "/v1/groups", joining)
        #expect(try MembershipFixture.groupIDs(groups) == [firstGroup])
        let sql = try shoppingSQL(database)
        let unconsumed = try #require(try await sql.raw("""
            SELECT accepted_by FROM invitations WHERE id = \(bind: secondInvite.id)
            """).first())
        #expect(try unconsumed.decode(column: "accepted_by", as: UUID?.self) == nil)
    }

    @Test(
        "Creating and joining concurrently cannot each consume the final account slot",
        .timeLimit(.minutes(1)),
        arguments: [true, false]
    )
    func creationAndAdmissionShareCapacity(createFirst: Bool) async throws {
        let owner = try await ShoppingFixture.user()
        let joining = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let invitation = try await ShoppingFixture.invitation(group)
        let body = MembershipFixture.creationBody()
        let create: @Sendable () async throws -> TestingHTTPResponse = {
            try await ShoppingFixture.request(
                .POST,
                "/v1/groups",
                joining,
                body
            )
        }
        let join: @Sendable () async throws -> TestingHTTPResponse = {
            try await MembershipFixture.accept(invitation, user: joining)
        }
        let responses = try await ShoppingFixture.overlappingRequests(
            lockedBy: "SELECT id FROM users WHERE id = \(bind: joining.id) FOR UPDATE",
            waitingQuery: "%FROM users%FOR NO KEY UPDATE%",
            first: createFirst ? create : join,
            second: createFirst ? join : create
        )
        #expect(responses.0.status == (createFirst ? .created : .ok))
        #expect(responses.1.status == .conflict)
        let me = try await ShoppingFixture.request(.GET, "/v1/me", joining)
        #expect(try MembershipFixture.capabilities(me)["membershipCount"] == .integer(1))
        let sql = try shoppingSQL(database)
        let persisted = try #require(try await sql.raw("""
            SELECT accepted_by FROM invitations WHERE id = \(bind: invitation.id)
            """).first())
        #expect(try persisted.decode(column: "accepted_by", as: UUID?.self) == (createFirst ? nil : joining.id))
        let created = try await sql.raw("SELECT id FROM groups WHERE creator_user_id = \(bind: joining.id)").all()
        #expect(created.count == (createFirst ? 1 : 0))
    }

    @Test("Reciprocal transfers in different groups complete without foreign-key deadlock", .timeLimit(.minutes(1)))
    func reciprocalTransfersAcrossGroups() async throws {
        try await MembershipFixture.withCapacity(2) {
            let first = try await ShoppingFixture.user()
            let second = try await ShoppingFixture.user()
            let firstGroup = try await ShoppingFixture.group(first)
            let secondGroup = try await ShoppingFixture.group(second)
            try await ShoppingFixture.join(second, group: firstGroup)
            try await ShoppingFixture.join(first, group: secondGroup)
            let firstProposal: APIJSON = .object([
                "operationId": .string(UUID().uuidString.lowercased()),
                "recipientUserId": .string(second.id.uuidString.lowercased())
            ])
            let secondProposal: APIJSON = .object([
                "operationId": .string(UUID().uuidString.lowercased()),
                "recipientUserId": .string(first.id.uuidString.lowercased())
            ])
            // Both requests reach transfer refresh holding their group and account locks before either recipient FK runs.
            let responses = try await ShoppingFixture.overlappingRequests(
                lockedBy: "LOCK TABLE group_administration_transfers IN SHARE MODE",
                waitingQuery: "%UPDATE group_administration_transfers%",
                first: {
                    try await ShoppingFixture.request(
                        .POST,
                        "/v1/groups/\(firstGroup)/administration-transfers",
                        first,
                        firstProposal
                    )
                },
                second: {
                    try await ShoppingFixture.request(
                        .POST,
                        "/v1/groups/\(secondGroup)/administration-transfers",
                        second,
                        secondProposal
                    )
                }
            )
            #expect(responses.0.status == .created)
            #expect(responses.1.status == .created)
            let sql = try shoppingSQL(database)
            let proposals = try await sql.raw(
                "SELECT group_id FROM group_administration_transfers WHERE status = 'pending'"
            ).all()
            #expect(Set(try proposals.map { try $0.decode(column: "group_id", as: UUID.self).uuidString.lowercased() })
                == [firstGroup, secondGroup])
        }
    }
}
