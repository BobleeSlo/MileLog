import Foundation

/// The one place distances and money are turned into text.
///
/// Screens used to format these ad hoc (`String(format: "%.1f km")`,
/// `"€ %.2f"`, `"%.0f km"`), so the same trip read "3.4 km" in the list,
/// "3,430579 km" in the classify sheet and "3 km" in a total. Everything
/// now shows one decimal, with the decimal separator and € placement of
/// the app's language.
enum Format {
    /// Follows the in-app language choice; set by `AppLanguage`.
    nonisolated(unsafe) static var locale: Locale = .autoupdatingCurrent

    /// "12,5 km" / "12.5 km".
    static func km(_ km: Double) -> String {
        "\(number(km)) km"
    }

    /// "12,5" / "12.5" — for places that show the unit separately.
    static func number(_ km: Double) -> String {
        km.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    /// "5,38 €" / "€5.38".
    static func euros(_ amount: Double) -> String {
        amount.formatted(.currency(code: "EUR").locale(locale))
    }
}

extension Double {
    /// Distance rounded to the 0.1 km every screen and report shows, so
    /// totals equal the sum of the rows a user can see.
    var roundedToTenthKm: Double { (self * 10).rounded() / 10 }
}
