import Foundation

/// The account's plan, combined from the server's entitlement rows, verified
/// StoreKit transactions on this device and the last known status (KTD5).
enum PlanStatus: Equatable, Codable {
    case free
    /// `until` is the renewal or expiry date when known (nil for an open-ended grant).
    case paid(until: Date?)
    /// Free because the Apple ID on this device pays for a different MileLog account (KTD6).
    case freeOtherAccount

    var isPaid: Bool {
        if case .paid = self { return true }
        return false
    }
}

/// One row of the `entitlements` table as the app reads it.
struct ServerEntitlement: Codable, Equatable {
    var source: String
    var originalTransactionID: String?
    var status: String
    var expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case source, status
        case originalTransactionID = "original_transaction_id"
        case expiresAt = "expires_at"
    }

    /// KTD8: active and grace period count as Paid until their expiry.
    nonisolated func isPaid(at now: Date) -> Bool {
        (status == "active" || status == "grace") && (expiresAt.map { $0 > now } ?? true)
    }
}

/// A verified StoreKit transaction for one of MileLog's subscriptions.
struct LocalEntitlement: Equatable {
    var originalTransactionID: String
    var appAccountToken: UUID?
    var expiresAt: Date?
    var isRevoked: Bool
}

/// Last known plan for one account, honoured offline (KTD5).
struct CachedPlan: Codable, Equatable {
    var userID: UUID
    var isPaid: Bool
    var expiresAt: Date?
    var checkedAt: Date

    /// Trusted until the earlier of its expiry and seven days after the last server check.
    static let maxAge: TimeInterval = 7 * 24 * 3600
}

enum PlanResolver {
    /// - Parameters:
    ///   - server: the account's rows, or nil when they couldn't be fetched (offline).
    ///   - local: verified current entitlements on this device.
    ///   - cache: the last known plan; only used when `server` is nil.
    nonisolated static func resolve(server: [ServerEntitlement]?, local: [LocalEntitlement], cache: CachedPlan?,
                                    userID: UUID, now: Date) -> PlanStatus {
        if let server, let best = server.filter({ $0.isPaid(at: now) }).max(by: { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }) {
            return .paid(until: best.expiresAt)
        }
        // A subscription the server has revoked stays Free whatever the device still holds.
        let revoked = Set((server ?? []).filter { $0.status == "revoked" }.compactMap(\.originalTransactionID))
        let live = local.filter { !$0.isRevoked && !revoked.contains($0.originalTransactionID) && ($0.expiresAt.map { $0 > now } ?? true) }
        if let mine = live.first(where: { $0.appAccountToken == userID }) {
            return .paid(until: mine.expiresAt)
        }
        if server == nil, let cache, cache.userID == userID, cache.isPaid {
            let limit = min(cache.expiresAt ?? .distantFuture, cache.checkedAt.addingTimeInterval(CachedPlan.maxAge))
            if now < limit { return .paid(until: cache.expiresAt) }
        }
        if live.contains(where: { $0.appAccountToken != nil && $0.appAccountToken != userID }) {
            return .freeOtherAccount
        }
        return .free
    }
}
