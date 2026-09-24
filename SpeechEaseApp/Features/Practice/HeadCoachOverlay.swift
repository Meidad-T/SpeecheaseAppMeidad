import SwiftUI

/// Overlay shown in the top area of a recording screen, driven by
/// `HeadMovementCoach`. Displays a gentle "look around" prompt with a faint
/// Face-ID-style head turning left↔right, and a white checkmark when the
/// speaker responds.
struct HeadCoachOverlay: View {
    @ObservedObject var coach: HeadMovementCoach

    var body: some View {
        ZStack {
            switch coach.cue {
            case .reminder:
                VStack(spacing: 10) {
                    Text(coach.reminderText)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.7), radius: 3)

                    LookingFaceView()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

            case .looked:
                Image(systemName: "checkmark")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 4)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))

            case .idle:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: coach.cue)
        .allowsHitTesting(false)
    }
}

/// Faint Face-ID glyph that slowly rotates left↔right to mime "look around".
private struct LookingFaceView: View {
    @State private var turned = false

    var body: some View {
        Image(systemName: "faceid")
            .font(.system(size: 42))
            .foregroundStyle(.white.opacity(0.28))
            .rotation3DEffect(
                .degrees(turned ? 24 : -24),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.6
            )
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: turned)
            .onAppear { turned = true }
    }
}
