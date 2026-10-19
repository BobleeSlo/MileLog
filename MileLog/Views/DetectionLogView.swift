import SwiftUI
import CoreLocation

struct DetectionLogView: View {
    @EnvironmentObject var detectionLog: DetectionLog
    @EnvironmentObject var detector: TripDetector

    var body: some View {
        List {
            Section {
                LabeledContent("Status") {
                    Text(detector.isEnabled ? "Monitoring" : "Off")
                        .foregroundColor(detector.isEnabled ? .green : .secondary)
                }
                LabeledContent("Permission", value: detector.permission.userText)
                LabeledContent("Active trip") {
                    if let trip = detector.activeTrip {
                        Text(Format.km(trip.distanceKm))
                            .foregroundColor(.blue)
                    } else {
                        Text("none").foregroundColor(.secondary)
                    }
                }
            }

            Section("Events") {
                if detectionLog.entries.isEmpty {
                    Text("No events yet.").foregroundColor(.secondary)
                } else {
                    ForEach(detectionLog.entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.message).font(.footnote)
                            Text(entry.timestamp, format: .dateTime.day().month().hour().minute().second())
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .listRowBackground(background(for: entry.level))
                    }
                }
            }
        }
        .navigationTitle("Detection log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !detectionLog.entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let url = detectionLog.exportAsFile() {
                            ShareLink(item: url) {
                                Label("Export & share log", systemImage: "square.and.arrow.up")
                            }
                        }
                        Button(role: .destructive) {
                            detectionLog.clear()
                        } label: {
                            Label("Clear log", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Log options")
                }
            }
        }
    }

    private func background(for level: DetectionLog.Level) -> Color {
        switch level {
        case .info:    return Color.clear
        case .warning: return Color.yellow.opacity(0.15)
        case .error:   return Color.red.opacity(0.15)
        }
    }
}

private extension CLAuthorizationStatus {
    var userText: String {
        switch self {
        case .notDetermined:        return String(localized: "Not asked yet", bundle: .app)
        case .restricted:           return String(localized: "Restricted", bundle: .app)
        case .denied:               return String(localized: "Denied — fix in Settings", bundle: .app)
        case .authorizedAlways:     return String(localized: "Always ✓", bundle: .app)
        case .authorizedWhenInUse:  return String(localized: "While using — needs upgrade", bundle: .app)
        @unknown default:           return String(localized: "Unknown", bundle: .app)
        }
    }
}
