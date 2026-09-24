import SwiftUI

// Lens-focus reveal: fades in while scaling up from 90% and sharpening blur.
// Removal is the same in reverse — fades out while scaling down and blurring.
private struct CameraReveal: ViewModifier, Animatable {
    var amount: CGFloat  // 0 = hidden, 1 = visible

    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(Double(max(0, amount)))
            .blur(radius: 18 * (1 - max(0, amount)))
            .scaleEffect(0.88 + 0.12 * max(0, amount))
    }
}

private extension AnyTransition {
    static var cameraReveal: AnyTransition {
        .modifier(active: CameraReveal(amount: 0), identity: CameraReveal(amount: 1))
    }
}

// MARK: - LiveSessionView
struct LiveSessionView: View {
    @Environment(\.dismiss) var dismiss

    var timeLimitSeconds: Double? = nil
    var onFinish: (Result<URL, Error>) -> Void
    var onCancel: () -> Void

    @StateObject private var recorder = LiveAudioRecorder()
    @StateObject private var headCoach = HeadMovementCoach()
    @AppStorage("headCoachEnabled") private var headCoachEnabled = true
    @State private var isCameraEnabled = false
    @State private var isMicEnabled = true

    private var btnSize: CGFloat {
        let available = UIScreen.main.bounds.width - 40
        return min(72, (available - 24) / 4)
    }
    private var btnSpacing: CGFloat {
        let available = UIScreen.main.bounds.width - 40
        return max(8, (available - btnSize * 4) / 3)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Color.black

                if isCameraEnabled {
                    CameraPreview()
                        .transition(.cameraReveal)
                        .zIndex(1)
                }

                AnimatedGlowWaveView()
                    .allowsHitTesting(false)
                    .mask(
                        LinearGradient(
                            colors: [.black, .black, .black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .zIndex(2)

                VStack {
                    Text(formatTime(recorder.duration))
                        .font(.system(size: 36, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(timeLimitWarningColor)
                        .shadow(color: .black.opacity(0.8), radius: 2)
                        .padding(.top, 30)

                    if let limit = timeLimitSeconds, limit > 0 {
                        Text(formatTime(max(0, limit - recorder.duration)) + " left")
                            .font(.system(size: 16, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(timeLimitWarningColor.opacity(0.8))
                            .shadow(color: .black.opacity(0.6), radius: 2)
                    }

                    if headCoach.isActive {
                        Label("Head coach on", systemImage: "airpods.pro")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .shadow(color: .black.opacity(0.6), radius: 2)
                            .padding(.top, 4)
                            .transition(.opacity)
                    }

                    HeadCoachOverlay(coach: headCoach)
                        .padding(.top, 18)

                    Spacer()
                }
                .zIndex(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 40,
                    bottomTrailingRadius: 40,
                    topTrailingRadius: 0
                )
            )
            .overlay(alignment: .topTrailing) {
                airPodsToggleButton
            }

            HStack(spacing: btnSpacing) {
                Button {
                    onCancel()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 26, weight: .bold))
                        .frame(width: btnSize, height: btnSize)
                        .glassEffect()
                }

                Button {
                    withAnimation(isCameraEnabled
                        ? .easeIn(duration: 0.25)
                        : .spring(response: 0.48, dampingFraction: 0.78)
                    ) {
                        isCameraEnabled.toggle()
                    }
                } label: {
                    Image(systemName: isCameraEnabled ? "video.fill" : "video.slash.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .frame(width: btnSize, height: btnSize)
                        .glassEffect()
                        .contentTransition(.symbolEffect(.replace))
                }

                Button { isMicEnabled.toggle() } label: {
                    Image(systemName: isMicEnabled ? "mic.fill" : "mic.slash.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .frame(width: btnSize, height: btnSize)
                        .glassEffect()
                        .contentTransition(.symbolEffect(.replace))
                }

                Button { finishSession() } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .bold))
                        .frame(width: btnSize, height: btnSize)
                        .glassEffect(tint: .accentColor)
                }
            }
            .foregroundStyle(.white)
            .padding(.vertical, 20)
            .padding(.bottom, 10)
            .padding(.horizontal, 20)
        }
        .background {
            ZStack {
                Color.black.ignoresSafeArea()
                AnimatedGlowWaveView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .blur(radius: 100)
                    .scaleEffect(x: 1.5, y: 1.2)
                    .opacity(0.7)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            recorder.prepare()
            recorder.startRecording()
            if headCoachEnabled { headCoach.start() }
        }
        .onDisappear {
            _ = recorder.stopRecording()
            headCoach.stop()
        }
        .onChange(of: headCoachEnabled) { _, enabled in
            if enabled { headCoach.start() } else { headCoach.stop() }
        }
        .onChange(of: recorder.duration) { _, newDuration in
            if let limit = timeLimitSeconds, limit > 0, newDuration >= limit {
                finishSession()
            }
        }
    }

    func finishSession() {
        if let url = recorder.stopRecording() {
            onFinish(.success(url))
        }
    }

    // Top-right toggle to enable/disable the AirPods look-around coach.
    private var airPodsToggleButton: some View {
        Button {
            headCoachEnabled.toggle()
        } label: {
            ZStack {
                Image(systemName: "airpods.pro")
                    .font(.system(size: 20, weight: .semibold))
                if !headCoachEnabled {
                    Capsule()
                        .fill(.white)
                        .frame(width: 2.5, height: 30)
                        .rotationEffect(.degrees(45))
                        .shadow(color: .black.opacity(0.5), radius: 1)
                }
            }
            .foregroundStyle(.white.opacity(headCoachEnabled ? 1 : 0.55))
            .frame(width: 48, height: 48)
            .glassEffect()
        }
        .padding(.top, 16)
        .padding(.trailing, 16)
    }

    var timeLimitWarningColor: Color {
        guard let limit = timeLimitSeconds, limit > 0 else { return .white }
        let remaining = limit - recorder.duration
        if remaining <= 10 { return .red }
        if remaining <= 30 { return .orange }
        return .white
    }

    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension View {
    func glassEffect(tint: Color = .white.opacity(0.1)) -> some View {
        self
            .background {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                    Circle()
                        .fill(tint)
                }
            }
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.3), lineWidth: 1)
                    .blendMode(.overlay)
            )
            .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 5)
    }
}
