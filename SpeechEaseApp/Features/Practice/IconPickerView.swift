import SwiftUI

struct IconPickerView: View {
    @Binding var selectedIcon: String?
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""

    private let categories: [(String, [String])] = [
        ("Speech & Voice", [
            "mic.fill", "mic.circle.fill", "mic.badge.plus",
            "waveform", "waveform.circle.fill", "waveform.badge.mic",
            "speaker.wave.3.fill", "speaker.wave.2.circle.fill",
            "bubble.left.fill", "bubble.right.fill", "bubble.left.and.bubble.right.fill",
            "quote.opening", "quote.closing",
            "text.bubble.fill", "message.fill",
            "megaphone.fill", "music.note", "music.microphone",
            "ear.fill", "ear.badge.checkmark",
            "waveform.and.mic"
        ]),
        ("Body & Movement", [
            "figure.stand", "figure.walk", "figure.run",
            "figure.arms.open", "figure.mind.and.body",
            "figure.cooldown", "figure.strengthtraining.traditional",
            "figure.yoga", "figure.dance", "figure.play",
            "hand.raised.fill", "hand.thumbsup.fill", "hand.thumbsdown.fill",
            "hands.clap.fill", "hands.sparkles.fill",
            "eye.fill", "eyes.inverse", "mouth.fill",
            "brain.head.profile", "person.fill",
            "person.bust.fill", "person.crop.circle.fill"
        ]),
        ("Goals & Achievement", [
            "target", "scope", "star.fill", "star.circle.fill",
            "bolt.fill", "bolt.circle.fill",
            "flame.fill", "flame.circle.fill",
            "trophy.fill", "medal.fill", "rosette",
            "checkmark.seal.fill", "checkmark.circle.fill",
            "crown.fill", "graduationcap.fill",
            "lightbulb.fill", "lightbulb.max.fill",
            "flag.fill", "flag.checkered",
            "flag.checkered.2.crossed",
            "chart.line.uptrend.xyaxis.circle.fill",
            "arrow.up.circle.fill"
        ]),
        ("Time & Training", [
            "timer", "timer.circle.fill", "stopwatch.fill",
            "clock.fill", "clock.badge.fill", "alarm.fill",
            "hourglass", "hourglass.tophalf.filled",
            "calendar", "calendar.badge.plus",
            "chart.line.uptrend.xyaxis", "chart.bar.fill",
            "chart.pie.fill", "chart.xyaxis.line",
            "speedometer", "gauge.with.dots.needle.67percent",
            "repeat.circle.fill", "arrow.clockwise.circle.fill"
        ]),
        ("Work & Interview", [
            "briefcase.fill", "briefcase.circle.fill",
            "person.2.fill", "person.3.fill",
            "building.2.fill", "building.columns.fill",
            "network", "globe.desk.fill",
            "laptopcomputer", "desktopcomputer",
            "doc.text.fill", "doc.richtext.fill",
            "pencil.and.list.clipboard", "list.bullet.clipboard.fill",
            "checklist", "questionmark.bubble.fill",
            "checkmark.bubble.fill", "phone.fill",
            "video.fill", "shareplay"
        ]),
        ("Focus & Mindset", [
            "brain", "brain.filled.head.profile",
            "theatermasks.fill", "theatermask.and.paintbrush.fill",
            "person.fill.viewfinder",
            "eye.circle.fill", "binoculars.fill",
            "magnifyingglass.circle.fill",
            "hexagonpath.fill", "staroflife.fill",
            "infinity.circle.fill", "circle.hexagongrid.fill",
            "wind", "tornado", "hurricane",
            "dot.radiowaves.left.and.right",
            "antenna.radiowaves.left.and.right",
            "wifi", "wave.3.right"
        ]),
        ("Nature & Energy", [
            "sun.max.fill", "sun.and.horizon.fill",
            "moon.fill", "moon.stars.fill",
            "cloud.bolt.fill", "cloud.sun.fill",
            "snowflake", "snowflake.circle.fill",
            "leaf.fill", "tree.fill",
            "drop.fill", "drop.circle.fill",
            "flame", "sparkles", "sparkle",
            "rays", "aqi.medium",
            "bolt.heart.fill", "sun.horizon.fill"
        ]),
        ("Shapes & Symbols", [
            "circle.fill", "square.fill", "triangle.fill",
            "diamond.fill", "hexagon.fill", "octagon.fill",
            "seal.fill", "shield.fill", "heart.fill",
            "suit.club.fill", "suit.spade.fill",
            "cross.fill", "plus.circle.fill",
            "xmark.circle.fill", "exclamationmark.circle.fill",
            "questionmark.circle.fill",
            "infinity", "atom",
            "square.on.circle.fill", "circle.grid.cross.fill"
        ]),
        ("Tech & Media", [
            "play.circle.fill", "pause.circle.fill",
            "record.circle.fill", "recordingtape",
            "camera.fill", "camera.circle.fill",
            "tv.fill", "airplayvideo",
            "headphones", "headphones.circle.fill",
            "earbuds", "homepodmini.fill",
            "cpu.fill", "memorychip.fill",
            "iphone", "applewatch",
            "keyboard.fill", "computermouse.fill"
        ]),
        ("People & Social", [
            "person.wave.2.fill", "person.2.wave.2.fill",
            "person.crop.circle.badge.checkmark",
            "person.badge.plus", "person.2.badge.gearshape",
            "hands.and.sparkles.fill",
            "peacesign", "hand.point.up.left.fill",
            "hand.point.right.fill",
            "face.smiling.inverse", "face.dashed",
            "bubble.left.and.exclamationmark.bubble.right.fill",
            "rectangle.3.group.bubble.fill",
            "person.fill.and.arrow.left.and.arrow.right",
            "shared.with.you.circle.fill"
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
