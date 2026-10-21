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
    private var userID: UUID?
    private var updatesTask: Task<Void, Never>?
    private let cache: PlanCache

    init(defaults: UserDefaults = .standard) {
        cache = PlanCache(defaults: defaults)
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
        if let old = userID, old != newUserID { cache.clear(for: old) }
        userID = newUserID
        guard newUserID != nil else {
            plan = .free
            return
        }
        // KTD6: a subscription bought under a deleted account, or renewed from iOS
        // Settings without a token, can still bind; the server decides.
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.appAccountToken != newUserID, isOurs(tx) {
                await sendToServer(result.jwsRepresentation)
            }
        }
        await refresh()
    }

    /// Recomputes the plan from the server, this device and the cache.
    func refresh() async {
        guard let userID else {
            plan = .free
            return
        }
        let server = try? await supabase?.pullEntitlements()
        var local: [LocalEntitlement] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result, isOurs(tx), isAcceptedEnvironment(tx) else { continue }
            local.append(LocalEntitlement(originalTransactionID: String(tx.originalID), appAccountToken: tx.appAccountToken,
                                          expiresAt: tx.expirationDate, isRevoked: tx.revocationDate != nil))
        }
        let now = Date()
        plan = PlanResolver.resolve(server: server, local: local, cache: cache.load(for: userID), userID: userID, now: now)
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

    func restore() async {
        lastError = nil
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        for await result in Transaction.currentEntitlements where isOursVerified(result) {
            await sendToServer(result.jwsRepresentation)
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
            // Not fatal: the device transaction still counts until the server catches up,
            // and apple-notifications updates the row independently.
            lastError = nil
        }
    }

    private func isOurs(_ tx: Transaction) -> Bool {
        Self.productIDs.contains(tx.productID)
    }

    private func isOursVerified(_ result: VerificationResult<Transaction>) -> Bool {
        if case .verified(let tx) = result { return isOurs(tx) }
        return false
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
