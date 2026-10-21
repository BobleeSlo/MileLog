import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var detector: TripDetector
    @EnvironmentObject var store: Store
    @EnvironmentObject var subscriptions: SubscriptionStore
    /// Asked once per app open while the choice is pending; Vehicles offers it too.
    @State private var showingRecordingChoice = false
    @State private var askedRecordingChoice = false
    @EnvironmentObject var notifications: NotificationManager
    @EnvironmentObject var usage: Usage
    @Environment(\.scenePhase) private var scenePhase
    @State private var askingUsageConsent = false
    @State private var showingPaywall = false
    @State private var monthEndCheckMonth: Date?
    @State private var routedTrip: Trip?
    /// Scene storage, so the tab survives the rebuild a language change
    /// triggers (the user stays in Settings instead of landing on Record).
    @SceneStorage("selectedTab") private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            RecordTripView()
                .tabItem { Label("Record", systemImage: "circle.dotted") }
                .tag(0)

            TripsListView()
                .tabItem { Label("Trips", systemImage: "list.bullet.rectangle.fill") }
                .tag(1)

            VehiclesView()
                .tabItem { Label("Vehicles", systemImage: "car.2.fill") }
                .tag(2)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(Theme.accent)
        .sheet(isPresented: $showingRecordingChoice) { RecordingVehicleChoiceView() }
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .sheet(item: Binding(get: { monthEndCheckMonth.map(RoutedMonth.init) }, set: { monthEndCheckMonth = $0?.month })) { routed in
            NavigationStack {
                MonthEndCheckView(month: routed.month)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { monthEndCheckMonth = nil } }
                    }
            }
        }
        .sheet(item: $routedTrip) { trip in
            NavigationStack {
                TripDetailView(trip: trip)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { routedTrip = nil } }
                    }
            }
        }
        // The one-time usage question (KTD13); the answer can change in Settings.
        .task {
            if usage.consent == nil, !store.trips.isEmpty { askingUsageConsent = true }
        }
        .alert("Share anonymous usage?", isPresented: $askingUsageConsent) {
            Button("Share") { usage.consent = true }
            Button("Don't share", role: .cancel) { usage.consent = false }
        } message: {
            Text("Once a month MileLog would send rough counts — such as 11–15 automatic trips — with no trips, places or device details. You can change this in Settings.")
        }
        // Notification taps (KTD15).
        .onChange(of: notifications.pendingRoute) { _, route in
            guard let route else { return }
            notifications.pendingRoute = nil
            switch route {
            case .paywall:
                if !subscriptions.plan.isPaid { showingPaywall = true }
            case .monthEndCheck(let month):
                if subscriptions.plan.allows(.monthEndCheck) { monthEndCheckMonth = month } else { showingPaywall = true }
            case .trip(let id):
                routedTrip = store.trips.first { $0.id == id }
            }
        }
        // Month-end reminder follows the plan and the current month's open items.
        // Keyed on cheap values: the check itself runs only in the task, and only for Paid users.
        .task(id: ReminderInputs(isPaid: subscriptions.plan.isPaid,
                                 tripsRevision: subscriptions.plan.isPaid ? store.trips.hashValue : 0,
                                 isActive: scenePhase == .active)) {
            let isPaid = subscriptions.plan.isPaid
            await notifications.scheduleMonthEndReminder(isPaid: isPaid, openItems: isPaid ? currentMonthOpenItems : 0)
        }
        .task(id: subscriptions.plan) {
            guard !askedRecordingChoice, store.needsRecordingVehicleChoice(isPaid: subscriptions.plan.isPaid) else { return }
            askedRecordingChoice = true
            showingRecordingChoice = true
        }
        .alert("Before auto-detect starts", isPresented: $detector.showsPermissionPrimer) {
            Button("Continue") { detector.confirmPermissionPrimer() }
            Button("Not now", role: .cancel) { }
        } message: {
            Text("iOS will ask two things. Location, set to “Always”, lets MileLog notice a drive starting while the app is closed. Notifications let it ask you to classify each trip when it ends.")
        }
    }
}

extension RootTabView {
    fileprivate var currentMonthOpenItems: Int {
        MonthEndCheck.build(trips: store.trips, candidates: store.mergeCandidates, month: Date()).openCount
    }
}

private struct ReminderInputs: Equatable {
    var isPaid: Bool
    /// Changes with any edit to a trip (classification, merge, address), not only the count.
    var tripsRevision: Int
    var isActive: Bool
}

private struct RoutedMonth: Identifiable {
    var month: Date
    var id: Date { month }
}
