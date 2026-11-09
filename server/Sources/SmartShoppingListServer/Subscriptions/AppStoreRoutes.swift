import Foundation
import Vapor

struct AppStoreRoutes: RouteCollection, Sendable {
    let service: SubscriptionService
    let authentication: any SessionAuthenticating
    var recovery: SubscriptionRecoveryService? = nil

    func boot(routes: any RoutesBuilder) throws {
        let version = routes.grouped("v1").grouped(APIErrorMiddleware())
        version.post("account", "subscription", "recovery-challenges") { request async throws -> Response in
            let user = try await authentication.authenticate(request)
            guard let recovery else { throw SubscriptionService.problem("subscription_unavailable") }
            let body = try APIObject.body(
                request,
                allowed: ["signedTransaction", "keyId"],
                required: ["signedTransaction", "keyId"]
            )
            do {
                return try await APIEncoding.response(
                    recovery.challenge(user: user, signed: body.string("signedTransaction"), keyID: body.string("keyId")),
                    status: .created
                )
            } catch let error as AppStoreGatewayError {
                throw error == .rejected ? SubscriptionRecoveryService.rejected
                    : SubscriptionService.problem("subscription_unavailable")
            }
        }
        version.post("account", "subscription", "recovery") { request async throws -> Response in
            let user = try await authentication.authenticate(request)
            guard let recovery else { throw SubscriptionService.problem("subscription_unavailable") }
            let body = try APIObject.body(
                request,
                allowed: ["challengeId", "keyId", "attestation", "signedTransaction"],
                required: ["challengeId", "keyId", "attestation", "signedTransaction"]
            )
            guard let id = UUID(uuidString: try body.string("challengeId")),
                  let proof = Data(base64Encoded: try body.string("attestation"))
            else {
                throw SubscriptionRecoveryService.rejected
            }
            do {
                return try await APIEncoding.response(recovery.recover(
                    user: user,
                    challengeID: id,
                    keyID: body.string("keyId"),
                    attestation: proof,
                    signed: body.string("signedTransaction")
                ))
            } catch let error as AppStoreGatewayError {
                throw error == .rejected ? SubscriptionRecoveryService.rejected
                    : SubscriptionService.problem("subscription_unavailable")
            }
        }
        version.get("account", "subscription") { request async throws -> Response in
            let user = try await authentication.authenticate(request)
            return try await APIEncoding.response(service.status(user: user).json)
        }
        version.post(
            "account",
            "subscription",
            "transactions"
        ) { request async throws -> Response in
            let user = try await authentication.authenticate(request)
            let body = try APIObject.body(request, allowed: ["signedTransaction"], required: ["signedTransaction"])
            return try await APIEncoding.response(service.submit(user: user, signed: body.string("signedTransaction")))
        }
        version.post("app-store", "notifications") { request async throws -> Response in
            let body = try APIObject.body(request, allowed: ["signedPayload"], required: ["signedPayload"])
            try await service.notification(signed: body.string("signedPayload"))
            return Response(status: .noContent)
        }
    }
}
