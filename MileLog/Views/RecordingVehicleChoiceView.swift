import SwiftUI

/// After the plan becomes Free with two or more active vehicles: which one keeps
/// recording (R10, KTD11). Dismissing keeps the most recently used vehicle.
struct RecordingVehicleChoiceView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var subscriptions: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.activeVehicles) { vehicle in
                        Button {
                            store.recordingVehicleID = vehicle.id
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(vehicle.name).foregroundStyle(.primary)
                                    Text(vehicle.type.label).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if vehicle.id == store.recordingVehicle(isPaid: false)?.id {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Trips in your other vehicles aren't recorded on the Free plan. All your vehicles, trips and receipts stay. Subscribe to record every vehicle again.")
                }
                Section {
                    Button("See what Paid adds") { showingPaywall = true }
                }
            }
            .navigationTitle("Which vehicle records?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .onChange(of: subscriptions.plan.isPaid) { _, paid in
                if paid { dismiss() }
            }
        }
    }
}
