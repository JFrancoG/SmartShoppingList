import Foundation
import JWTKit
import Vapor

enum AppStoreEnvironment: String, Codable, Sendable {
    case production = "Production"
    case sandbox = "Sandbox"

    var origin: String {
        switch self {
        case .production: "https://api.storekit.apple.com"
        case .sandbox: "https://api.storekit-sandbox.apple.com"
        }
    }
}

/// Server credentials opt in to Apple verification; these values never grant premium themselves.
struct AppStoreConfiguration: Sendable {
    let bundleID: String
    let appAppleID: Int64
    let subscriptionGroupID: String
    let issuerID: String
    let keyID: String
    let privateKeyPEM: String
    let monthlyProductID: String
    let annualProductID: String
    let environment: AppStoreEnvironment

    var productIDs: [String] { [monthlyProductID, annualProductID] }

    static func load(environment value: (String) -> String? = Environment.get) throws -> Self? {
        let names = [
            "APP_STORE_BUNDLE_ID", "APP_STORE_APP_ID", "APP_STORE_ISSUER_ID", "APP_STORE_KEY_ID",
            "APP_STORE_PRIVATE_KEY_PEM", "APP_STORE_PREMIUM_MONTHLY_PRODUCT_ID",
            "APP_STORE_PREMIUM_ANNUAL_PRODUCT_ID", "APP_STORE_ENVIRONMENT", "APP_STORE_SUBSCRIPTION_GROUP_ID"
        ]
        let values = names.map(value)
        guard values.contains(where: { $0 != nil }) else { return nil }
        guard values.allSatisfy({ $0?.isEmpty == false }),
              let appID = values[1].flatMap(Int64.init), appID > 0,
              let issuerID = values[2], UUID(uuidString: issuerID) != nil,
              let deployment = values[7].flatMap(AppStoreEnvironment.init(rawValue:)),
              let bundleID = values[0], let keyID = values[3], let pem = values[4],
              let monthly = values[5], let annual = values[6], monthly != annual,
              let group = values[8], AppStoreTransaction.isTransactionID(group),
              bundleID == "com.plusprojects.SmartShoppingList", keyID.utf8.count == 10,
              keyID.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) })
        else {
            throw AppStoreGatewayError.invalidConfiguration
        }
        do {
            _ = try ES256PrivateKey(pem: pem)
        } catch {
            throw AppStoreGatewayError.invalidConfiguration
        }
        return Self(
            bundleID: bundleID,
            appAppleID: appID,
            subscriptionGroupID: group,
            issuerID: issuerID,
            keyID: keyID,
            privateKeyPEM: pem,
            monthlyProductID: monthly,
            annualProductID: annual,
            environment: deployment
        )
    }

    func authorization(now: Date) async throws -> String {
        do {
            let keys = JWTKeyCollection()
            await keys.add(ecdsa: try ES256PrivateKey(pem: privateKeyPEM), kid: .init(string: keyID))
            return try await keys.sign(
                APIAuthorization(
                    issuer: issuerID,
                    issuedAt: Int64(now.timeIntervalSince1970),
                    expiration: Int64(now.addingTimeInterval(300).timeIntervalSince1970),
                    audience: "appstoreconnect-v1",
                    bundleID: bundleID
                ),
                kid: .init(string: keyID)
            )
        } catch {
            throw AppStoreGatewayError.invalidConfiguration
        }
    }

    private struct APIAuthorization: JWTPayload {
        let issuer: String
        let issuedAt: Int64
        let expiration: Int64
        let audience: String
        let bundleID: String

        enum CodingKeys: String, CodingKey {
            case issuer = "iss"
            case issuedAt = "iat"
            case expiration = "exp"
            case audience = "aud"
            case bundleID = "bid"
        }

        func verify(using algorithm: some JWTAlgorithm) throws {
            guard algorithm.name == "ES256" else { throw AppStoreGatewayError.rejected }
        }
    }
}
