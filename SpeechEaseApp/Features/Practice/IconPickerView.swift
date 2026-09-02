import SwiftUI

struct IconPickerView: View {
    @Binding var selectedIcon: String?
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""

    private let categories: [(String, [String])] = [
        ("Speech & Voice", [
            "mic.fill", "mic.circle.fill", "waveform", "waveform.circle.fill",
            "speaker.wave.3.fill", "bubble.left.fill", "bubble.right.fill",
            "quote.opening", "text.bubble.fill", "megaphone.fill",
            "music.note", "music.microphone"
        ]),
        ("Body & Movement", [
            "figure.stand", "figure.walk", "figure.arms.open",
            "figure.mind.and.body", "figure.cooldown", "hand.raised.fill",
            "hand.thumbsup.fill", "hands.clap.fill", "eye.fill",
            "mouth.fill", "brain.head.profile", "person.fill"
        ]),
        ("Goals & Focus", [
            "target", "scope", "star.fill", "bolt.fill",
            "flame.fill", "trophy.fill", "medal.fill", "rosette",
            "checkmark.seal.fill", "crown.fill", "graduationcap.fill",
            "lightbulb.fill"
        ]),
        ("Time & Training", [
            "timer", "stopwatch.fill", "clock.fill", "alarm.fill",
            "hourglass", "calendar", "chart.line.uptrend.xyaxis",
            "chart.bar.fill", "speedometer", "gauge.with.dots.needle.67percent"
        ]),
        ("Work & Interview", [
            "briefcase.fill", "person.2.fill", "building.2.fill",
            "network", "laptopcomputer", "desktopcomputer",
            "doc.text.fill", "pencil.and.list.clipboard", "list.bullet.clipboard.fill",
            "questionmark.bubble.fill", "checkmark.bubble.fill"
        ]),
        ("Nature & Energy", [
            "sun.max.fill", "moon.fill", "cloud.bolt.fill", "wind",
            "leaf.fill", "drop.fill", "flame", "snowflake",
            "sparkles", "rays", "antenna.radiowaves.left.and.right"
        ]),
        ("Shapes & Icons", [
            "circle.fill", "square.fill", "triangle.fill", "diamond.fill",
            "hexagon.fill", "seal.fill", "shield.fill", "heart.fill",
            "suit.club.fill", "suit.spade.fill", "infinity.circle.fill"
        ])
    ]

    private var filteredCategories: [(String, [String])] {
        guard !searchText.isEmpty else { return categories }
        let q = searchText.lowercased()
        var result: [(String, [String])] = []
        for (title, symbols) in categories {
            let filtered = symbols.filter { $0.lowercased().contains(q) }
            if !filtered.isEmpty { result.append((title, filtered)) }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    resetRow
                    categoryGrids
                }
                .padding(.vertical)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search icons")
        }
    }

    private var resetRow: some View {
        Button {
            selectedIcon = nil
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                Text("Use default icon")
                    .foregroundStyle(.primary)
                Spacer()
                if selectedIcon == nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(14)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var categoryGrids: some View {
        if filteredCategories.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No icons found")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else {
            ForEach(filteredCategories, id: \.0) { (title, symbols) in
                IconCategorySection(
                    title: title,
                    symbols: symbols,
                    selectedIcon: $selectedIcon,
                    onSelect: { dismiss() }
                )
            }
        }
    }
}

private struct IconCategorySection: View {
    let title: String
    let symbols: [String]
    @Binding var selectedIcon: String?
    let onSelect: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 52), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(symbols, id: \.self) { symbol in
                    IconCell(symbol: symbol, isSelected: selectedIcon == symbol) {
                        selectedIcon = symbol
                        onSelect()
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct IconCell: View {
    let symbol: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor : Color(UIColor.secondarySystemGroupedBackground))
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .frame(width: 52, height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .scaleEffect(isSelected ? 1.1 : 1.0)
            .animation(.spring(response: 0.25), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}
