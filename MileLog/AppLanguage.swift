import SwiftUI
import Combine

/// The app's own language choice, separate from the iPhone's language.
///
/// The choice is stored the same way iOS's per-app language setting
/// (Settings → Apps → MileLog → Language) stores it — `AppleLanguages` in
/// the app's own defaults domain — so picking a language here or there
/// gives the same result, and each screen shows the other's choice.
///
/// The list is whatever the app ships: every language in the string
/// catalogs appears automatically, so a new translation needs no code here.
@MainActor
final class AppLanguage: ObservableObject {

    /// Empty means "follow the iPhone's language".
    static let system = ""

    @Published private(set) var code: String

    /// Language codes the app is translated into, e.g. `["en", "sl"]`.
    let available: [String]

    private let defaults = UserDefaults.standard

    init() {
        let shipped = Bundle.main.localizations.filter { $0 != "Base" }
        available = shipped.sorted {
            Self.nativeName(for: $0).localizedCaseInsensitiveCompare(Self.nativeName(for: $1)) == .orderedAscending
        }
        code = Self.appOverride(in: shipped) ?? Self.system
    }

    /// Locale handed to SwiftUI, which uses it to look up `Text` strings and
    /// to format numbers and dates. An override keeps the user's region, so
    /// choosing Slovenian on a German-region phone still formats as German.
    var locale: Locale {
        guard code != Self.system else { return .autoupdatingCurrent }
        var components = Locale.Components(locale: .autoupdatingCurrent)
        components.languageComponents = Locale.Language.Components(languageCode: Locale.LanguageCode(code))
        return Locale(components: components)
    }

    func select(_ newCode: String) {
        guard newCode != code else { return }
        code = newCode
        if newCode == Self.system {
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        } else {
            defaults.set([newCode], forKey: Self.appleLanguagesKey)
        }
    }

    /// A language's name in that language, e.g. "slovenščina" → "Slovenščina".
    nonisolated static func nativeName(for code: String) -> String {
        let locale = Locale(identifier: code)
        return locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? code
    }

    // MARK: - Private

    private static let appleLanguagesKey = "AppleLanguages"

    /// The language set for this app only. `UserDefaults.standard` also
    /// returns the system-wide `AppleLanguages`, so the app's own domain is
    /// read directly to tell "chosen for MileLog" apart from "the phone's".
    private static func appOverride(in shipped: [String]) -> String? {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let domain = UserDefaults.standard.persistentDomain(forName: bundleID),
              let first = (domain[appleLanguagesKey] as? [String])?.first else { return nil }
        // "sl-SI" from iOS Settings → "sl".
        let language = Locale(identifier: first).language.languageCode?.identifier ?? first
        return shipped.contains(language) ? language : nil
    }
}
