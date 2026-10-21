import SwiftUI

/// The ✕ in the corner of every sheet.
///
/// There used to be no consistent way out. The share sheet had nothing at all —
/// Escape worked, but you had to know that. The vibescapes panel had "Done",
/// the custom vibescape sheet had "Cancel" on some steps and a back arrow on
/// others. Same gesture, three different names, one of them absent.
///
/// One button, same place, same shape in all of them. Escape still closes every
/// sheet regardless — this is for the person who did not know that.
struct SheetCloseButton: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hovering = false

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(hovering ? Color.white : Color(white: 0.65))
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(Color.white.opacity(hovering ? 0.18 : 0.08))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Close")
    }
}

/// A sheet's title row, with the close button in the trailing corner.
///
/// Wrapped into a row of its own rather than pushed into whatever header each
/// sheet already had, so the button lands in the same pixel position in all of
/// them — which is the whole point of having one component.
struct SheetHeader<Trailing: View>: View {
    let title: String
    var tint: Color = Color(white: 0.55)
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(tint)
            Spacer(minLength: 8)
            trailing()
            SheetCloseButton()
        }
    }
}

extension SheetHeader where Trailing == EmptyView {
    init(title: String, tint: Color = Color(white: 0.55)) {
        self.init(title: title, tint: tint, trailing: { EmptyView() })
    }
}