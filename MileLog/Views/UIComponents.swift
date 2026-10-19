import SwiftUI
import UIKit

// MARK: - Keyboard "Done" toolbar

private struct KeyboardDoneToolbar: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            // Leading, not trailing: on iOS 26 the keyboard toolbar floats
            // over the form, and a trailing "Done" covered the right-aligned
            // amount and rate fields.
            ToolbarItemGroup(placement: .keyboard) {
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
                .fontWeight(.semibold)
                Spacer()
            }
        }
        // A second way out when the toolbar doesn't show (seen with the
        // decimal pad): drag the form down to dismiss the keyboard.
        .scrollDismissesKeyboard(.interactively)
    }
}

extension View {
    /// Adds a "Done" button above the on-screen keyboard so the user can always
    /// dismiss it — important on forms where the Save / Resolve buttons would
    /// otherwise be hidden underneath.
    func keyboardDoneToolbar() -> some View {
        modifier(KeyboardDoneToolbar())
    }
}

// MARK: - DecimalField

/// Text input for money and rates: digits plus at most one decimal
/// separator ("," or "."), capped at `fractionDigits` decimals. A plain
/// `TextField(value:format:)` let "0,180,2" be typed and then quietly
/// dropped it.
enum DecimalInput {
    static func sanitize(_ text: String, fractionDigits: Int) -> String {
        var result = ""
        var seenSeparator = false
        var decimals = 0
        for ch in text {
            if ch.isASCII, ch.isNumber {
                if seenSeparator {
                    guard decimals < fractionDigits else { continue }
                    decimals += 1
                }
                result.append(ch)
            } else if (ch == "," || ch == "."), !seenSeparator, fractionDigits > 0 {
                seenSeparator = true
                result.append(ch)
            }
        }
        return result
    }

    static func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
}

struct DecimalField: View {
    let placeholder: String
    @Binding var value: Double
    var fractionDigits = 2
    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .onAppear {
                text = value.formatted(.number.precision(.fractionLength(0...fractionDigits))
                    .grouping(.never).locale(Format.locale))
            }
            .onChange(of: text) { _, new in
                let clean = DecimalInput.sanitize(new, fractionDigits: fractionDigits)
                if clean != new { text = clean; return }
                if let parsed = DecimalInput.parse(clean) { value = parsed }
            }
    }
}

// MARK: - PrettyStepper

/// Modern pill-shaped stepper: large hit targets, monospaced digits in the
/// middle, and clear disabled state at the bounds. Drop-in replacement for the
/// default `Stepper` when you want a more readable presentation.
struct PrettyStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    // LocalizedStringKey, not String: a plain String is shown as-is, so these
    // labels stayed English in every language.
    let label: LocalizedStringKey
    let unit: LocalizedStringKey
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Label above the controls at accessibility text sizes; side by side
        // the unit broke into "5 / min / sta- / tion / ary".
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .foregroundColor(.primary)
                Text("Tap − or + to adjust")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !stacked { Spacer() }

            // 44×44pt tap targets (Apple's HIG minimum), not the previous
            // 38×32 — this control is used for settings like "Lock trips
            // after"/"End trip after" in an app whose own premise is being
            // operated while getting in and out of a car, exactly the
            // low-precision-tap condition the 44pt guideline exists for.
            // Icon-only buttons also had no accessibilityLabel anywhere in
            // the app; VoiceOver would only ever announce "minus"/"plus"
            // with no indication of what they adjust (round-1 UX review
            // finding).
            HStack(spacing: 0) {
                Button { decrement() } label: {
                    Image(systemName: "minus")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(value <= range.lowerBound)
                .accessibilityLabel(Text("Decrease \(Text(label))"))

                Text("\(value) \(Text(unit))")
                    .font(.body.monospacedDigit())
                    // Shrink rather than hyphenate ("station-ary").
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .fontWeight(.medium)
                    .frame(minWidth: 56)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)

                Button { increment() } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(value >= range.upperBound)
                .accessibilityLabel(Text("Increase \(Text(label))"))
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .background(
                Capsule().fill(Color.accentColor.opacity(0.12))
            )
        }
        .padding(.vertical, 2)
    }

    private func decrement() {
        guard value > range.lowerBound else { return }
        value -= 1
        haptic()
    }

    private func increment() {
        guard value < range.upperBound else { return }
        value += 1
        haptic()
    }

    private func haptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - SectionHeaderLabel (icon + title for Form section headers)

struct SectionHeaderLabel: View {
    /// LocalizedStringKey so section headers are translated (see PrettyStepper).
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundColor(.secondary)
            .textCase(nil)
    }
}

// MARK: - PulsingDot (Recording / live status indicator)

struct PulsingDot: View {
    var color: Color = .white
    var size: CGFloat = 8

    @State private var animate = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(animate ? 1.6 : 1.0)
            .opacity(animate ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true),
                       value: animate)
            .onAppear { animate = true }
    }
}

// MARK: - TripTypeChip

struct TripTypeChip: View {
    let type: TripType
    var compact: Bool = false

    var body: some View {
        Text(type.label.uppercased())
            .font(compact ? .caption2.weight(.bold) : .caption.weight(.bold))
            .tracking(0.5)
            // One line, shrinking if it must: at large text sizes the badge
            // broke mid-word ("BUSI-NESS").
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 3)
            .background(Theme.tripColor(type).opacity(0.18))
            .foregroundColor(Theme.tripColor(type))
            .clipShape(Capsule())
    }
}

// MARK: - Card style modifier

private struct CardStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Theme.cardShadow, radius: 4, x: 0, y: 1)
    }
}

extension View {
    /// Applies the MileLog card surface: padding + rounded corners + subtle shadow.
    func cardStyle() -> some View {
        modifier(CardStyleModifier())
    }
}
