import SwiftUI
import CoreLocation
import UIKit
import StoreKit

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var supabase: SupabaseService
    @EnvironmentObject var detector: TripDetector
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var appLock: AppLock
    @EnvironmentObject var language: AppLanguage
    @EnvironmentObject var subscriptions: SubscriptionStore
    @EnvironmentObject var usage: Usage
    @State private var showingPaywall = false
    @State private var showingManageSubscription = false
    @State private var isRestoring = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var exportURL: URL?
    @State private var lockResultMessage: String?

    @State private var homeInput = ""
    @State private var workInput = ""
    @State private var geocodeStatus: String?
    @State private var isGeocoding = false

    // Monthly own-car PDF export state (PDF result lives in ReportSelectionView)
    @State private var pdfYear: Int = Calendar.current.component(.year, from: Date())
    @State private var pdfMonth: Int = Calendar.current.component(.month, from: Date())

    // Company car logbook PDF state
    @State private var logbookVehicleID: UUID?
    @State private var logbookYear: Int = Calendar.current.component(.year, from: Date())
    @State private var logbookMonth: Int = Calendar.current.component(.month, from: Date())

    private enum Field: Hashable { case rate, commuteRate, home, work }

    private var planName: String {
        switch subscriptions.plan {
        case .paid: String(localized: "Paid", bundle: .app)
        case .free: String(localized: "Free", bundle: .app)
        case .freeOtherAccount: String(localized: "Free — subscription on another account", bundle: .app)
        }
    }
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Reimbursement
                Section {
                    rateRow("Business rate", placeholder: "0.43",
                            value: $store.settings.reimbursementRate, focus: .rate)
                    rateRow("Commute rate", placeholder: "0.18",
                            value: $store.settings.commuteRate, focus: .commuteRate)
                    Text("Business rate applies to customer visits with your own car. Commute rate applies to Home ↔ Work trips. Private trips and company-car trips are excluded from the monthly own-car report.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } header: {
                    SectionHeaderLabel(title: "Reimbursement", systemImage: "eurosign.circle")
                }

                // MARK: Auto-detect
                Section {
                    Toggle(isOn: Binding(
                        get: { store.settings.autoDetectEnabled },
                        set: { detector.requestAutoDetect($0) }
                    )) {
                        Label("Detect trips automatically", systemImage: "location.fill")
                    }
                    Text(autoDetectHint)
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    PrettyStepper(
                        value: $store.settings.stationaryTimeoutMinutes,
                        range: 2...20,
                        label: "End trip after",
                        unit: "min stationary"
                    )

                    if store.settings.autoDetectEnabled && detector.permission != .authorizedAlways {
                        // Once permission is actually denied, re-requesting
                        // it (`detector.requestEnable()`) is a guaranteed
                        // no-op — iOS never re-shows the system prompt,
                        // `requestEnable()` just logs a warning nobody but
                        // this app's own debug screen ever sees. The button
                        // looked identically actionable in every state, but
                        // silently did nothing in the one state a user is
                        // most likely to be stuck in (round-1 UX review
                        // finding).
                        if detector.permission == .denied || detector.permission == .restricted {
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Label("Open Settings", systemImage: "gear")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button {
                                Task { await detector.requestEnable() }
                            } label: {
                                Label("Grant location permission", systemImage: "checkmark.shield")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    NavigationLink {
                        DetectionLogView()
                    } label: {
                        Label("Detection log", systemImage: "list.bullet.rectangle.portrait")
                    }
                } header: {
                    SectionHeaderLabel(title: "Auto-detect trips", systemImage: "dot.radiowaves.left.and.right")
                }

                // MARK: Energy mode
                Section {
                    Picker(selection: $store.settings.energyMode) {
                        ForEach(EnergyMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    } label: {
                        Label("Mode", systemImage: "bolt.fill")
                    }
                    .pickerStyle(.segmented)

                    Text(store.settings.energyMode.summary)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } header: {
                    SectionHeaderLabel(title: "Energy mode", systemImage: "battery.75")
                } footer: {
                    // This used to say "changes take effect on the next
                    // trip start" — factually wrong. LocationManager.apply
                    // (energyMode:) mutates the live CLLocationManager
                    // immediately, and TripDetector re-reads the mode's
                    // GPS-accuracy threshold live inside its per-fix
                    // callbacks — switching modes mid-drive immediately
                    // changes which GPS fixes get accepted into whatever
                    // trip is currently recording, the opposite of what
                    // this told the user (round-3 UX review finding).
                    Text("Switch presets any time — changes apply immediately, even to a trip already in progress.")
                        .font(.caption)
                }

                // MARK: Compliance & locking
                Section {
                    PrettyStepper(
                        value: $store.settings.lockAfterDays,
                        range: 1...MonthLocking.maxDaysIntoNextMonth,
                        label: "Lock a month's trips",
                        unit: "days into the next month"
                    )
                    Text("A month's trips stay editable until you generate its report after the month ends, or until this many days into the next month. Once locked, a trip's mileage / date / vehicle become immutable. Edits to purpose, customer, and notes are still allowed but recorded in the audit log.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Button {
                        // A compliance-relevant action that previously
                        // acted with zero outcome feedback — the button
                        // gave no indication of how many trips (if any)
                        // were actually locked (round-3 UX review finding).
                        switch store.applyAutomaticLocks() {
                        case .locked(let count):
                            lockResultMessage = count == 0
                                ? "No trips needed locking."
                                : "Locked \(count) trip\(count == 1 ? "" : "s")."
                        case .skippedAwaitingSettings:
                            // Don't claim success for a compliance action
                            // that declined to run (round-9 UX finding).
                            lockResultMessage = String(localized: "Waiting for your settings to finish syncing — try again in a moment.", bundle: .app)
                        }
                    } label: {
                        Label("Apply locks now", systemImage: "lock.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    if let lockResultMessage {
                        Text(lockResultMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    SectionHeaderLabel(title: "Compliance & locking", systemImage: "lock.shield")
                }

                // MARK: Home & Work
                Section {
                    addressField(
                        placeholder: "Home address",
                        text: $homeInput,
                        lat: store.settings.homeLat,
                        lng: store.settings.homeLng,
                        focus: .home
                    )

                    addressField(
                        placeholder: "Work address",
                        text: $workInput,
                        lat: store.settings.workLat,
                        lng: store.settings.workLng,
                        focus: .work
                    )

                    Button {
                        Task { await geocodeAddresses() }
                    } label: {
                        Label(isGeocoding ? "Resolving…" : "Resolve addresses",
                              systemImage: "mappin.and.ellipse")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGeocoding || (homeInput.isEmpty && workInput.isEmpty))

                    if let geocodeStatus {
                        Text(geocodeStatus)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    Text("Used to recognize commute trips (Home → Work mornings, Work → Home evenings).")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } header: {
                    SectionHeaderLabel(title: "Home & Work", systemImage: "house")
                }

                // MARK: Monthly own-car PDF (for bookkeeping reimbursement)
                Section {
                    Picker("Month", selection: $pdfMonth) {
                        ForEach(1...12, id: \.self) { m in
                            Text(monthLabel(m)).tag(m)
                        }
                    }
                    Picker("Year", selection: $pdfYear) {
                        ForEach(yearRange, id: \.self) { y in
                            Text(String(y)).tag(y)
                        }
                    }

                    NavigationLink {
                        ownCarSelection
                    } label: {
                        Label("Review trips and generate", systemImage: "list.bullet.rectangle.portrait")
                            .frame(maxWidth: .infinity)
                    }

                    Text("Own-car business + commute trips only. Private trips and company-car trips are excluded. On the next screen you can check / uncheck individual trips before generating the PDF for your accountant.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } header: {
                    SectionHeaderLabel(title: "Own-car monthly report", systemImage: "doc.text")
                }

                // MARK: Company car logbook (potni nalog)
                if !companyVehicles.isEmpty {
                    Section {
                        TextField("Company name", text: $store.settings.companyName)
                        TextField("Company address", text: $store.settings.companyAddress)
                        TextField("Company city", text: $store.settings.companyLocation)
                        TextField("Driver name", text: $store.settings.driverName)
                        // Every sibling field above has an English gloss;
                        // these two didn't, breaking the pattern the rest
                        // of the section establishes and leaving anyone
                        // unfamiliar with these specific Slovenian
                        // administrative terms with no in-app clue what to
                        // type (round-2 UX review finding).
                        TextField("Koristnik po nalogu (beneficiary)", text: $store.settings.tripBeneficiary)
                        TextField("Na relaciji (area/route)", text: $store.settings.tripArea)

                        Text("Printed in the potni nalog header. Per-vehicle seat count and vehicle type are set on the vehicle itself.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } header: {
                        SectionHeaderLabel(title: "Potni nalog details", systemImage: "building.2")
                    }

                    Section {
                        Picker("Vehicle", selection: $logbookVehicleID) {
                            ForEach(companyVehicles) { v in
                                Text("\(v.name) \(v.licensePlate.isEmpty ? "" : "· \(v.licensePlate)")")
                                    .tag(Optional(v.id))
                            }
                        }
                        Picker("Month", selection: $logbookMonth) {
                            ForEach(1...12, id: \.self) { m in
                                Text(monthLabel(m)).tag(m)
                            }
                        }
                        Picker("Year", selection: $logbookYear) {
                            ForEach(yearRange, id: \.self) { y in
                                Text(String(y)).tag(y)
                            }
                        }
                        NavigationLink {
                            logbookSelection
                        } label: {
                            Label("Review trips and generate", systemImage: "list.bullet.rectangle.portrait")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(logbookVehicleID == nil)

                        Text("Slovenian potni nalog layout: date / departure / arrival / from / to / purpose / km. Odometer-start, odometer-end and signature columns are left blank so you can fill them by hand. Review and select trips on the next screen.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } header: {
                        SectionHeaderLabel(title: "Company car · potni nalog", systemImage: "book")
                    }
                }

                // MARK: CSV export
                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Export \(store.exportableTripCount) trips as CSV",
                                  systemImage: "tablecells")
                        }
                    } else if store.exportableTripCount == 0 {
                        Text("No trips to export yet.")
                            .foregroundColor(.secondary)
                    } else {
                        // A CSV write failure previously collapsed into the
                        // "no trips" branch above, telling a user with
                        // hundreds of trips they had nothing to export
                        // (round-5 UX review finding) — the same class of
                        // silent failure round 2 fixed for PDF generation.
                        Text("Couldn't prepare the export — check available storage and try again.")
                            .foregroundColor(.red)
                    }
                } header: {
                    SectionHeaderLabel(title: "All trips (CSV)", systemImage: "tablecells")
                }

                // MARK: Security (biometric lock)
                Section {
                    if BiometricAuth.isAvailable {
                        Toggle(isOn: Binding(
                            get: { appLock.enabled },
                            set: { wantOn in
                                Task {
                                    if wantOn {
                                        await appLock.enable()   // only enables on successful auth
                                    } else {
                                        appLock.disable()
                                    }
                                }
                            }
                        )) {
                            Label("Require \(BiometricAuth.available.label)",
                                  systemImage: BiometricAuth.available.systemImage)
                        }
                        Text("When on, MileLog asks for \(BiometricAuth.available.label) each time you open it or return from the background.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        Label("Face ID / Touch ID not available", systemImage: "lock.slash")
                            .foregroundColor(.secondary)
                        Text("Set up Face ID or Touch ID in iOS Settings to enable app lock.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    SectionHeaderLabel(title: "Security", systemImage: "lock.shield")
                }

                // MARK: Language
                Section {
                    Picker(selection: Binding(get: { language.code },
                                              set: { language.select($0) })) {
                        Text("Same as iPhone").tag(AppLanguage.system)
                        ForEach(language.available, id: \.self) { code in
                            Text(verbatim: AppLanguage.nativeName(for: code)).tag(code)
                        }
                    } label: {
                        Label("App language", systemImage: "globe")
                    }
                } header: {
                    SectionHeaderLabel(title: "Language", systemImage: "character.bubble")
                } footer: {
                    Text("Changes the language of MileLog only — the rest of your iPhone stays as it is.")
                        .font(.caption)
                }

                // MARK: Plan
                Section {
                    LabeledContent("Current plan", value: planName)
                    if case .paid(let until?) = subscriptions.plan {
                        LabeledContent("Renews or ends", value: until.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Format.locale)))
                    }
                    if subscriptions.plan.isPaid {
                        Button {
                            showingManageSubscription = true
                        } label: {
                            Label("Manage subscription", systemImage: "creditcard")
                        }
                    } else {
                        Button {
                            showingPaywall = true
                        } label: {
                            Label("See what Paid adds", systemImage: "star")
                        }
                    }
                    Button {
                        isRestoring = true
                        Task {
                            await subscriptions.restore()
                            isRestoring = false
                        }
                    } label: {
                        HStack {
                            Label("Restore purchases", systemImage: "arrow.clockwise")
                            if isRestoring { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isRestoring)
                } header: {
                    SectionHeaderLabel(title: "Plan", systemImage: "star.circle")
                } footer: {
                    HStack(spacing: 16) {
                        Link("Privacy policy", destination: AppLinks.privacyPolicy)
                        Link("Terms of use", destination: AppLinks.termsOfUse)
                    }
                    .font(.caption)
                }

                // MARK: Developer (debug and TestFlight builds only)
                if BuildChannel.isTestBuild {
                    Section {
                        Picker("Pretend plan", selection: Binding(
                            get: { subscriptions.developerOverride },
                            set: { newValue in
                                // A lapse asks again which vehicle keeps recording.
                                if newValue == .lapsed { store.recordingVehicleID = nil }
                                subscriptions.developerOverride = newValue
                            }
                        )) {
                            ForEach(DeveloperPlanOverride.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    } header: {
                        SectionHeaderLabel(title: "Developer", systemImage: "hammer")
                    } footer: {
                        Text("Test builds only. The app behaves as if on this plan; your real subscription and the server are unchanged. App Store builds never show this.")
                            .font(.caption)
                    }
                }

                // MARK: Privacy
                Section {
                    Toggle("Share anonymous usage", isOn: Binding(
                        get: { usage.consent == true },
                        set: { usage.consent = $0 }
                    ))
                } header: {
                    SectionHeaderLabel(title: "Privacy", systemImage: "hand.raised")
                } footer: {
                    Text("Once a month MileLog sends rough counts — how many automatic trips, reports, receipts and month-end checks, in ranges such as 11–15 — with no trips, places or device details. It helps decide the Free plan's limits. Nothing depends on it.")
                        .font(.caption)
                }

                // MARK: Account
                Section {
                    LabeledContent("Signed in as", value: supabase.userEmail ?? "—")
                    Button(role: .destructive) {
                        // Re-lock immediately rather than waiting for the
                        // next .background transition — otherwise signing
                        // out and back in (or as a different account)
                        // without ever backgrounding the app skips the
                        // Face ID/Touch ID prompt this section promises
                        // "each time you open it" (round-9 adversarial
                        // review finding).
                        appLock.lock()
                        Task { await supabase.signOut() }
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    NavigationLink {
                        DeleteAccountView()
                    } label: {
                        Label("Delete account", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                } header: {
                    SectionHeaderLabel(title: "Account", systemImage: "person.crop.circle")
                }

                Section {
                    LabeledContent("App", value: "MileLog")
                    LabeledContent("Version", value: AppVersion.display)
                    LabeledContent("Sync", value: String(localized: "Private cloud backup", bundle: .app))
                } header: {
                    SectionHeaderLabel(title: "About", systemImage: "info.circle")
                } footer: {
                    Text("Quote the version when reporting a problem — it identifies exactly which build produced a Detection Log.")
                        .font(.caption)
                }
            }
            .navigationTitle("Settings")
            .keyboardDoneToolbar()
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .manageSubscriptionsSheet(isPresented: $showingManageSubscription)
            .onAppear {
                refreshExport()
                // With a single company car there's nothing to choose — the
                // greyed-out "Review trips" gave no hint why it was disabled.
                if logbookVehicleID == nil, companyVehicles.count == 1 {
                    logbookVehicleID = companyVehicles.first?.id
                }
                homeInput = store.settings.homeAddress
                workInput = store.settings.workAddress
            }
            .onChange(of: store.trips.count) { refreshExport() }
            .onChange(of: store.settings.reimbursementRate) {
                store.saveSettings()
                refreshExport()
            }
            .onChange(of: store.settings.commuteRate) {
                store.saveSettings()
                refreshExport()
            }
            // Auto-detect enable/disable is handled by detector.setAutoDetect
            // via the Toggle binding (shared with the Record-screen toggle),
            // so no onChange handler is needed here.
            .onChange(of: store.settings.stationaryTimeoutMinutes) { store.saveSettings() }
            .onChange(of: store.settings.lockAfterDays) { store.saveSettings() }
            .onChange(of: store.settings.companyName) { store.saveSettings() }
            .onChange(of: store.settings.companyAddress) { store.saveSettings() }
            .onChange(of: store.settings.companyLocation) { store.saveSettings() }
            .onChange(of: store.settings.driverName) { store.saveSettings() }
            .onChange(of: store.settings.tripBeneficiary) { store.saveSettings() }
            .onChange(of: store.settings.tripArea) { store.saveSettings() }
            .onChange(of: store.settings.energyMode) { _, newMode in
                store.saveSettings()
                location.apply(energyMode: newMode)
                // TripDetector picks up the new mode automatically on next trip start.
            }
        }
    }

    // MARK: - Rate row helper

    /// Label and value side by side; stacked at accessibility text sizes,
    /// where the label broke into "Busi-ness rate" and the value showed "0,…".
    private func rateRow(_ label: LocalizedStringKey, placeholder: String,
                         value: Binding<Double>, focus: Field) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout())
        return layout {
            Text(label)
            if !stacked { Spacer() }
            HStack {
                DecimalField(placeholder: placeholder, value: value, fractionDigits: 3)
                    .focused($focusedField, equals: focus)
                    .frame(maxWidth: stacked ? .infinity : 80)
                Text("€/km").foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Address field helper

    @ViewBuilder
    private func addressField(
        placeholder: LocalizedStringKey,
        text: Binding<String>,
        lat: Double?,
        lng: Double?,
        focus: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($focusedField, equals: focus)
                .onSubmit {
                    Task { await geocodeAddresses() }
                }

            if let lat, let lng {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption2)
                    Text(String(format: "%.4f, %.4f", lat, lng))
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var autoDetectHint: String {
        if !store.settings.autoDetectEnabled {
            return String(localized: "When enabled, the app starts trips automatically when you start driving and ends them when you stop.", bundle: .app)
        }
        switch detector.permission {
        case .authorizedAlways:
            return detector.isEnabled
                ? "Monitoring is active. Pair your cars under Vehicles to identify which car you're driving."
                : "Permission granted but monitoring is off — toggle off and on to restart."
        case .authorizedWhenInUse:
            return String(localized: "Need 'Always' location permission for background detection. Tap the button below to upgrade.", bundle: .app)
        case .notDetermined:
            return String(localized: "Tap the button below to grant location permission.", bundle: .app)
        case .denied, .restricted:
            return String(localized: "Location permission denied. Enable 'Always' for MileLog in iOS Settings → Privacy.", bundle: .app)
        @unknown default:
            return ""
        }
    }

    private func refreshExport() {
        exportURL = store.trips.isEmpty ? nil : store.exportCSV()
    }

    /// In the app's language, standalone form ("oktober", not "oktobra").
    private func monthLabel(_ month: Int) -> String {
        let df = DateFormatter()
        df.locale = Format.locale
        return df.standaloneMonthSymbols[month - 1].capitalized(with: Format.locale)
    }

    /// Years that have at least one trip plus the current year.
    private var yearRange: [Int] {
        let cal = Calendar.current
        let thisYear = cal.component(.year, from: Date())
        var years = Set<Int>([thisYear])
        for trip in store.trips {
            years.insert(cal.component(.year, from: trip.startedAt))
        }
        return years.sorted(by: >)
    }

    /// Vehicles eligible for the company-car logbook export.
    /// Archived vehicles are hidden — the user has to restore one first
    /// before they can run a logbook against it.
    private var companyVehicles: [Vehicle] {
        store.activeVehicles.filter { $0.type == .company }
    }

    // MARK: - Selection destinations

    @ViewBuilder
    private var ownCarSelection: some View {
        let candidates = PDFReporter.ownCarCandidates(
            trips: store.trips,
            vehicleLookup: { store.vehicle($0) },
            year: pdfYear, month: pdfMonth
        )
        let businessRate = store.settings.reimbursementRate
        let commuteRate = store.settings.commuteRate
        let year = pdfYear, month = pdfMonth

        ReportSelectionView(
            title: "\(monthLabel(month)) \(String(year))",
            candidateTrips: candidates,
            formatRow: { trip in AnyView(ownCarRow(trip: trip)) },
            generate: { chosen in
                let result = PDFReporter.generateMonthlyOwnCar(
                    trips: chosen,
                    vehicleLookup: { store.vehicle($0) },
                    businessRate: businessRate,
                    commuteRate: commuteRate,
                    year: year, month: month
                )
                // A report for an ended month closes it for its vehicles (KTD10).
                if result != nil {
                    store.closeMonth(year: year, month: month, vehicleIDs: Set(chosen.map(\.vehicleID)), reportKind: "own_car")
                }
                return result
            }
        )
    }

    @ViewBuilder
    private var logbookSelection: some View {
        if let id = logbookVehicleID, let vehicle = store.vehicle(id) {
            let candidates = PDFReporter.companyLogbookCandidates(
                trips: store.trips,
                vehicle: vehicle,
                year: logbookYear, month: logbookMonth
            )
            let year = logbookYear, month = logbookMonth
            let captured = vehicle

            ReportSelectionView(
                title: "\(monthLabel(month)) \(String(year))",
                subtitle: [vehicle.name.trimmingCharacters(in: .whitespaces), vehicle.licensePlate]
                    .filter { !$0.isEmpty }.joined(separator: " · "),
                warning: store.settings.companyName.isEmpty || store.settings.driverName.isEmpty
                    ? "Company name or driver isn't set, so the PDF leaves blank lines for them. Add them under Potni nalog details in Settings."
                    : nil,
                candidateTrips: candidates,
                // The potni nalog is an official business-travel-order
                // document (every generated page hardcodes "Vrsta prevoza:
                // SLUŽBENA POT"). Unlike the own-car report, this report's
                // candidates intentionally include private trips too — so a
                // full logbook can reconcile total company-car mileage — but
                // they must never be silently pre-checked into an official
                // business record. Default-select only business/commute;
                // private trips stay visible (badged, see logbookRow) and
                // selectable, requiring a conscious opt-in (round-9
                // adversarial review finding).
                defaultSelected: candidates.filter { $0.type != .privateTrip },
                formatRow: { trip in AnyView(logbookRow(trip: trip)) },
                generate: { chosen in
                    let result = PDFReporter.generateCompanyCarLogbook(
                        trips: chosen,
                        vehicle: captured,
                        settings: store.settings,
                        year: year, month: month
                    )
                    if result != nil {
                        store.closeMonth(year: year, month: month, vehicleIDs: [captured.id], reportKind: "company_logbook")
                    }
                    return result
                }
            )
        }
    }

    /// Three-column row used in both selection screens: [date + type chip] |
    /// customer-or-purpose (flexible width, prominent) | km (right-aligned).
    @ViewBuilder
    private func ownCarRow(trip: Trip) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.medium))
                Text(trip.type.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(typeBadgeColor(trip.type).opacity(0.2))
                    .foregroundColor(typeBadgeColor(trip.type))
                    .clipShape(Capsule())
            }
            .frame(width: 84, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(customerOrPurpose(trip))
                    .font(.subheadline)
                    .foregroundColor(hasCustomerOrPurpose(trip) ? .primary : .secondary)
                    .lineLimit(2)
                if !trip.customerName.isEmpty && !trip.purpose.isEmpty {
                    Text(trip.purpose)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(Format.km(trip.distanceKm))
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func logbookRow(trip: Trip) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.medium))
                Text(trip.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                // Unlike ownCarRow, this list previously showed no type
                // indicator at all, so a private trip riding along in a
                // company car's official travel-order document looked
                // identical to a business one (round-9 adversarial review
                // finding).
                Text(trip.type.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(typeBadgeColor(trip.type).opacity(0.2))
                    .foregroundColor(typeBadgeColor(trip.type))
                    .clipShape(Capsule())
            }
            .frame(width: 84, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(customerOrPurpose(trip))
                    .font(.subheadline)
                    .foregroundColor(hasCustomerOrPurpose(trip) ? .primary : .secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(Format.km(trip.distanceKm))
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundColor(.secondary)
        }
    }

    private func customerOrPurpose(_ trip: Trip) -> String {
        if !trip.customerName.isEmpty { return trip.customerName }
        if !trip.purpose.isEmpty      { return trip.purpose }
        return "—"
    }

    private func hasCustomerOrPurpose(_ trip: Trip) -> Bool {
        !trip.customerName.isEmpty || !trip.purpose.isEmpty
    }

    private func typeBadgeColor(_ type: TripType) -> Color {
        switch type {
        case .business:    return .blue
        case .commute:     return .orange
        case .privateTrip: return .gray
        }
    }

    private func geocodeAddresses() async {
        focusedField = nil          // dismiss keyboard
        isGeocoding = true
        defer { isGeocoding = false }
        geocodeStatus = String(localized: "Resolving…", bundle: .app)
        var status: [String] = []

        if !homeInput.isEmpty {
            if let coord = await Geocoding.coordinate(for: homeInput) {
                store.settings.homeAddress = homeInput
                store.settings.homeLat = coord.latitude
                store.settings.homeLng = coord.longitude
                status.append("Home ✓")
            } else {
                status.append("Home not found")
            }
        }

        if !workInput.isEmpty {
            if let coord = await Geocoding.coordinate(for: workInput) {
                store.settings.workAddress = workInput
                store.settings.workLat = coord.latitude
                store.settings.workLng = coord.longitude
                status.append("Work ✓")
            } else {
                status.append("Work not found")
            }
        }

        store.saveSettings()
        geocodeStatus = status.joined(separator: " · ")
    }
}

/// Build identity, read from the bundle at runtime.
///
/// Both values come from Info.plist. Note that with
/// `GENERATE_INFOPLIST_FILE = NO` the Version and Build fields on Xcode's
/// General tab edit `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`, which
/// nothing in this target reads — typing a new number there has no effect.
/// `tools/bump_version.py` writes the plist directly, which is what ships.
enum AppVersion {
    static var short: String { string("CFBundleShortVersionString") }
    static var build: String { string("CFBundleVersion") }

    /// e.g. "1.1 (2)" — the form to quote in a bug report.
    static var display: String { "\(short) (\(build))" }

    /// Host only, never the key: this row is on a screen users are asked to
    /// screenshot when something misbehaves.
    static var backendHost: String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let host = URL(string: raw)?.host, !host.isEmpty
        else { return "not configured" }
        return host
    }

    private static func string(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? "—"
    }
}
