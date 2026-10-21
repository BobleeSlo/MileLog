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

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MileLog Paid")
                .font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 10) {
                Label("Unlimited automatic trips", systemImage: "car.fill")
                Label("Monthly PDF reports and potni nalog", systemImage: "doc.richtext")
                Label("Receipt photos", systemImage: "camera")
                Label("Month-end check before you close a month", systemImage: "checklist")
                Label("More than one vehicle", systemImage: "car.2.fill")
            }
            .font(.body)
            Text("Free keeps manual recording, a monthly allowance of automatic trips, CSV export and all your history.")
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
