import Foundation
import Combine
import UserNotifications

/// Local notifications for auto-detected trips: ask the user to confirm/edit
/// the classification with three quick-action buttons.
@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationManager()

    /// Set by the app on launch so action taps can route to the store.
    weak var store: Store?
    weak var detectionLog: DetectionLog?
    /// Set by the app on launch so a classify tap that no longer finds its
    /// trip in store.trips can tell "merged back into an in-progress trip"
    /// apart from "gone for some other reason."
    weak var detector: TripDetector?

    private let center = UNUserNotificationCenter.current()
    private let classifyCategoryID = "TRIP_CLASSIFY"

    /// Where a tapped notification should take the user; RootTabView consumes it.
    enum Route: Equatable {
        case paywall
        case monthEndCheck(Date)
        case trip(UUID)
    }
    @Published var pendingRoute: Route?

    override init() {
        super.init()
        center.delegate = self
        registerCategories()
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - Categories with quick-classify actions

    private func registerCategories() {
        let business = UNNotificationAction(identifier: "CLASSIFY_BUSINESS",
                                            title: String(localized: "Business", bundle: .app), options: [])
        let commute  = UNNotificationAction(identifier: "CLASSIFY_COMMUTE",
                                            title: String(localized: "Commute", bundle: .app),  options: [])
        let priv     = UNNotificationAction(identifier: "CLASSIFY_PRIVATE",
                                            title: String(localized: "Private", bundle: .app),  options: [])

        let category = UNNotificationCategory(
            identifier: classifyCategoryID,
            actions: [business, commute, priv],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    // MARK: - Sending

    func sendClassifyNotification(for trip: Trip) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Trip ended", bundle: .app)
        let distanceText = Format.km(trip.distanceKm)
        content.subtitle = "\(distanceText) · \(trip.type.label)"
        if trip.customerName.isEmpty {
            content.body = String(localized: "Tap to classify, or pick one below.", bundle: .app)
        } else {
            content.body = String(localized: "Customer: \(trip.customerName). Tap to confirm or change.", bundle: .app)
        }
        content.categoryIdentifier = classifyCategoryID
        content.userInfo = ["tripID": trip.id.uuidString]
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "trip-\(trip.id.uuidString)",
            content: content,
            trigger: nil   // deliver immediately
        )
        try? await center.add(request)
    }

    /// Sent the moment location authorization drops from Always to anything
    /// else while auto-detect is enabled. Background trip detection depends
    /// entirely on Always permission — CLLocationManager just silently stops
    /// waking the app on a downgrade, with no error the user would ever see
    /// unless they happen to open Settings or the Record tab. A real field
    /// case went undetected for a full week because of exactly this silence.
    func sendPermissionDowngradedNotification() async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Auto-detect has stopped", bundle: .app)
        content.body = String(localized: "Location permission dropped to 'While Using' — trips won't be tracked in the background anymore. Tap to fix it in Settings.", bundle: .app)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "permission-downgraded",
            content: content,
            trigger: nil   // deliver immediately
        )
        try? await center.add(request)
    }

    /// A fully GPS/motion-verified drive was detected but had to be thrown
    /// away because the account has no vehicle to attribute it to. That
    /// previously left its only trace in the Detection Log — a screen
    /// buried under Settings that a first-time user has no reason to ever
    /// open — so the user simply lost a real trip with no signal at all
    /// (round-4 UX review finding).
    func sendNoVehicleTripDroppedNotification() async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Trip not saved", bundle: .app)
        content.body = String(localized: "A drive was detected, but there's no vehicle to log it against. Add your car in MileLog so the next one is saved.", bundle: .app)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "no-vehicle-trip-dropped",
            content: content,
            trigger: nil   // deliver immediately
        )
        try? await center.add(request)
    }

    // MARK: - Month-end reminder

    private let monthEndReminderID = "month-end-reminder"

    /// 18:00 on the last day of the month, for Paid users with something to fix
    /// (KTD15). Re-run at launch, on foreground and when the plan changes.
    func scheduleMonthEndReminder(isPaid: Bool, openItems: Int, now: Date = Date()) async {
        center.removePendingNotificationRequests(withIdentifiers: [monthEndReminderID])
        guard isPaid, openItems > 0,
              let fireDate = Self.monthEndReminderDate(after: now), fireDate > now else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Month ends today", bundle: .app)
        content.body = String(localized: "\(openItems) trips still need checking before you close the month.", bundle: .app)
        content.sound = .default
        content.userInfo = ["route": "monthEndCheck"]
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let request = UNNotificationRequest(identifier: monthEndReminderID, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        try? await center.add(request)
    }

    /// 18:00 on the last day of `now`'s month.
    nonisolated static func monthEndReminderDate(after now: Date, calendar: Calendar = .current) -> Date? {
        guard let month = calendar.dateInterval(of: .month, for: now),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end) else { return nil }
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: lastDay)
    }

    /// Free plan allowance: heads-up before the limit and the pause at it.
    func sendAllowanceNotice(_ notice: Allowance.Notice, state: AllowanceState) async {
        let content = UNMutableNotificationContent()
        switch notice {
        case .threeLeft, .oneLeft:
            content.title = String(localized: "Automatic trips running low", bundle: .app)
            content.body = String(localized: "\(state.remaining) of \(state.limit) automatic trips left this month on the Free plan.", bundle: .app)
        case .paused:
            content.title = String(localized: "Automatic recording paused", bundle: .app)
            content.body = String(localized: "You've used all \(state.limit) automatic trips this month. Record trips manually, or subscribe to keep recording automatically.", bundle: .app)
        }
        content.sound = .default
        content.userInfo = ["route": "paywall"]
        let request = UNNotificationRequest(identifier: "allowance-\(notice.rawValue)", content: content, trigger: nil)
        try? await center.add(request)
    }

    // MARK: - Handling action taps

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionID = response.actionIdentifier
        // Pull the only piece of userInfo we care about into a Sendable String
        // before the @Sendable Task closure, so we don't capture the non-Sendable
        // [AnyHashable: Any] dictionary.
        let tripIDString = response.notification.request.content.userInfo["tripID"] as? String
        let routeString = response.notification.request.content.userInfo["route"] as? String
        let isPlainTap = actionID == UNNotificationDefaultActionIdentifier

        Task { @MainActor in
            if isPlainTap {
                // A tap on the notification itself opens the matching screen (KTD15).
                switch routeString {
                case "paywall": self.pendingRoute = .paywall
                case "monthEndCheck": self.pendingRoute = .monthEndCheck(Date())
                default:
                    if let id = tripIDString.flatMap(UUID.init(uuidString:)) { self.pendingRoute = .trip(id) }
                }
            } else {
                self.handleAction(actionID: actionID, tripIDString: tripIDString)
            }
            completionHandler()
        }
    }

    /// Show the notification banner even when the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    @MainActor
    private func handleAction(actionID: String, tripIDString: String?) {
        guard let idString = tripIDString, let tripID = UUID(uuidString: idString), let store else { return }

        guard var trip = store.trips.first(where: { $0.id == tripID }) else {
            // The trip this notification was for isn't in store.trips
            // anymore — most likely it got merged/reclaimed back into an
            // in-progress trip (a brief stop, or a relaunch-interrupted
            // drive resuming) before the user tapped the action. There's
            // nowhere to apply the classification: an in-progress
            // ActiveTripState doesn't carry a type yet, it'll get a fresh
            // one from TripClassifier whenever it next actually ends.
            // Logging this explicitly closes what was previously a totally
            // silent, undiagnosable no-op (round-2 adversarial review
            // finding) — the tap is still lost, but now traceable.
            if let active = detector?.activeTrip, active.id == tripID {
                // Uses the trip's own start time rather than the opaque
                // truncated id — even if someone opens this debug screen
                // (told to by support, or just curious), a raw UUID gives
                // no way to tell which actual drive it's about (round-2 UX
                // review finding).
                let when = active.startedAt.formatted(date: .abbreviated, time: .shortened)
                detectionLog?.log("Classify tap for the \(when) trip ignored — it's back in progress (merged with continued driving) and will be reclassified when it next ends.",
                                   level: .warning)
            } else {
                detectionLog?.log("Classify tap for \(idString.prefix(8)) ignored — trip no longer found.", level: .warning)
            }
            return
        }

        let newType: TripType?
        switch actionID {
        case "CLASSIFY_BUSINESS": newType = .business
        case "CLASSIFY_COMMUTE":  newType = .commute
        case "CLASSIFY_PRIVATE":  newType = .privateTrip
        default:                  newType = nil
        }

        if let newType {
            // Checked BEFORE mutating `trip` below: Store.updateTrip's merge
            // only lets `type` through `if !previous.isLocked` — if this
            // trip crossed its lockAfterDays threshold while the
            // notification sat unactioned in Notification Center (they
            // persist indefinitely until dismissed), the classification
            // silently never applies. Logging success unconditionally
            // regardless left that completely untraceable — even the
            // Detection Log itself would have claimed it worked (round-13
            // adversarial review finding).
            let wasLocked = trip.isLocked
            trip.type = newType
            // Marks this trip as human-reviewed so TripDetector's merge/
            // reclaim logic refuses to ever resurrect it as in-progress
            // again — see Trip.reviewedAt's doc comment for why silently
            // doing so would be actively harmful, not just a missed
            // opportunity.
            trip.reviewedAt = Date()
            store.updateTrip(trip)
            // References the trip's own start time rather than the opaque
            // truncated id, matching the fix above (round-2 UX review
            // finding).
            let when = trip.startedAt.formatted(date: .abbreviated, time: .shortened)
            if wasLocked {
                detectionLog?.log("Classify tap for the \(when) trip ignored — it was locked before the tap was handled; classification not changed.",
                                   level: .warning)
            } else {
                detectionLog?.log("Classified the \(when) trip as \(newType.label) via notification")
            }
        }
        // Default action (UNNotificationDefaultActionIdentifier) → app opens to trips list naturally.
    }
}
