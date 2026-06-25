import SwiftUI

// MARK: - Shared component vocabulary
//
// The reusable building blocks every screen composes from, so the re-skin is
// consistent by construction (not by discipline). All visuals follow the
// "calm pro-tool" system in ShiftDesign.swift: flat surfaces, hairline borders,
// one indigo accent, soft tints — never gradients or glassmorphism on working
// surfaces. Role/category identity reads from an SF Symbol + label, not hue.

// MARK: - Section header

/// The standard uppercase, letter-spaced label above a content group
/// (e.g. "VENUES & SPACES"), with an optional trailing accessory ("View all").
/// Standardizes the inlined `.microLabel()` usages.
struct ShiftSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).microLabel()
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension ShiftSectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

// MARK: - Icon tile

/// Soft-tinted rounded glyph tile — an accent icon over a low-opacity fill of
/// the same hue. The canonical leading element for list rows and quick actions.
struct ShiftIconTile: View {
    let systemImage: String
    var tint: Color = ShiftPalette.accent
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                ShiftPalette.soft(tint),
                in: RoundedRectangle(cornerRadius: ShiftDesign.iconRadius, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Chip

/// Flat, soft-tinted pill for status / role / metadata. Replaces gradient
/// capsules — colour is a quiet tint, never a saturated fill unless `filled`.
struct ShiftChip: View {
    let text: String
    var tint: Color = ShiftPalette.neutral
    var systemImage: String?
    var filled: Bool = false
    var uppercase: Bool = true

    init(
        _ text: String,
        tint: Color = ShiftPalette.neutral,
        systemImage: String? = nil,
        filled: Bool = false,
        uppercase: Bool = true
    ) {
        self.text = text
        self.tint = tint
        self.systemImage = systemImage
        self.filled = filled
        self.uppercase = uppercase
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2.weight(.bold))
            }
            Text(text)
                .font(.caption2.weight(.semibold))
                .textCase(uppercase ? .uppercase : nil)
                .kerning(uppercase ? 0.6 : 0)
        }
        .foregroundStyle(filled ? Color.white : tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            filled ? AnyShapeStyle(tint) : AnyShapeStyle(ShiftPalette.soft(tint)),
            in: Capsule()
        )
    }
}

// MARK: - List row

/// Trailing chevron accessory used by the default `ShiftRow`.
struct ShiftChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

/// Canonical flat list row over a `proCard`: leading icon tile, title + optional
/// subtitle, and a trailing accessory (defaults to a chevron). The repeated
/// "tool row" anatomy used across Marketplace, Settings, Vendor dashboard, etc.
struct ShiftRow<Trailing: View>: View {
    let icon: String
    var tint: Color = ShiftPalette.accent
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(
        icon: String,
        tint: Color = ShiftPalette.accent,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 14) {
            ShiftIconTile(systemImage: icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .proCard()
        .contentShape(Rectangle())
    }
}

extension ShiftRow where Trailing == ShiftChevron {
    init(icon: String, tint: Color = ShiftPalette.accent, title: String, subtitle: String? = nil) {
        self.init(icon: icon, tint: tint, title: title, subtitle: subtitle) { ShiftChevron() }
    }
}

// MARK: - Button styles

/// Filled, full-width primary action. `tint` defaults to the indigo accent;
/// pass `ShiftPalette.live` for go/complete actions (e.g. "Mark Complete").
struct ShiftFilledButtonStyle: ButtonStyle {
    var tint: Color = ShiftPalette.accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                tint.opacity(isEnabled ? 1 : 0.4),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// Quiet secondary action — tinted text over a soft tint of the same hue.
struct ShiftSoftButtonStyle: ButtonStyle {
    var tint: Color = ShiftPalette.accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                ShiftPalette.soft(tint),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

extension ButtonStyle where Self == ShiftFilledButtonStyle {
    static var shiftFilled: ShiftFilledButtonStyle { ShiftFilledButtonStyle() }
    static func shiftFilled(_ tint: Color) -> ShiftFilledButtonStyle { ShiftFilledButtonStyle(tint: tint) }
}

extension ButtonStyle where Self == ShiftSoftButtonStyle {
    static var shiftSoft: ShiftSoftButtonStyle { ShiftSoftButtonStyle() }
    static func shiftSoft(_ tint: Color) -> ShiftSoftButtonStyle { ShiftSoftButtonStyle(tint: tint) }
}

// MARK: - Avatar

/// Circular avatar with an initials fallback and an optional status dot
/// (Live Dashboard team readiness, reviews, chat).
struct ShiftAvatar: View {
    let name: String
    var imageURL: URL?
    var size: CGFloat = 44
    var status: Color?

    @Environment(\.colorScheme) private var colorScheme

    private var initials: String {
        let chars = name.split(separator: " ").prefix(2).compactMap(\.first)
        return String(chars).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(ShiftPalette.soft(ShiftPalette.accent))
            if let imageURL {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsText
                }
                .clipShape(Circle())
            } else {
                initialsText
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.white.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            if let status {
                Circle()
                    .fill(status)
                    .frame(width: size * 0.26, height: size * 0.26)
                    .overlay(Circle().strokeBorder(ProBackgroundColor.base(colorScheme), lineWidth: 2))
            }
        }
        .accessibilityLabel(name)
    }

    private var initialsText: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(ShiftPalette.accent)
    }
}

/// Solid fill that matches `ProBackground` for ringing status dots / cut-outs
/// so they read as "punched through" the canvas.
enum ProBackgroundColor {
    static func base(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.067, green: 0.060, blue: 0.112)
            : Color(red: 0.945, green: 0.937, blue: 0.985)
    }
}

// MARK: - Previews

#Preview("Components") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            ShiftSectionHeader("Venues & Spaces") {
                Text("View all").font(.caption.weight(.semibold)).foregroundStyle(ShiftPalette.accent)
            }

            HStack(spacing: 8) {
                ShiftChip("Planning", tint: ShiftPalette.accent)
                ShiftChip("Live", tint: ShiftPalette.live, systemImage: "dot.radiowaves.left.and.right")
                ShiftChip("Pro", tint: ShiftPalette.accent, filled: true, uppercase: false)
            }

            ShiftRow(icon: "tray.full.fill", title: "Inbox", subtitle: "Event requests & messages")

            ShiftRow(icon: "checkmark.seal.fill", tint: ShiftPalette.live, title: "Listed in the marketplace", subtitle: "5 busy days this month") {
                ShiftChip("3", tint: .red, filled: true, uppercase: false)
            }

            HStack(spacing: 16) {
                ShiftAvatar(name: "Avery Chen", status: ShiftPalette.live)
                ShiftAvatar(name: "Dana Ruiz", status: ShiftPalette.warm)
                ShiftAvatar(name: "Sam Park", status: .red)
            }

            Button("Mark Complete") {}.buttonStyle(.shiftFilled(ShiftPalette.live))
            Button("Continue with Email") {}.buttonStyle(.shiftFilled)
            Button("Decline") {}.buttonStyle(.shiftSoft(ShiftPalette.neutral))
        }
        .padding(20)
    }
    .background { ProBackground() }
}
