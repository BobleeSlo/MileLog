import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var detector: TripDetector
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
        .alert("Before auto-detect starts", isPresented: $detector.showsPermissionPrimer) {
            Button("Continue") { detector.confirmPermissionPrimer() }
            Button("Not now", role: .cancel) { }
        } message: {
            Text("iOS will ask two things. Location, set to “Always”, lets MileLog notice a drive starting while the app is closed. Notifications let it ask you to classify each trip when it ends.")
        }
    }
}
