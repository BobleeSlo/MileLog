import Foundation

/// Features the Free plan gates behind the paywall (R3, R8).
enum PaidFeature {
    case reports, receipts, monthEndCheck, extraVehicle
}

extension PlanStatus {
    /// - Parameter activeVehicleCount: for `.extraVehicle`, the active vehicles the
    ///   account already has; archived ones don't count.
    func allows(_ feature: PaidFeature, activeVehicleCount: Int = 0) -> Bool {
        if isPaid { return true }
        switch feature {
        case .extraVehicle: return activeVehicleCount == 0
        case .reports, .receipts, .monthEndCheck: return false
        }
    }
}
