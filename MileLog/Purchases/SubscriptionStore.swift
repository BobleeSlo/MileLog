import Foundation
import Combine
import StoreKit

/// Sells the Paid subscription and keeps `plan` current for the signed-in account.
///
/// Every purchase carries the Supabase user id as `appAccountToken`. Each signed
/// transaction is sent to the `verify-purchase` Edge Function before it is
/// finished; the server's entitlement rows are the authority (KTD5), with this
/// device's verified transactions and the cached plan as fallbacks.
@MainActor
final class SubscriptionStore: ObservableObject {

    /// Must match App Store Connect, MileLog.storekit and the Edge Functions' APPLE_PRODUCT_IDS.
    nonisolated static let productIDs = ["BT1.MileLog.paid.monthly", "BT1.MileLog.paid.yearly"]

    @Published private(set) var plan: PlanStatus = .free
    @Published private(set) var products: [Product] = []
    @Published private(set) var lastError: String?

    private weak var supabase: SupabaseService?
    /// The signed-in account; purchases carry it as `appAccountToken`.
    private(set) var userID: UUID?
    private var updatesTask: Task<Void, Never>?
    private let cache: PlanCache

    init(defaults: UserDefaults = .standard) {
        cache = PlanCache(defaults: defaults)
        // A background relaunch for a drive can reach the trip detector before
        // any view has resolved the account: start from the last account's
        // cached plan so a Paid user is never refused (KTD5's offline rule).
        if let last = cache.lastUserID {
            plan = PlanResolver.resolve(server: nil, local: [], cache: cache.load(for: last), userID: last, now: Date())
        }
    }

    /// Starts listening for transactions; call once at launch.
    func start(supabase: SupabaseService) {
        self.supabase = supabase
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { products = (try? await Product.products(for: Self.productIDs)) ?? [] }
    }

    /// Called whenever the signed-in account changes (nil on sign-out).
    func accountChanged(to newUserID: UUID?) async {
        // The previous launch's account counts only when another account signs in;
        // a sign-out clears the account signed in during this run.
        if let old = userID ?? (newUserID != nil ? cache.lastUserID : nil), old != newUserID { cache.clear(for: old) }
        userID = newUserID
        cache.lastUserID = newUserID
        guard newUserID != nil else {
            setPlan(.free)
            return
        }
        // KTD6: a subscription bought under a deleted account, or renewed from iOS
        // Settings without a token, can still bind; the server decides.
        for (tx, jws) in await ourEntitlements() where tx.appAccountToken != newUserID {
            await sendToServer(jws)
        }
        await refresh()
    }

    /// Recomputes the plan from the server, this device and the cache.
    func refresh() async {
        guard let userID else {
            setPlan(.free)
            return
        }
        let server = try? await supabase?.pullEntitlements()
        let local = await ourEntitlements().map(\.tx).filter(isAcceptedEnvironment).map {
            LocalEntitlement(originalTransactionID: String($0.originalID), appAccountToken: $0.appAccountToken,
                             expiresAt: $0.expirationDate, isRevoked: $0.revocationDate != nil)
        }
        // The account may have changed during the awaits above.
        guard self.userID == userID else { return }
        let now = Date()
        setPlan(PlanResolver.resolve(server: server, local: local, cache: cache.load(for: userID), userID: userID, now: now))
        if server != nil {
            var until: Date?
            if case .paid(let date) = plan { until = date }
            cache.save(CachedPlan(userID: userID, isPaid: plan.isPaid, expiresAt: until, checkedAt: now))
        }
    }

    func purchase(_ product: Product) async {
        guard let userID else { return }
        lastError = nil
        do {
            let result = try await product.purchase(options: [.appAccountToken(userID)])
            if case .success(let verification) = result {
                await handle(verification)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Completion of a purchase made through `SubscriptionStoreView`.
    func purchaseCompleted(_ result: Result<Product.PurchaseResult, any Error>) async {
        switch result {
        case .success(.success(let verification)):
            await handle(verification)
        case .success:
            break // cancelled or pending (Ask to Buy)
        case .failure(let error):
            lastError = error.localizedDescription
        }
    }

    func restore() async {
        lastError = nil
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        for (_, jws) in await ourEntitlements() {
            await sendToServer(jws)
        }
        await refresh()
    }

    // MARK: - Private

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let tx) = result else { return }
        if isOurs(tx) { await sendToServer(result.jwsRepresentation) }
        await tx.finish()
        await refresh()
    }

    private func sendToServer(_ jws: String) async {
        do {
            try await supabase?.verifyPurchase(signedTransaction: jws)
        } catch {
            // Ignored: the device transaction still counts until the server catches up,
            // and apple-notifications updates the row independently.
        }
    }

    /// Assigns only on change, so observers don't re-render for an unchanged plan.
    private func setPlan(_ new: PlanStatus) {
        if plan != new { plan = new }
    }

    /// Verified current entitlements for MileLog's subscriptions, with their signed form.
    private func ourEntitlements() async -> [(tx: Transaction, jws: String)] {
        var out: [(tx: Transaction, jws: String)] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, isOurs(tx) { out.append((tx, result.jwsRepresentation)) }
        }
        return out
    }

    private func isOurs(_ tx: Transaction) -> Bool {
        Self.productIDs.contains(tx.productID)
    }

    /// App Store builds only trust production transactions; TestFlight and debug
    /// builds also accept sandbox and Xcode ones (KTD5).
    private func isAcceptedEnvironment(_ tx: Transaction) -> Bool {
        #if DEBUG
        return true
        #else
        if tx.environment == .production { return true }
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}

/// Per-account plan cache in UserDefaults.
struct PlanCache {
    let defaults: UserDefaults

    /// The account whose plan was last resolved on this device.
    var lastUserID: UUID? {
        get { defaults.string(forKey: "MileLog.planCache.lastUser").flatMap(UUID.init(uuidString:)) }
        nonmutating set { defaults.set(newValue?.uuidString, forKey: "MileLog.planCache.lastUser") }
    }

    private func key(_ userID: UUID) -> String { "MileLog.planCache.\(userID.uuidString.lowercased())" }

    func load(for userID: UUID) -> CachedPlan? {
        defaults.data(forKey: key(userID)).flatMap { try? JSONDecoder().decode(CachedPlan.self, from: $0) }
    }

    func save(_ plan: CachedPlan) {
        defaults.set(try? JSONEncoder().encode(plan), forKey: key(plan.userID))
    }

    func clear(for userID: UUID) {
        defaults.removeObject(forKey: key(userID))
    }
}
