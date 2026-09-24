import Foundation
import Testing
@testable import SmartShoppingList

@Suite(.tags(.fast))
struct SharedAPIConfigurationTests {
    @Test
    func `A canonical invitation is retained for authentication`() throws {
        let config = try configuration()
        let url = try #require(URL(string: "https://links.test/invite/abcdef01-0000-4000-8000-000000000001#token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"))

        let invitation = try config.invitation(from: url)

        #expect(invitation.id.uuidString.lowercased() == "abcdef01-0000-4000-8000-000000000001")
        #expect(invitation.token == "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
    }

    @Test(arguments: [
        "http://links.test/invite/abcdef01-0000-4000-8000-000000000001#token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "https://evil.test/invite/abcdef01-0000-4000-8000-000000000001#token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "https://links.test.evil.test/invite/abcdef01-0000-4000-8000-000000000001#token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "https://person@links.test/invite/abcdef01-0000-4000-8000-000000000001#token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "https://links.test/invite/ABCDEF01-0000-4000-8000-000000000001#token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "https://links.test/invite/abcdef01-0000-4000-8000-000000000001/?token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "https://links.test/invite/abcdef01-0000-4000-8000-000000000001#token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "https://links.test/invite/abcdef01-0000-4000-8000-000000000001#token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB",
        "https://links.test/invite/abcdef01-0000-4000-8000-000000000001#token=%41AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "https://links.test/invite/abcdef01-0000-4000-8000-000000000001?tracking=1#token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    ])
    func `Untrusted or noncanonical invitations cannot enter saved authentication state`(_ rawURL: String) throws {
        let config = try configuration()
        let url = try #require(URL(string: rawURL))
        #expect(throws: SharedAPIError.invalidInvitation) {
            try config.invitation(from: url)
        }
    }

    @Test(arguments: [
        "",
        "http://127.0.0.1:8080",
        "https://api.smartshoppinglist.example",
        "https://api.test/v1",
        "https://u:p@api.test",
        "https://api.test?x=1",
        "$(SHARED_API_BASE_URL)"
    ])
    func `Missing insecure placeholder or path configurations cannot become a server`(_ origin: String) throws {
        #expect(throws: SharedAPIError.configuration) {
            try SharedAPIConfiguration(baseURL: origin, invitationOrigin: "https://links.test")
        }
    }

    private func configuration() throws -> SharedAPIConfiguration {
        try SharedAPIConfiguration(baseURL: "https://api.test", invitationOrigin: "https://links.test")
    }
}
