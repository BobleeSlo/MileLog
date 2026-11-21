import SwiftUI

/// One list of everything that needs fixing in a month (R15, R16, F2). Each item
/// opens the trip or the merge screen; locked trips are shown apart, read-only.
struct MonthEndCheckView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var usage: Usage
    @State var month: Date
    @State private var showsMergeTrips = false

    private var check: MonthEndCheck {
        MonthEndCheck.build(trips: store.trips, candidates: store.mergeCandidates, month: month)
    }

    private var monthTitle: String {
        month.formatted(Date.FormatStyle().month(.wide).year().locale(Format.locale))
    }

    var body: some View {
        let check = check
        List {
            Section {
                HStack {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous month")
                    Spacer()
                    Text(monthTitle).font(.headline)
                    Spacer()
                    Button { step(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next month")
                        .disabled(Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month))
                }
                .buttonStyle(.borderless)
                if check.openCount == 0 {
                    Label("Nothing to fix this month", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("\(check.openCount) items to check", systemImage: "checklist")
                }
            }

            if !check.unreviewed.isEmpty {
                Section {
                    ForEach(check.unreviewed) { tripRow($0) }
                    Button {
                        confirmAll(check.unreviewed)
                    } label: {
                        Label("Confirm all as classified", systemImage: "checkmark.circle")
                    }
                } header: {
                    SectionHeaderLabel(title: "Not yet reviewed", systemImage: "eye")
                }
            }

            if !check.missingDetails.isEmpty {
                Section {
                    ForEach(check.missingDetails) { tripRow($0) }
                } header: {
                    SectionHeaderLabel(title: "Business trips without customer or purpose", systemImage: "person.crop.circle.badge.questionmark")
                }
            }

            if !check.likelySplits.isEmpty {
                Section {
                    ForEach(check.likelySplits) { pair in
                        Button {
                            showsMergeTrips = true
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(timeRange(pair.first.startedAt, pair.second.endedAt))
                                    .foregroundStyle(.primary)
                                Text("\(Format.km(pair.first.distanceKm)) + \(Format.km(pair.second.distanceKm)) · \(store.vehicleName(pair.first.vehicleID))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    SectionHeaderLabel(title: "Likely split trips", systemImage: "arrow.triangle.merge")
                }
            }

            if !check.missingAddresses.isEmpty {
                Section {
                    ForEach(check.missingAddresses) { tripRow($0) }
                } header: {
                    SectionHeaderLabel(title: "Missing addresses", systemImage: "mappin.slash")
                }
            }

            if !check.locked.isEmpty {
                Section {
                    ForEach(check.locked) { trip in
                        tripSummary(trip).foregroundStyle(.secondary)
                    }
                } header: {
                    SectionHeaderLabel(title: "Locked, can't be changed", systemImage: "lock")
                } footer: {
                    Text("These trips were locked before they were checked. They stay as recorded and don't count as open items.")
                        .font(.caption)
                }
            }
        }
        .onAppear { usage.record(.monthEndCheckOpens) }
        .navigationTitle("Month-end check")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsMergeTrips) { MergeTripsView() }
    }

    private func tripRow(_ trip: Trip) -> some View {
        NavigationLink {
            TripDetailView(trip: trip)
        } label: {
            tripSummary(trip)
        }
    }

    private func tripSummary(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(timeRange(trip.startedAt, trip.endedAt))
            Text("\(Format.km(trip.distanceKm)) · \(trip.type.label) · \(store.vehicleName(trip.vehicleID))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func timeRange(_ start: Date, _ end: Date) -> String {
        let day = start.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Format.locale))
        let until = end.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Format.locale))
        return "\(day) – \(until)"
    }

    private func step(_ months: Int) {
        month = Calendar.current.date(byAdding: .month, value: months, to: month) ?? month
    }

    private func confirmAll(_ trips: [Trip]) {
        let now = Date()
        for trip in trips {
            var reviewed = trip
            reviewed.reviewedAt = now
            store.updateTrip(reviewed)
        }
    }
}
