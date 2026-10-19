import SwiftUI

/// Identifies which header dropdown is open. Only one at a time.
enum DropdownID: String {
    case mode, genre, palette, source
}

/// One selectable row in a `DropdownMenu`.
struct DropdownEntry<Item: Hashable>: Identifiable {
    let value: Item
    let title: String
    var subtitle: String? = nil
    var glyph: String? = nil
    /// Optional two-stop colour swatch shown instead of the glyph.
    var swatch: (shadow: SIMD3<Float>, highlight: SIMD3<Float>)? = nil
    /// When set, picking this row runs the action instead of changing the
    /// selection. Used for things like an "Auto" toggle that isn't itself a
    /// member of the selection set.
    var action: (() -> Void)? = nil
    var id: String { title + (subtitle ?? "") }
}

/// A header pill that opens a floating list.
///
/// This replaces SwiftUI's `Menu` for the mode and genre pickers. `Menu` is
/// the obvious choice, but it renders through an NSView that can't be
/// captured by `ImageRenderer`, which made the chrome impossible to review
/// without a screen recorder. A hand-rolled list also lets the two pickers
/// share one visual language and lets the open list draw *over* the
/// visualiser instead of being clipped by the header.
struct DropdownMenu<Item: Hashable>: View {
    let id: DropdownID
    let entries: [DropdownEntry<Item>]
    @Binding var selection: Item
    var tint: Color = Color(red: 1, green: 0.17, blue: 0.84)
    /// Width of the collapsed pill. Long titles truncate rather than pushing
    /// the rest of the header off-screen.
    var pillWidth: CGFloat? = nil
    /// Extra content rendered inside the pill, after the title.
    var pillExtra: AnyView? = nil
    /// Rendered inside the pill, before the title — the source pill's status
    /// dot, for instance.
    var pillLeading: AnyView? = nil
    /// Overrides the title the pill shows, for pickers whose pill means
    /// something different from their selection (the source pill names what's
    /// flowing, not what's chosen).
    var pillTitle: String? = nil

    @EnvironmentObject var app: AppState

    private var isOpen: Bool { app.openDropdown == id }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.14)) {
                app.openDropdown = isOpen ? nil : id
            }
        } label: {
            HStack(spacing: 8) {
                if let leading = pillLeading {
                    leading
                } else if let swatch = current?.swatch {
                    PaletteSwatch(shadow: swatch.shadow, highlight: swatch.highlight)
                } else if let glyph = current?.glyph {
                    Text(glyph)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(tint)
                        .frame(width: 16, alignment: .leading)
                }
                Text(pillTitle ?? current?.title ?? "")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(1.6)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Color(white: 0.85))
                if let extra = pillExtra {
                    extra
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(white: 0.55))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(width: pillWidth)
            .background(
                RoundedRectangle(cornerRadius: 100)
                    .fill(Color.black.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 100)
                            .stroke(tint.opacity(0.5), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 100))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if isOpen {
                list
                    .fixedSize()
                    .padding(.top, 34)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(100)
            }
        }
    }

    private var current: DropdownEntry<Item>? {
        entries.first { $0.value == selection && $0.action == nil }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                Button {
                    if let action = entry.action {
                        action()
                    } else {
                        selection = entry.value
                    }
                    withAnimation(.easeOut(duration: 0.14)) { app.openDropdown = nil }
                } label: {
                    HStack(spacing: 10) {
                        if let swatch = entry.swatch {
                            PaletteSwatch(shadow: swatch.shadow, highlight: swatch.highlight)
                        } else if let glyph = entry.glyph {
                            Text(glyph)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(isSelected(entry) ? tint : Color(white: 0.45))
                                .frame(width: 16, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title)
                                .font(.system(size: 11, weight: .medium))
                                .tracking(1.4)
                                .foregroundStyle(isSelected(entry) ? Color.white : Color(white: 0.8))
                            if let sub = entry.subtitle {
                                Text(sub)
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .foregroundStyle(Color(white: 0.4))
                            }
                        }
                        Spacer(minLength: 12)
                        if isSelected(entry) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(tint)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, entry.subtitle == nil ? 5 : 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected(entry) ? tint.opacity(0.16) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(minWidth: 180, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.06, green: 0.03, blue: 0.11).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(tint.opacity(0.35), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.55), radius: 18, y: 6)
    }

    /// A row is "selected" if it represents the current selection. Rows with
    /// their own action (like the AUTO toggle) show selected by their own
    /// state instead.
    private func isSelected(_ entry: DropdownEntry<Item>) -> Bool {
        if entry.action != nil { return false }
        return entry.value == selection
    }
}
