import SwiftUI
import StoreKit

/// What Paid adds, with Apple's subscription buttons (prices, trial eligibility,
/// restore) and the legal links App Review requires (KTD4, R11–R13).
struct PaywallView: View {
    @EnvironmentObject var subscriptions: SubscriptionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if subscriptions.plan == .freeOtherAccount {
                    otherAccount
                } else {
                    SubscriptionStoreView(productIDs: SubscriptionStore.productIDs) {
                        header
                    }
                    .subscriptionStoreControlStyle(.prominentPicker)
                    .storeButton(.visible, for: .restorePurchases)
                    // Inside our NavigationStack Apple's own ✕ doesn't dismiss the sheet;
                    // the toolbar's Close does.
                    .storeButton(.hidden, for: .cancellation)
                    .subscriptionStorePolicyDestination(url: AppLinks.privacyPolicy, for: .privacyPolicy)
                    .subscriptionStorePolicyDestination(url: AppLinks.termsOfUse, for: .termsOfService)
                    .inAppPurchaseOptions { _ in
                        subscriptions.userID.map { [.appAccountToken($0)] } ?? []
                    }
                    .onInAppPurchaseCompletion { _, result in
                        await subscriptions.purchaseCompleted(result)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: subscriptions.plan.isPaid) { _, paid in
                if paid { dismiss() }
            }
        }
    }

    /// StoreKit hosts this marketing content without the app's locale environment,
    /// so each string is resolved from the in-app language bundle up front.
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MileLog Paid")
                .font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 10) {
                Label(String(localized: "Unlimited automatic trips", bundle: .app), systemImage: "car.fill")
                Label(String(localized: "Monthly PDF reports and potni nalog", bundle: .app), systemImage: "doc.richtext")
                Label(String(localized: "Receipt photos", bundle: .app), systemImage: "camera")
                Label(String(localized: "Month-end check before you close a month", bundle: .app), systemImage: "checklist")
                Label(String(localized: "More than one vehicle", bundle: .app), systemImage: "car.2.fill")
            }
            .font(.body)
            Text(String(localized: "Free keeps manual recording, a monthly allowance of automatic trips, CSV export and all your history.", bundle: .app))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    /// R26: this Apple ID already pays for a different MileLog account.
    private var otherAccount: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Subscription belongs to another account")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("The Apple ID on this iPhone pays for a different MileLog account. Sign in with that account to use Paid, or subscribe with another Apple ID.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
