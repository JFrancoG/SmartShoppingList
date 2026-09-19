import Foundation

struct SharedAPIConfiguration: Equatable {
    private let apiOrigin: URL
    private let linkOrigin: URL

    var baseURL: URL { apiOrigin }
    var invitationOrigin: URL { linkOrigin }

    func invitation(from url: URL) throws(SharedAPIError) -> PendingInvitation {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let origin = URLComponents(url: linkOrigin, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host?.lowercased() == origin.host?.lowercased(),
              (parts.port ?? 443) == (origin.port ?? 443), parts.user == nil, parts.password == nil,
              parts.query == nil, let fragment = parts.percentEncodedFragment,
              fragment.hasPrefix("token=") else {
            throw .invalidInvitation
        }

        let components = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 3, components[0].isEmpty, components[1] == "invite",
              let identifier = UUID(uuidString: String(components[2])),
              identifier.uuidString.lowercased() == components[2] else {
            throw .invalidInvitation
        }
        let token = String(fragment.dropFirst("token=".count))
        guard Self.isCanonicalSecret(token) else { throw .invalidInvitation }
        return PendingInvitation(id: identifier, token: token)
    }

    static func isCanonicalSecret(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 43, let last = bytes.last, "AEIMQUYcgkosw048".utf8.contains(last) else { return false }
        return bytes.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
}

extension SharedAPIConfiguration {
    init(baseURL: String, invitationOrigin: String) throws(SharedAPIError) {
        guard let api = Self.httpsOrigin(baseURL), let links = Self.httpsOrigin(invitationOrigin) else {
            throw .configuration
        }
        apiOrigin = api
        linkOrigin = links
    }

    init(bundle: Bundle = .main) throws(SharedAPIError) {
        guard let api = bundle.object(forInfoDictionaryKey: "SharedAPIBaseURL") as? String,
              let links = bundle.object(forInfoDictionaryKey: "SharedInvitationOrigin") as? String else {
            throw .configuration
        }
        try self.init(baseURL: api, invitationOrigin: links)
    }

    private static func httpsOrigin(_ text: String) -> URL? {
        guard let parts = URLComponents(string: text), parts.scheme == "https",
              let host = parts.host, !host.isEmpty,
              !host.lowercased().hasSuffix(".example"), host.lowercased() != "example", !host.contains("$("),
              parts.user == nil, parts.password == nil,
              parts.path.isEmpty || parts.path == "/", parts.query == nil, parts.fragment == nil,
              parts.port == nil || (1...65535).contains(parts.port ?? 0),
              let url = parts.url else {
            return nil
        }
        return url
    }
}
