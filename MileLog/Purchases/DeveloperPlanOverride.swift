import Foundation

/// Debug and TestFlight builds only: pretend to be on another plan to test the
/// Free allowance, the paywall and the lapse flow without touching the server.
/// App Store builds ignore it, whatever is stored.
enum DeveloperPlanOverride: String, CaseIterable, Identifiable {
    case none, free, paid, lapsed, otherAccount

    var id: String { rawValue }

    /// The plan the app acts on: the real one, or the pretended one.
    nonisolated func apply(to real: PlanStatus) -> PlanStatus {
        switch self {
        case .none: real
        case .free, .lapsed: .free
        case .paid: .paid(until: nil)
        case .otherAccount: .freeOtherAccount
        }
    }

    var label: String {
        switch self {
        case .none: String(localized: "Real plan", bundle: .app)
        case .free: String(localized: "Free", bundle: .app)
        case .paid: String(localized: "Paid", bundle: .app)
        case .lapsed: String(localized: "Lapsed (Paid ended)", bundle: .app)
        case .otherAccount: String(localized: "Free — subscription on another account", bundle: .app)
        }
    }
}

enum BuildChannel {
    /// Debug builds and TestFlight. App Store builds have a production receipt.
    nonisolated static var isTestBuild: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
