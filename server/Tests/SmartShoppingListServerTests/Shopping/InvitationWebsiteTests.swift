@testable import SmartShoppingListServer
import Foundation
import FluentSQL
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test("A public invitation page neither reveals the group nor consumes its invitation")
    func invitationLandingIsPassive() async throws {
        let owner = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let invitation = try await ShoppingFixture.invitation(group)
        let page = try await app.sendRequest(.GET, "/invite/\(invitation.id.uuidString.lowercased())")
        #expect(page.status == .ok)
        #expect(!page.body.string.contains(invitation.secret))
        #expect(!page.body.string.contains(group))
        #expect(page.headers.first(name: "Referrer-Policy") == "no-referrer")
        let sql = try shoppingSQL(database)
        let persisted = try #require(try await sql.raw("""
            SELECT accepted_by, revoked_at FROM invitations WHERE id = \(bind: invitation.id)
            """).first())
        #expect(try persisted.decode(column: "accepted_by", as: UUID?.self) == nil)
        #expect(try persisted.decode(column: "revoked_at", as: Date?.self) == nil)
    }

    @Test("AASA grants the configured app only invitation paths without excluding fragments")
    func associationKeepsInvitationFragments() async throws {
        let response = try await app.sendRequest(.GET, "/.well-known/apple-app-site-association")
        try #require(response.status == .ok)
        let actual = try JSONDecoder().decode(APIJSON.self, from: Data(response.body.readableBytesView))
        let expected: APIJSON = .object([
            "applinks": .object([
                "details": .array([.object([
                    "appIDs": .array([.string("NWN8JUE438.com.plusprojects.SmartShoppingList")]),
                    "components": .array([.object(["/": .string("/invite/*")])])
                ])])
            ])
        ])
        #expect(actual == expected)
    }
}
