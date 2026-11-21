import Foundation

/// Public pages the App Store requires links to (R12, R22). The texts are drafted
/// in docs/legal/; the owner publishes them at these addresses.
enum AppLinks {
    static let privacyPolicy = URL(string: "https://bobleeslo.github.io/milelog/privacy-policy")!
    static let termsOfUse = URL(string: "https://bobleeslo.github.io/milelog/terms-of-use")!
}
