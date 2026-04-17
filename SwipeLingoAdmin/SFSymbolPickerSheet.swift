import SwiftUI

// MARK: - SFSymbolPickerSheet
//
// Picker для выбора SF Symbol иконки коллекции.
// Показывает курированный список символов с поиском по имени.

struct SFSymbolPickerSheet: View {

    @Environment(\.dismiss) private var dismiss

    let onSelect: (String) -> Void

    @State private var query: String = ""

    // MARK: Symbol catalog

    private static let allSymbols: [(category: String, symbols: [String])] = [
        ("Education", [
            "book", "book.fill", "books.vertical", "books.vertical.fill",
            "graduationcap", "graduationcap.fill", "pencil", "pencil.line",
            "doc.text", "doc.text.fill", "note.text", "newspaper",
            "newspaper.fill", "text.book.closed", "text.book.closed.fill",
            "abc", "textformat", "character.book.closed", "list.bullet",
            "list.number", "checkmark.circle", "checkmark.circle.fill"
        ]),
        ("Language & Speech", [
            "bubble.left", "bubble.left.fill", "bubble.right", "bubble.right.fill",
            "bubble.left.and.bubble.right", "quote.bubble", "quote.bubble.fill",
            "megaphone", "megaphone.fill", "mic", "mic.fill",
            "speaker.wave.2", "speaker.wave.2.fill", "waveform",
            "character", "textformat.abc", "globe", "globe.americas",
            "globe.europe.africa", "globe.asia.australia"
        ]),
        ("People & Social", [
            "person", "person.fill", "person.2", "person.2.fill",
            "person.3", "person.3.fill", "figure.stand", "figure.walk",
            "brain", "brain.head.profile", "hand.raised", "hand.raised.fill",
            "hand.thumbsup", "hand.thumbsup.fill", "hands.clap", "hands.clap.fill"
        ]),
        ("Nature", [
            "leaf", "leaf.fill", "tree", "tree.fill",
            "sun.max", "sun.max.fill", "moon", "moon.fill",
            "cloud", "cloud.fill", "flame", "flame.fill",
            "drop", "drop.fill", "snowflake", "wind",
            "mountain.2", "mountain.2.fill", "water.waves"
        ]),
        ("Objects & Places", [
            "house", "house.fill", "building.2", "building.2.fill",
            "building.columns", "building.columns.fill",
            "fork.knife", "cup.and.saucer", "cup.and.saucer.fill",
            "car", "car.fill", "airplane", "tram", "ferry", "bicycle",
            "cart", "cart.fill", "bag", "bag.fill",
            "suitcase", "suitcase.fill", "briefcase", "briefcase.fill",
            "camera", "camera.fill", "photo", "photo.fill",
            "film", "film.fill", "music.note", "music.quarternote.3",
            "theatermasks", "theatermasks.fill", "sportscourt", "sportscourt.fill",
            "dumbbell", "dumbbell.fill", "trophy", "trophy.fill",
            "medal", "medal.fill", "crown", "crown.fill"
        ]),
        ("Business & Finance", [
            "chart.bar", "chart.bar.fill", "chart.line.uptrend.xyaxis",
            "dollarsign.circle", "dollarsign.circle.fill",
            "creditcard", "creditcard.fill", "banknote", "banknote.fill",
            "tag", "tag.fill", "bookmark", "bookmark.fill",
            "bell", "bell.fill", "flag", "flag.fill",
            "star", "star.fill", "heart", "heart.fill",
            "map", "map.fill", "location", "location.fill"
        ]),
        ("Technology", [
            "laptopcomputer", "desktopcomputer", "iphone",
            "server.rack", "cpu", "memorychip", "wifi",
            "antenna.radiowaves.left.and.right", "network",
            "lock", "lock.fill", "key", "key.fill",
            "gear", "gearshape", "gearshape.fill",
            "wrench.and.screwdriver", "wrench.and.screwdriver.fill",
            "hammer", "hammer.fill", "lightbulb", "lightbulb.fill"
        ]),
        ("Symbols & Shapes", [
            "circle", "circle.fill", "square", "square.fill",
            "triangle", "triangle.fill", "diamond", "diamond.fill",
            "hexagon", "hexagon.fill", "seal", "seal.fill",
            "plus.circle", "plus.circle.fill", "minus.circle",
            "xmark.circle", "checkmark.circle", "checkmark.circle.fill",
            "exclamationmark.circle", "questionmark.circle",
            "info.circle", "info.circle.fill",
            "arrow.right.circle", "arrow.right.circle.fill"
        ])
    ]

    private var filteredSymbols: [(category: String, symbols: [String])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Self.allSymbols }
        let flat = Self.allSymbols.flatMap(\.symbols).filter { $0.contains(q) }
        return flat.isEmpty ? [] : [("Results", flat)]
    }

    private let columns = Array(repeating: GridItem(.fixed(44), spacing: 8), count: 8)

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            // ── Search bar ────────────────────────────────
            HStack(spacing: 0) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
                TextField("Search symbols…", text: $query)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(alignment: .bottom) { Divider() }

            // ── Grid ──────────────────────────────────────
            if filteredSymbols.isEmpty {
                Spacer()
                Text("No symbols found")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(filteredSymbols, id: \.category) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.category)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)

                                LazyVGrid(columns: columns, spacing: 8) {
                                    ForEach(group.symbols, id: \.self) { name in
                                        SymbolCell(name: name) {
                                            onSelect(name)
                                            dismiss()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 460)
        .navigationTitle("Choose Symbol")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

// MARK: - SymbolCell

private struct SymbolCell: View {
    let name:   String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 20))
                .frame(width: 44, height: 44)
                .background(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(name)
        .onHover { isHovered = $0 }
    }
}
