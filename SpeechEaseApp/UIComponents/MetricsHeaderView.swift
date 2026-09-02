//
//  MetricsHeaderView.swift
//  SpeechEaseApp
//

import SwiftUI

struct MetricsHeaderView: View {
    @ObservedObject var manager = LearningManager.shared
    var onRefillHearts: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Level — short label, star icon doesn't clash with background
            StatPill(icon: "star.fill", value: "\(currentSpeechLevel)", color: Color(red: 1.0, green: 0.88, blue: 0.2))

            Spacer()

            // Streak — white flame outline so it pops on the orange bg
            StatPill(icon: "flame.fill", value: "\(manager.streakCount)", color: .white)

            Spacer()

            // Gems
            StatPill(icon: "diamond.fill", value: "\(manager.gems)", color: Color(red: 0.45, green: 0.9, blue: 1.0))

            Spacer()

            // Hearts
            Button(action: onRefillHearts) {
                StatPill(icon: "heart.fill", value: "\(manager.hearts)", color: Color(red: 1.0, green: 0.35, blue: 0.55))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(height: 52)
    }

    private var currentSpeechLevel: Int {
        totalCrowns + 3
    }

    private var totalCrowns: Int {
        var count = 0
        for topic in TopicType.allCases {
            if manager.isTopicCompleted(for: topic) { count += 1 }
        }
        return count
    }
}

private struct StatPill: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.6), radius: 4, x: 0, y: 1)

            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(.white.opacity(0.15), in: Capsule())
    }
}

#Preview {
    ZStack {
        Color("AccentColor").ignoresSafeArea()
        MetricsHeaderView(onRefillHearts: {})
    }
}
