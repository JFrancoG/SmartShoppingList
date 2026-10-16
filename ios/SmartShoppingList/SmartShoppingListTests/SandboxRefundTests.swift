#if DEBUG
import Foundation
import StoreKit
import Testing
@testable import SmartShoppingList

@Suite(.tags(.fast))
struct SandboxRefundTests {
    private let owner = UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, 1))
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: ["production", "xcode", "foreign", "missingOwner", "expired", "revoked", "upgraded", "otherProduct"])
    func `Test refund cannot select a real purchase or an ineligible account transaction`(_ fault: String) {
        let candidate = SandboxRefundCandidate(
            id: 42,
            appAccountToken: fault == "missingOwner" ? nil : (fault == "foreign" ? UUID() : owner),
            productID: fault == "otherProduct" ? "other.product" : "premium.monthly",
            environment: fault == "production" ? .production : (fault == "xcode" ? .xcode : .sandbox),
            purchaseDate: now.addingTimeInterval(-60),
            expirationDate: fault == "expired" ? now : now.addingTimeInterval(60),
            revocationDate: fault == "revoked" ? now.addingTimeInterval(-10) : nil,
            isUpgraded: fault == "upgraded"
        )
        #expect(SandboxRefundCandidate.select(
            from: [candidate],
            appAccountToken: owner,
            productIDs: ["premium.monthly"],
            now: now
        ) == nil)
    }

    @Test
    func `Refund targets the newest eligible period regardless of entitlement enumeration order`() {
        let older = candidate(id: 12, purchasedAt: now.addingTimeInterval(-60))
        let newer = candidate(id: 34, purchasedAt: now.addingTimeInterval(-10))
        #expect(SandboxRefundCandidate.select(
            from: [newer, older],
            appAccountToken: owner,
            productIDs: ["premium.monthly"],
            now: now
        ) == 34)
        #expect(SandboxRefundCandidate.select(
            from: [older, newer],
            appAccountToken: owner,
            productIDs: ["premium.monthly"],
            now: now
        ) == 34)
    }

    @Test(arguments: ["production", "mixed", "wrongPort", "sandbox"])
    func `Refund testing is available only when both origins use the dedicated Sandbox backend`(_ setup: String) throws {
        let sandbox = "https://smartshoppinglistsandbox-sandbox.up.railway.app"
        let production = "https://smartshoppinglist-production.up.railway.app"
        let configuration = try SharedAPIConfiguration(
            baseURL: setup == "production" ? production : (setup == "wrongPort" ? sandbox + ":444" : sandbox),
            invitationOrigin: setup == "production" || setup == "mixed" ? production : sandbox
        )
        #expect(configuration.allowsSandboxRefundTesting == (setup == "sandbox"))
    }

    private func candidate(id: UInt64, purchasedAt: Date) -> SandboxRefundCandidate {
        SandboxRefundCandidate(
            id: id,
            appAccountToken: owner,
            productID: "premium.monthly",
            environment: .sandbox,
            purchaseDate: purchasedAt,
            expirationDate: now.addingTimeInterval(60),
            revocationDate: nil,
            isUpgraded: false
        )
    }
}
#endif
