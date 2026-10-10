import Foundation
import Testing
@testable import SmartShoppingList

@Suite(.tags(.fast))
@MainActor
struct PremiumSubscriptionTests {
    @Test
    func `Saved purchase verification completes even when Apple's product catalogue is unavailable`() async throws {
        let fixture = PremiumFixture()
        let api = PremiumAPI(status: fixture.status())
        let store = PremiumStore(transaction: fixture.transaction)
        await store.failCatalogue()
        let credentials = MemorySharedCredentialStore()
        let verification = PendingSubscriptionVerification(
            userID: fixture.session.user.id,
            transactionID: fixture.transaction.id,
            request: VerifySharedSubscriptionRequest(signedTransaction: fixture.transaction.signedTransaction)
        )
        await credentials.saveSubscriptionVerification(verification)
        let model = fixture.model(api: api, store: store, credentials: credentials)
        #expect(await model.load(session: fixture.session, isCurrentSession: { _ in true }))
        #expect(await api.receivedRequests == [verification.request])
        #expect(await store.productLoads == 0)
        #expect(await store.finished == ["701"])
        #expect(await credentials.loadSubscriptionVerification() == nil)
    }

    @Test(arguments: ["partial", "differentGroups", "bothMonthly"])
    func `Only complete monthly and annual products in one Apple group can be offered`(_ fault: String) async throws {
        let fixture = PremiumFixture()
        let api = PremiumAPI(status: fixture.status())
        let store = PremiumStore(transaction: fixture.transaction)
        var products = [SharedSubscriptionProduct(
            id: "premium.monthly",
            displayName: "Premium",
            displayPrice: "2,99 €",
            period: .monthly,
            subscriptionGroupID: "910"
        )]
        if fault != "partial" {
            products.append(SharedSubscriptionProduct(
                id: "premium.annual",
                displayName: "Premium anual",
                displayPrice: "29,99 €",
                period: fault == "bothMonthly" ? .monthly : .annual,
                subscriptionGroupID: fault == "differentGroups" ? "911" : "910"
            ))
        }
        await store.setCatalogue(products)
        let model = fixture.model(api: api, store: store)
        _ = await model.load(session: fixture.session, isCurrentSession: { _ in true })
        _ = await model.purchase(
            productID: fixture.transaction.productID,
            session: fixture.session,
            isCurrentSession: { _ in true }
        )
        #expect(model.products.isEmpty)
        #expect(!model.canPurchase)
        #expect(await store.purchases == 0)
        #expect(await api.receivedRequests.isEmpty)
        #expect(await store.finished.isEmpty)
        #expect(model.status?.state == .free)
    }

    @Test
    func `HTTP verification delivers a stored Apple transaction only after the server confirms its current grace state`(
    ) async throws {
        let fixture = PremiumFixture()
        let transport = PremiumHTTPTransport()
        let configuration = try SharedAPIConfiguration(baseURL: "https://api.test", invitationOrigin: "https://links.test")
        let api = SharedHTTPAPI(configuration: configuration, transport: transport)
        let store = PremiumStore(transaction: fixture.transaction)
        let credentials = MemorySharedCredentialStore()
        let model = SharedPremiumViewModel(api: api, store: store, credentials: credentials)
        _ = await model.load(session: fixture.session, isCurrentSession: { _ in true })
        let acknowledged = await model.purchase(
            productID: fixture.transaction.productID,
            session: fixture.session,
            isCurrentSession: { _ in true }
        )

        #expect(acknowledged)
        #expect(model.status?.state == .inGracePeriod)
        #expect(model.status?.gracePeriodExpiresAt == Date(timeIntervalSince1970: 1_790_236_800))
        #expect(await store.finished == ["701"])
        #expect(await credentials.loadSubscriptionVerification() == nil)
        #expect(await transport.submittedTransaction == "verified.device.transaction")
        #expect(await store.purchaseTokens == [fixture.accountToken])
    }

    @Test
    func `Unconfigured subscriptions cannot contact StoreKit or offer a purchase`() async throws {
        let fixture = PremiumFixture()
        let api = PremiumAPI(status: fixture.status(configured: false))
        let store = PremiumStore(transaction: fixture.transaction)
        let model = fixture.model(api: api, store: store)
        _ = await model.load(session: fixture.session, isCurrentSession: { _ in true })
        _ = await model.purchase(productID: "premium.monthly", session: fixture.session, isCurrentSession: { _ in true })

        #expect(await store.productLoads == 0)
        #expect(await store.purchases == 0)
        #expect(!model.canPurchase)
        #expect(model.products.isEmpty)
        #expect(await api.receivedRequests.isEmpty)
    }

    @Test(arguments: [false, true])
    func `Device verification never finishes or grants rights without the exact server acknowledgement`(
        wrongAcknowledgement: Bool
    ) async throws {
        let fixture = PremiumFixture()
        let api = PremiumAPI(status: fixture.status())
        await api.setVerificationFailure(wrongAcknowledgement ? nil : .transport)
        await api.setAcknowledgementID(wrongAcknowledgement ? "another-transaction" : fixture.transaction.id)
        let store = PremiumStore(transaction: fixture.transaction)
        let credentials = MemorySharedCredentialStore()
        let shoppingOperation = PendingSharedOperation.createGroup(
            userID: fixture.session.user.id,
            request: CreateGroupRequest(operationId: UUID(), name: "Casa")
        )
        await credentials.saveOperation(shoppingOperation)
        let model = fixture.model(api: api, store: store, credentials: credentials)
        _ = await model.load(session: fixture.session, isCurrentSession: { _ in true })
        let acknowledged = await model.purchase(
            productID: fixture.transaction.productID,
            session: fixture.session,
            isCurrentSession: { _ in true }
        )

        #expect(!acknowledged)
        #expect(model.status?.state == .free)
        #expect(await store.finished.isEmpty)
        let pending = try #require(await credentials.loadSubscriptionVerification())
        #expect(pending.userID == fixture.session.user.id)
        #expect(pending.transactionID == "701")
        #expect(pending.request.signedTransaction == "verified.device.transaction")
        #expect(await credentials.loadOperation() == shoppingOperation)

        await api.setVerificationFailure(nil)
        await api.setAcknowledgementID(fixture.transaction.id)
        let reopened = fixture.model(api: api, store: store, credentials: credentials)
        let recovered = await reopened.load(session: fixture.session, isCurrentSession: { _ in true })
        #expect(recovered)
        #expect(await store.finished == ["701"])
        #expect(await api.receivedRequests.map(\.signedTransaction) == [
            "verified.device.transaction", "verified.device.transaction"
        ])
        #expect(await credentials.loadSubscriptionVerification() == nil)
        #expect(await credentials.loadOperation() == shoppingOperation)
    }

    @Test
    func `Acknowledging a historical transaction finishes delivery while current rights remain expired`() async throws {
        let fixture = PremiumFixture()
        let api = PremiumAPI(status: fixture.status())
        await api.setAcknowledgedStatus(fixture.status(state: .expired))
        let store = PremiumStore(transaction: fixture.transaction)
        let model = fixture.model(api: api, store: store)
        _ = await model.load(session: fixture.session, isCurrentSession: { _ in true })
        let result = await model.purchase(
            productID: fixture.transaction.productID,
            session: fixture.session,
            isCurrentSession: { _ in true }
        )

        #expect(result)
        #expect(model.status?.state == .expired)
        #expect(await store.finished == ["701"])
        #expect(model.pendingVerification == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func `An account change during verification cannot finish a transaction or discard its original recovery envelope`(
    ) async throws {
        let fixture = PremiumFixture()
        let api = PremiumAPI(status: fixture.status())
        let gate = PremiumGate()
        await api.setGate(gate)
        let store = PremiumStore(transaction: fixture.transaction)
        let credentials = MemorySharedCredentialStore()
        let model = fixture.model(api: api, store: store, credentials: credentials)
        _ = await model.load(session: fixture.session, isCurrentSession: { _ in true })
        var currentAccount = fixture.session.user.id
        let purchase = Task {
            return await model.purchase(
                productID: fixture.transaction.productID,
                session: fixture.session,
                isCurrentSession: { $0.user.id == currentAccount }
            )
        }
        await gate.waitUntilReached()
        currentAccount = UUID()
        model.clearPresentation()
        await gate.open()
        #expect(await purchase.value == false)
        #expect(await store.finished.isEmpty)
        #expect(model.status == nil)
        #expect(await credentials.loadSubscriptionVerification()?.userID == fixture.session.user.id)
    }

    @Test
    func `A different app account cannot submit or finish an Apple transaction bound to its original account`() async throws {
        let fixture = PremiumFixture()
        let api = PremiumAPI(status: fixture.status())
        let transaction = SharedStoreTransaction(
            id: "701",
            appAccountToken: UUID(),
            productID: fixture.transaction.productID,
            signedTransaction: fixture.transaction.signedTransaction
        )
        let store = PremiumStore(transaction: transaction)
        let model = fixture.model(api: api, store: store)
        _ = await model.load(session: fixture.session, isCurrentSession: { _ in true })
        _ = await model.purchase(
            productID: transaction.productID,
            session: fixture.session,
            isCurrentSession: { _ in true }
        )
        #expect(await api.receivedRequests.isEmpty)
        #expect(await store.finished.isEmpty)
        #expect(model.pendingVerification == nil)
        #expect(model.status?.state == .free)
    }

    @Test(arguments: [false, true])
    func `Cancelled or pending Apple purchases never reach server verification`(pending: Bool) async throws {
        let fixture = PremiumFixture()
        let api = PremiumAPI(status: fixture.status())
        let store = PremiumStore(transaction: fixture.transaction)
        await store.setPurchaseResult(pending ? .pending : .cancelled)
        let model = fixture.model(api: api, store: store)
        _ = await model.load(session: fixture.session, isCurrentSession: { _ in true })
        _ = await model.purchase(
            productID: fixture.transaction.productID,
            session: fixture.session,
            isCurrentSession: { _ in true }
        )
        #expect(await api.receivedRequests.isEmpty)
        #expect(await store.finished.isEmpty)
        #expect(model.pendingVerification == nil)
        #expect(model.status?.state == .free)
    }

    @Test
    func `Explicit restoration syncs Apple once and acknowledges the recovered transaction before finishing`() async throws {
        let fixture = PremiumFixture()
        let api = PremiumAPI(status: fixture.status())
        await api.setAcknowledgedStatus(fixture.status(state: .subscribed))
        let store = PremiumStore(transaction: fixture.transaction)
        let model = fixture.model(api: api, store: store)
        _ = await model.load(session: fixture.session, isCurrentSession: { _ in true })
        #expect(await store.restorations == 0)
        await store.setRestoredTransactions([fixture.transaction])
        #expect(await model.restore(session: fixture.session, isCurrentSession: { _ in true }))
        #expect(await store.restorations == 1)
        #expect(await store.purchases == 0)
        #expect(await store.finished == ["701"])
        #expect(model.status?.state == .subscribed)
    }

    @Test
    func `Confirmed rejection clears local verification without finishing a transaction Apple has not delivered`() async throws {
        let fixture = PremiumFixture()
        let api = PremiumAPI(status: fixture.status())
        await api.setVerificationFailure(.server(
            status: 403,
            code: "transaction_account_mismatch",
            requestID: UUID(),
            retryAfter: nil
        ))
        let store = PremiumStore(transaction: fixture.transaction)
        let credentials = MemorySharedCredentialStore()
        let model = fixture.model(api: api, store: store, credentials: credentials)
        _ = await model.load(session: fixture.session, isCurrentSession: { _ in true })
        _ = await model.purchase(
            productID: fixture.transaction.productID,
            session: fixture.session,
            isCurrentSession: { _ in true }
        )
        #expect(await store.finished.isEmpty)
        #expect(await credentials.loadSubscriptionVerification() == nil)
        #expect(model.pendingVerification == nil)
        #expect(model.notice != nil)
        #expect(model.status?.state == .free)
    }
}

private struct PremiumFixture {
    let accountToken = UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, 1))
    let session = SharedSession(
        accessToken: String(repeating: "A", count: 43),
        tokenType: "Bearer",
        expiresAt: .distantFuture,
        user: SharedUser(id: UUID(), displayName: "Alex", group: nil)
    )

    var transaction: SharedStoreTransaction {
        SharedStoreTransaction(
            id: "701",
            appAccountToken: accountToken,
            productID: "premium.monthly",
            signedTransaction: "verified.device.transaction"
        )
    }

    func status(configured: Bool = true, state: SharedSubscriptionState = .free) -> SharedSubscriptionStatus {
        SharedSubscriptionStatus(
            appAccountToken: accountToken,
            isConfigured: configured,
            productIDs: configured ? ["premium.monthly", "premium.annual"] : [],
            state: state,
            expiresAt: state == .free ? nil : Date(timeIntervalSince1970: 1_900_000_000),
            gracePeriodExpiresAt: nil,
            autoRenewEnabled: state == .subscribed ? true : nil,
            verifiedAt: state == .free ? nil : Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    @MainActor
    func model(
        api: PremiumAPI,
        store: PremiumStore,
        credentials: MemorySharedCredentialStore = MemorySharedCredentialStore()
    ) -> SharedPremiumViewModel {
        SharedPremiumViewModel(api: api, store: store, credentials: credentials)
    }
}

private actor PremiumAPI: SharedSubscriptionAPI {
    private let currentStatus: SharedSubscriptionStatus
    private var acknowledgedStatus: SharedSubscriptionStatus
    private var failure: SharedAPIError?
    private var acknowledgementID = "701"
    private var gate: PremiumGate?
    private(set) var receivedRequests: [VerifySharedSubscriptionRequest] = []

    init(status: SharedSubscriptionStatus) {
        currentStatus = status
        acknowledgedStatus = status
    }

    func setAcknowledgedStatus(_ status: SharedSubscriptionStatus) {
        acknowledgedStatus = status
    }
    func setVerificationFailure(_ error: SharedAPIError?) {
        failure = error
    }
    func setAcknowledgementID(_ id: String) {
        acknowledgementID = id
    }
    func setGate(_ gate: PremiumGate) {
        self.gate = gate
    }

    func subscription(token: String) async throws -> SharedSubscriptionStatus { currentStatus }

    func verifySubscription(
        _ request: VerifySharedSubscriptionRequest,
        token: String
    ) async throws -> SharedSubscriptionAcknowledgement {
        receivedRequests.append(request)
        await gate?.pause()
        if let failure {
            throw failure
        }
        return SharedSubscriptionAcknowledgement(
            subscription: acknowledgedStatus,
            acknowledgedTransactionId: acknowledgementID
        )
    }
}

private actor PremiumStore: SharedSubscriptionStore {
    private let transaction: SharedStoreTransaction
    private var result: SharedSubscriptionPurchaseResult
    private var restoredTransactions: [SharedStoreTransaction] = []
    private var catalogueFailure = false
    private var catalogue: [SharedSubscriptionProduct] = [
        SharedSubscriptionProduct(
            id: "premium.monthly",
            displayName: "Premium",
            displayPrice: "2,99 €",
            period: .monthly,
            subscriptionGroupID: "910"
        ),
        SharedSubscriptionProduct(
            id: "premium.annual",
            displayName: "Premium anual",
            displayPrice: "29,99 €",
            period: .annual,
            subscriptionGroupID: "910"
        )
    ]
    private(set) var productLoads = 0
    private(set) var purchases = 0
    private(set) var purchaseTokens: [UUID] = []
    private(set) var restorations = 0
    private(set) var finished: [String] = []

    init(transaction: SharedStoreTransaction) {
        self.transaction = transaction
        result = .verified(transaction)
    }

    func setPurchaseResult(_ result: SharedSubscriptionPurchaseResult) {
        self.result = result
    }
    func setRestoredTransactions(_ transactions: [SharedStoreTransaction]) {
        restoredTransactions = transactions
    }

    func setCatalogue(_ products: [SharedSubscriptionProduct]) {
        catalogue = products
    }

    func failCatalogue() {
        catalogueFailure = true
    }

    func products(ids: [String]) async throws -> [SharedSubscriptionProduct] {
        productLoads += 1
        if catalogueFailure {
            throw SharedSubscriptionStoreError.unavailable
        }
        return catalogue
    }

    func purchase(id: String, appAccountToken: UUID) async throws -> SharedSubscriptionPurchaseResult {
        purchases += 1
        purchaseTokens.append(appAccountToken)
        return result
    }

    func restore() async throws {
        restorations += 1
    }
    func transactions() async throws -> [SharedStoreTransaction] { restoredTransactions }
    func updates() async -> AsyncStream<SharedStoreTransaction> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
    func finish(transactionID: String) async {
        finished.append(transactionID)
    }
}

private actor PremiumGate {
    private var isReached = false
    private var isOpen = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?

    func pause() async {
        isReached = true
        arrival?.resume()
        arrival = nil
        if !isOpen {
            await withCheckedContinuation { release = $0 }
        }
    }

    func waitUntilReached() async {
        if !isReached {
            await withCheckedContinuation { arrival = $0 }
        }
    }

    func open() {
        isOpen = true
        release?.resume()
        release = nil
    }
}

private actor PremiumHTTPTransport: SharedHTTPTransport {
    private(set) var submittedTransaction: String?

    func response(to request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = try #require(request.url)
        let body: String
        switch (request.httpMethod, url.path) {
        case ("GET", "/v1/account/subscription"):
            body = Self.status(state: "free")
        case ("POST", "/v1/account/subscription/transactions"):
            let payload = try #require(request.httpBody)
            let submitted = try JSONDecoder().decode(VerifySharedSubscriptionRequest.self, from: payload)
            submittedTransaction = submitted.signedTransaction
            body = "{\"subscription\":\(Self.status(state: "in_grace_period")),\"acknowledgedTransactionId\":\"701\"}"
        default:
            throw SharedAPIError.invalidResponse
        }
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
        return (Data(body.utf8), response)
    }

    private static func status(state: String) -> String {
        """
        {"appAccountToken":"00000000-0000-4000-8000-000000000001","isConfigured":true,
        "productIDs":["premium.monthly","premium.annual"],"state":"\(state)",
        "expiresAt":"2026-09-19T10:10:00Z","gracePeriodExpiresAt":"2026-09-24T08:00:00Z",
        "autoRenewEnabled":true,"verifiedAt":"2026-09-20T09:00:00Z"}
        """
    }
}
