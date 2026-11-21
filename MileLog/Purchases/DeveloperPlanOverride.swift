import Foundation
import StoreKit
import Synchronization

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
    /// Debug builds and TestFlight. Release builds read the App Store environment
    /// with `resolve()` and count as App Store builds until it answers (fail closed).
    nonisolated static var isTestBuild: Bool {
        #if DEBUG
        return true
        #else
        return isSandbox.withLock { $0 }
        #endif
    }

    nonisolated private static let isSandbox = Mutex(false)
    private static var resolveTask: Task<Void, Never>?

    /// Reads the signed app transaction once; later calls wait for the same answer.
    static func resolve() async {
        #if !DEBUG
        if resolveTask == nil {
            resolveTask = Task {
                if case .verified(let app)? = try? await AppTransaction.shared {
                    isSandbox.withLock { $0 = app.environment != .production }
                }
            }
        }
        await resolveTask?.value
        #endif
    }
}
