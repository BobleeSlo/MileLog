import SwiftUI

/// Lists trips that look like one drive split in two, and merges the ones
/// the user ticks. Nothing is merged without confirmation: the rules that
/// find candidates (same car, short gap, close together) are a strong hint,
/// not proof — a quick customer stop is legitimately its own trip.
struct MergeTripsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    /// Snapshot taken when the sheet opens, so ticking boxes is not disturbed
    /// by the list recomputing underneath.
    @State private var candidates: [Store.MergeCandidate] = []
    @State private var selected: Set<String> = []
    @State private var isMerging = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "No split trips",
                        systemImage: "checkmark.circle",
                        description: Text("Every trip already stands on its own.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Split trips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(isMerging)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isMerging {
                        ProgressView()
                    } else {
                        Button("Merge \(selected.count)") { Task { await merge() } }
                            .disabled(selected.isEmpty)
                    }
                }
            }
            .alert("Merge stopped",
                   isPresented: Binding(get: { errorMessage != nil },
                                        set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onAppear {
            candidates = store.mergeCandidates
            selected = Set(candidates.map(\.id))
        }
        .interactiveDismissDisabled(isMerging)
    }

    private var list: some View {
        List {
            Section {
                ForEach(candidates) { pair in
                    Button {
                        if selected.contains(pair.id) { selected.remove(pair.id) }
                        else { selected.insert(pair.id) }
                    } label: {
                        MergeCandidateRow(pair: pair,
                                          vehicleName: store.vehicleName(pair.first.vehicleID),
                                          isSelected: selected.contains(pair.id))
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Same car, under \(Int(Store.mergeMaxGapMinutes)) min and \(Int(Store.mergeMaxGapMetres)) m apart. The merged trip keeps the first trip's start, type and purpose, and adds both distances plus the gap between them. A stop at a customer should stay a separate trip — untick it.")
            }
        }
    }

    private func merge() async {
        let chosen = candidates.filter { selected.contains($0.id) }
        isMerging = true
        defer { isMerging = false }
        do {
            try await store.mergeTrips(chosen)
            dismiss()
        } catch {
            errorMessage = "\(error.localizedDescription)\n\nTrips merged before the problem are saved. Check your connection and open this screen again for the rest."
            candidates = store.mergeCandidates
            selected = Set(candidates.map(\.id))
        }
    }
}

/// One candidate pair: when, where, how far, and the gap between the parts.
private struct MergeCandidateRow: View {
    let pair: Store.MergeCandidate
    let vehicleName: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(pair.first.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.semibold))
                Text(part(pair.first))
                    .font(.caption)
                Text(part(pair.second))
                    .font(.caption)
                Text(gapLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func part(_ trip: Trip) -> String {
        let from = trip.startAddress.isEmpty ? "?" : trip.startAddress
        let to = trip.endAddress.isEmpty ? "?" : trip.endAddress
        let time = "\(trip.startedAt.formatted(date: .omitted, time: .shortened))–\(trip.endedAt.formatted(date: .omitted, time: .shortened))"
        return "\(time) · \(Format.km(trip.distanceKm)) · \(from) → \(to)"
    }

    private var gapLine: String {
        let minutes = max(0, Int(pair.gapMinutes.rounded()))
        let metres = pair.gapMetres.map { "\(Int($0.rounded())) m" } ?? "?"
        return "\(vehicleName) · stopped \(minutes) min, \(metres) apart"
    }
}
