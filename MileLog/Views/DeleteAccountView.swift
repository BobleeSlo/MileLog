import SwiftUI
import StoreKit

/// Settings → Account → Delete account (R21, KTD14): what is deleted, the
/// subscription warning, the password, and a final confirmation.
struct DeleteAccountView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var supabase: SupabaseService
    @EnvironmentObject var subscriptions: SubscriptionStore
    @EnvironmentObject var appLock: AppLock

    @State private var password = ""
    @State private var confirming = false
    @State private var isDeleting = false
    @State private var errorText: String?
    @State private var showingManageSubscription = false

    var body: some View {
        Form {
            Section {
                Text("Deleting your account permanently removes, from this iPhone and from MileLog's cloud:")
                Label("All trips, routes and the audit log", systemImage: "car")
                Label("Vehicles, customers and settings", systemImage: "gearshape")
                Label("Receipt photos", systemImage: "camera")
                Label("Your sign-in", systemImage: "person.crop.circle")
            } footer: {
                Text("This can't be undone. Export your trips as CSV first if you need a copy.")
            }

            if subscriptions.plan.isPaid {
                Section {
                    Text("Deleting the account doesn't cancel your App Store subscription. Cancel it first, or Apple keeps billing your Apple ID.")
                    Button("Manage subscription") { showingManageSubscription = true }
                } header: {
                    SectionHeaderLabel(title: "Subscription", systemImage: "creditcard")
                }
            }

            Section {
                SecureField("Password", text: $password)
                    .textContentType(.password)
            } header: {
                SectionHeaderLabel(title: "Confirm with your password", systemImage: "key")
            }

            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(.red)
                }
            }

            Section {
                Button(role: .destructive) {
                    confirming = true
                } label: {
                    HStack {
                        Spacer()
                        if isDeleting { ProgressView() } else { Text("Delete account").bold() }
                        Spacer()
                    }
                }
                .disabled(password.isEmpty || isDeleting)
            }
        }
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isDeleting)
        .navigationBarBackButtonHidden(isDeleting)
        .manageSubscriptionsSheet(isPresented: $showingManageSubscription)
        .confirmationDialog("Delete your account and all its data?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func delete() async {
        isDeleting = true
        errorText = nil
        defer { isDeleting = false }
        do {
            try await supabase.reauthenticate(password: password)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            errorText = String(localized: "You're offline. Connect to the internet to delete your account — nothing was changed.", bundle: .app)
            return
        } catch {
            errorText = String(localized: "That password isn't right.", bundle: .app)
            return
        }
        do {
            try await supabase.deleteAccount()
        } catch SupabaseService.DeleteAccountError.offline {
            errorText = String(localized: "You're offline. Connect to the internet to delete your account — nothing was changed.", bundle: .app)
            return
        } catch {
            errorText = String(localized: "The account couldn't be deleted. Your data is still here — try again.", bundle: .app)
            return
        }
        store.wipeAfterAccountDeletion()
        await subscriptions.accountChanged(to: nil)
        appLock.lock()
        await supabase.finishAfterAccountDeletion()
    }
}
