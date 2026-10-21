import SwiftUI
import AppKit

/// A pointer cursor over a control that does something when clicked.
///
/// SwiftUI has no `.cursor()` modifier, so this is the usual way round it:
/// the cursor is set when the pointer arrives and put back when it leaves.
/// `set()` rather than `push()`/`pop()`, so a control that appears or
/// disappears under the pointer can't leave the cursor stack unbalanced.
private struct PointingHand: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

extension View {
    /// Shows a pointing hand over this view.
    func pointingHand() -> some View {
        modifier(PointingHand())
    }
}

/// The View All panel: every vibescape the app has, with a picture of it, and a
/// switch to say whether it appears in the vibescape list and takes part in Auto
/// Scan.
///
/// This is where a vibescape the user has never seen becomes findable. The drop-
/// down is a list of names; this is a wall of pictures, so someone browsing
/// on the hunt for something to look at can find it by sight. It is also
/// where the vibescape list gets curated — a person with twenty vibescapes wants
/// three in the list and the rest kept, not deleted.
struct VibescapesView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    /// False for the headless UI shots, which render the panel without a
    /// window. `ImageRenderer` can't lay out a scroll view — it gives the
    /// content no height and draws nothing — so the shots use a plain stack
    /// and get the whole panel.
    var scrollable: Bool = true

    /// The panel's height. Taller for the headless shots, which need the
    /// whole list rather than a scrollable window.
    var height: CGFloat = 560

    /// Which card to draw as the drop target, for the headless UI shots.
    var dropTargetIndex: Int?

    /// How many cards fit across.
    private let columnsPerRow = 3

    /// The editor, if it's open. The panel is itself a sheet, so it
    /// presents its own rather than asking the window to — two sheets on
    /// the same view can't both be up.
    @State private var editor: AppState.CustomVibescapeSheet?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            if scrollable {
                ScrollView { grid }
            } else {
                grid
            }
            Divider().overlay(Color.white.opacity(0.08))
            footer
        }
        .frame(width: 720, height: height)
        .background(Color(red: 0.05, green: 0.02, blue: 0.09))
        .sheet(item: $editor) { sheet in
            CustomVibescapeView(editing: sheet.mode)
                .environmentObject(app)
        }
        .onAppear {
            // Draw a picture of each of the user's own vibescapes, so the panel
            // shows what they look like.
            app.refreshCustomVibescapePreviews()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Vibescapes")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Switch off the ones you don't want in the list or in Auto Scan. Drag them to change the order.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            // Put the list back the way it shipped. Only worth offering
            // when it's actually been rearranged.
            if app.hasCustomOrder {
                Button("Reset Order") { app.resetVibescapeOrder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(white: 0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.08))
                    )
                    .pointingHand()
                    .help("Put the vibescapes back in their original order")
            }
            SheetCloseButton()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    /// The cards, dealt into rows.
    ///
    /// A plain layout rather than a lazy grid: a lazy grid doesn't lay
    /// itself out until there's a real scroll view to scroll, which left the
    /// panel blank in the headless UI shots.
    private var grid: some View {
        VStack(spacing: 14) {
            ForEach(rows, id: \.self) { row in
                VibescapeRow(entries: row, columns: columnsPerRow,
                        editor: $editor, dropTargetIndex: dropTargetIndex)
            }
        }
        .padding(18)
    }

    /// The vibescapes, dealt into rows, with a card for making a new one at the
    /// end.
    private var rows: [[VibescapeEntry]] {
        var all = app.allVibescapes
        all.append(VibescapeEntry(newVibescapeCard: true))
        return stride(from: 0, to: all.count, by: columnsPerRow).map {
            Array(all[$0..<min($0 + columnsPerRow, all.count)])
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .foregroundStyle(Color(white: 0.4))
            Text("Your own vibescapes are marked ★. Add another with the card at the end.")
                .font(.system(size: 10))
                .foregroundStyle(Color(white: 0.45))
            Spacer()
            Text("\(app.enabledVibescapes.count) of \(app.allVibescapes.count) switched on")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.5))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

/// One row of cards. Split out of the panel because the type-checker
/// struggles with the whole grid in one expression.
private struct VibescapeRow: View {
    @EnvironmentObject var app: AppState
    let entries: [VibescapeEntry]
    let columns: Int

    /// The editor, if it's open.
    @Binding var editor: AppState.CustomVibescapeSheet?

    /// The card a dragged vibescape is currently over, so it can say so.
    @State private var dropTargetID: VibescapeID?

    /// Which card to draw as the drop target, for the headless UI shots.
    var dropTargetIndex: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(entries) { entry in
                card(entry)
            }
            // Pad the last row so the cards stay the width of a full row
            // rather than stretching.
            if entries.count < columns {
                ForEach(0..<(columns - entries.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func card(_ entry: VibescapeEntry) -> some View {
        let base = VibescapeCard(entry: entry, onEdit: { target in
            guard let mode = app.customVibescape(id: target.id.slug) else { return }
            editor = .editing(mode)
        }, onCreate: {
            editor = .new
        }, onSelect: { target in
            if target.isNewVibescapeCard {
                editor = .new
                return
            }
            // Picking a vibescape that was switched off would leave it chosen
            // but missing from the list, so switch it back on.
            if !target.isEnabled {
                app.setVibescapeEnabled(target.id, enabled: true)
            }
            app.viaPicker = true
            app.activeVibescape = target.id
            app.showVibescapesSheet = false
        }, isDropTarget: isDropTarget(entry))
            .contentShape(Rectangle())
        if entry.isNewVibescapeCard {
            // The "make your own" card isn't a vibescape, so it isn't dragged
            // and nothing can be dropped onto it. Its placeholder id is
            // also another vibescape's, so letting a drop through would move
            // that vibescape instead.
            base
        } else {
            base
                .draggable(entry.id.rawValue) {
                    // A small chip, not a copy of the whole card. A card-sized
                    // drag image sits right on top of the card being aimed
                    // at, which hides the drop indicator completely.
                    DragChip(title: entry.title)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first,
                          let dragged = VibescapeID(rawValue: raw),
                          let index = app.allVibescapes.firstIndex(where: { $0.id == entry.id })
                    else { return false }
                    app.moveVibescape(dragged, to: index)
                    return true
                } isTargeted: { targeted in
                    // While something is being dragged over this card, the
                    // card says so — otherwise there's no sign of where the
                    // vibescape would land.
                    dropTargetID = targeted ? entry.id : (dropTargetID == entry.id ? nil : dropTargetID)
                }
        }
    }

    /// True for the card a dragged vibescape would land on.
    private func isDropTarget(_ entry: VibescapeEntry) -> Bool {
        if let dropTargetIndex,
           let index = app.allVibescapes.firstIndex(where: { $0.id == entry.id }),
           index == dropTargetIndex {
            return true
        }
        return dropTargetID == entry.id
    }
}

/// What follows the cursor while a vibescape is being dragged.
///
/// Deliberately small. A copy of the whole card would sit right on top of
/// the card being aimed at, hiding the drop indicator — and the drag image
/// is drawn by the system above everything the app draws.
private struct DragChip: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .bold))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.08, green: 0.04, blue: 0.14).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 1, green: 0.17, blue: 0.84), lineWidth: 1.5)
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
    }
}

/// One vibescape in the grid: a picture, its name, and a switch.
private struct VibescapeCard: View {
    @EnvironmentObject var app: AppState
    let entry: VibescapeEntry
    /// Called when the card's edit button is pressed.
    var onEdit: ((VibescapeEntry) -> Void)?
    /// Called when the card is pressed, for the "make your own" card.
    var onCreate: (() -> Void)?

    /// True while the pointer is over the card, so the author can be shown
    /// instead of taking up room all the time.
    @State private var isHovering = false

    /// Called when the picture is pressed: pick this vibescape.
    var onSelect: ((VibescapeEntry) -> Void)?
    /// True when a dragged vibescape is over this card, so it can show where
    /// the vibescape would land.
    var isDropTarget = false

    /// Set when the delete button is pressed, so the confirmation can ask.
    @State private var pendingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            preview
            HStack(spacing: 6) {
                if entry.isNewVibescapeCard {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 1, green: 0.17, blue: 0.84))
                } else if entry.isCustom {
                    // Only the user's own vibescapes are marked. The numbers that
                    // sit next to the names in the drop-down are keyboard
                    // shortcuts, and this panel isn't about keys.
                    Text("★")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.2))
                        .frame(width: 14, alignment: .leading)
                }
                Text(entry.title)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(entry.isEnabled ? Color.white : Color(white: 0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if entry.isCustom {
                    // Only the user's own vibescapes can be changed. The
                    // shipped ones are part of the app.
                    Button {
                        onEdit?(entry)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(white: 0.55))
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .help("Edit this vibescape")
                    Button {
                        pendingDelete = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.36))
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .help("Delete this vibescape")
                    .confirmationDialog(
                        "Delete “\(entry.title)”?",
                        isPresented: $pendingDelete,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            app.deleteCustomVibescape(id: entry.id.slug)
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The vibescape and its code are removed from this Mac. This can't be undone.")
                    }
                }
                if !entry.isNewVibescapeCard {
                    VibescapeSwitch(isOn: entry.isEnabled) {
                        app.setVibescapeEnabled(entry.id, enabled: !entry.isEnabled)
                    }
                }
            }


            // Who made it. Always shown, and clickable — the name and the
            // link both lead to the same place.
            HStack(spacing: 4) {
                if !entry.isNewVibescapeCard {
                    if let link = entry.link {
                        Link(destination: link) {
                            HStack(spacing: 4) {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 8))
                                Text(entry.author.isEmpty ? "Unknown" : entry.author)
                                    .font(.system(size: 9))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Color(white: 0.5))
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .help("Go to \(entry.author.isEmpty ? "the author's site" : entry.author)")
                        Link(destination: link) {
                            Image(systemName: "link")
                                .font(.system(size: 8))
                                .foregroundStyle(Color(white: 0.5))
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .help(link.absoluteString)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 8))
                            Text(entry.author.isEmpty ? "Unknown" : entry.author)
                                .font(.system(size: 9))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color(white: 0.5))
                    }
                }
            }
            .frame(height: 12, alignment: .leading)
            if let problem = app.customVibescapeProblems[entry.id.slug] {
                Label("Needs a fix", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.2))
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(entry.isEnabled ? 0.045 : 0.015))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(borderColour, lineWidth: isDropTarget ? 2 : 1)
                )
        )
        .overlay(alignment: .bottom) {
            // The drop zone. While a vibescape is being dragged over this card,
            // a bar appears along the bottom showing it would land here.
            if isDropTarget {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 1, green: 0.17, blue: 0.84))
                    .frame(height: 3)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 5)
                    .transition(.opacity)
            }
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(red: 1, green: 0.17, blue: 0.84).opacity(0.12))
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        // A native tooltip as well, for anyone who hovers and waits. It
        // carries the same two facts as the line that appears in the card.
        .help(tooltip)

    }

    /// The card's outline. Bright when it's the drop target, and the
    /// "make your own" card always stands out a little.
    private var borderColour: Color {
        if isDropTarget { return Color(red: 1, green: 0.17, blue: 0.84) }
        if entry.isNewVibescapeCard { return Color(red: 1, green: 0.17, blue: 0.84).opacity(0.45) }
        if entry.isEnabled { return Color(red: 1, green: 0.17, blue: 0.84).opacity(0.28) }
        return Color.white.opacity(0.06)
    }

    /// The author, and where to find more.
    private var tooltip: String {
        if entry.isNewVibescapeCard {
            return "Make a mode of your own"
        }
        var text = entry.author.isEmpty ? "Made by an unknown author" : "Made by \(entry.author)"
        if let url = entry.url, !url.isEmpty {
            text += "\n\(url)"
        }
        if entry.isCustom {
            text += "\nYour own mode — press the pencil to edit it."
        }
        return text
    }

    /// The picture. A user's own vibescape is drawn for real, so the panel shows
    /// what it looks like rather than a stand-in.
    ///
    /// Clicking it picks the vibescape: the panel closes and that vibescape is what
    /// gets drawn.
    @ViewBuilder
    private var preview: some View {
        Button {
            onSelect?(entry)
        } label: {
            if entry.isNewVibescapeCard {
                VStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Color(red: 1, green: 0.17, blue: 0.84))
                    Text("Make your own")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(white: 0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(red: 1, green: 0.17, blue: 0.84).opacity(0.08))
                )
                .frame(height: 96)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 5))
            } else if entry.isCustom {
                if let image = app.customVibescapePreviews[entry.id.slug] {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 96)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    // Nothing drawn yet — the picture is made the first time
                    // the panel opens.
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            ProgressView().controlSize(.small)
                        )
                        .frame(height: 96)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            } else if let image = VibescapePreviewImage.builtIn(entry.id) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 96)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                CustomVibescapeCover(name: entry.title, seed: entry.id.slug)
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .buttonStyle(.plain)
        .pointingHand()
        .help(entry.isNewVibescapeCard ? "Make a vibescape of your own" : "Switch to \(entry.title)")
    }
}

/// A hand-drawn on/off switch.
///
/// SwiftUI's own `Toggle` renders through an NSView that `ImageRenderer`
/// can't capture — it comes out as the "unsupported" placeholder — which is
/// the same reason the vibescape drop-down is hand-rolled. This one is drawn, so
/// it looks the same everywhere and can be reviewed in a screenshot.
struct VibescapeSwitch: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color(red: 1, green: 0.17, blue: 0.84).opacity(0.85)
                               : Color(white: 0.22))
                    .frame(width: 26, height: 15)
                Circle()
                    .fill(.white)
                    .frame(width: 11, height: 11)
                    .padding(.horizontal, 2)
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .help(isOn ? "Switch off" : "Switch on")
    }
}

/// Loads the vibescape pictures that ship with the app's website.
///
/// They're in the site folder rather than in the bundle because the app
/// doesn't ship them today. If they're not there — a build from source, or
/// a trimmed bundle — the card falls back to a generated cover rather than
/// showing a broken image.
enum VibescapePreviewImage {
    private static var cache: [String: NSImage] = [:]

    static func builtIn(_ id: VibescapeID) -> NSImage? {
        guard let builtin = id.builtin, builtin != .autoScan else { return nil }
        let key = builtin.rawValue
        if let cached = cache[key] { return cached }
        guard let image = load(builtin: builtin) else { return nil }
        cache[key] = image
        return image
    }

    private static func load(builtin: Vibescape) -> NSImage? {
        // The pictures live beside the site, and the app is usually run from
        // a build in the same checkout. Look in a few places rather than
        // insisting on one layout.
        let file = "modes/\(builtin.rawValue).jpg"
        var roots: [URL] = []
        if let override = ProcessInfo.processInfo.environment["VIBRESIA_PREVIEW_DIR"] {
            roots.append(URL(fileURLWithPath: override, isDirectory: true))
        }
        let here = URL(fileURLWithPath: Bundle.main.bundlePath)
        roots.append(here.appendingPathComponent("Resources"))
        roots.append(here.deletingLastPathComponent())
        // Up two levels from the built .app: <checkout>/VisualiserMac/build/Vibresia.app
        roots.append(here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("site/media"))
        for root in roots {
            let url = root.appendingPathComponent(file)
            if let image = NSImage(contentsOf: url) { return image }
        }
        return nil
    }
}

/// A generated cover for a vibescape with no picture: the user's own, or any
/// built-in whose picture couldn't be found.
///
/// It's drawn from the name, so the same vibescape always gets the same cover and
/// a wall of them looks like a set rather than a row of grey boxes.
struct CustomVibescapeCover: View {
    let name: String
    let seed: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.05, blue: 0.26), Color(red: 0.04, green: 0.02, blue: 0.08)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            // A few soft blobs, placed from the name so it's stable.
            ForEach(0..<3, id: \.self) { i in
                let h = hash(seed + String(i))
                Circle()
                    .fill(Color(hue: Double(h % 100) / 100.0,
                                saturation: 0.75,
                                brightness: 0.65)
                        .opacity(0.35))
                    .frame(width: 40 + CGFloat(h % 60), height: 40 + CGFloat(h % 50))
                    .blur(radius: 18)
                    .offset(x: CGFloat(Int(h % 100) - 50) / 3.0,
                            y: CGFloat(Int((h / 7) % 100) - 50) / 3.0)
            }
            Text(name.isEmpty ? "?" : String(name.prefix(2)).uppercased())
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private func hash(_ s: String) -> Int {
        var h = 5381
        for c in s.unicodeScalars { h = (h &* 33) &+ Int(c.value) }
        return abs(h)
    }
}
