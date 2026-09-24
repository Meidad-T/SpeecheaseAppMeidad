import SwiftUI

struct AnimatedGlowWaveView: View {
    private let waves: [WaveConfig] = [
        WaveConfig(
            color: Color(red: 1.0, green: 1.0, blue: 0.0),
            horizontalSpeed: 16,
            baseAmplitude: 100,
            amplitudeRange: 35,
            baseBaselineOffset: -20,
            baselineRange: 40,
            intervalMultiplier: 1.0
        ),
        WaveConfig(
            color: Color(red: 1.0, green: 0.6, blue: 0.3),
            horizontalSpeed: 10,
            baseAmplitude: 140,
            amplitudeRange: 50,
            baseBaselineOffset: -10,
            baselineRange: 30,
            intervalMultiplier: 0.7
        ),
        WaveConfig(
            color: Color(red: 1.0, green: 0.45, blue: 0.1),
            horizontalSpeed: 6,
            baseAmplitude: 90,
            amplitudeRange: 30,
            baseBaselineOffset: 25,
            baselineRange: 20,
            intervalMultiplier: 0.4
        )
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.5, blue: 0.0).opacity(0.3),
                        Color.clear
                    ],
                    startPoint: .bottom,
                    endPoint: .center
                )
                .ignoresSafeArea()

                ForEach(0..<waves.count, id: \.self) { index in
                    SingleWaveView(
                        config: waves[index],
                        screenSize: geo.size
                    )
                }
            }
            .drawingGroup()
            .clipped()
        }
    }
}

struct WaveConfig {
    let color: Color
    let horizontalSpeed: Double
    let baseAmplitude: CGFloat
    let amplitudeRange: CGFloat
    let baseBaselineOffset: CGFloat
    let baselineRange: CGFloat
    let intervalMultiplier: CGFloat
}

struct SingleWaveView: View {
    let config: WaveConfig
    let screenSize: CGSize

    @State private var offset: CGFloat = 0
    @State private var currentAmplitude: CGFloat
    @State private var currentBaselineOffset: CGFloat

    init(config: WaveConfig, screenSize: CGSize) {
        self.config = config
        self.screenSize = screenSize
        _currentAmplitude = State(initialValue: config.baseAmplitude)
        _currentBaselineOffset = State(initialValue: config.baseBaselineOffset)
    }

    var body: some View {
        let interval = screenSize.width * config.intervalMultiplier
        let baseline = screenSize.height * 0.85

        let waveShape = SineWaveShape(
            interval: interval,
            amplitude: currentAmplitude,
            baseline: baseline + currentBaselineOffset
        )

        ZStack {
            waveShape
                .fill(
                    LinearGradient(
                        colors: [config.color.opacity(0.5), .clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .blur(radius: 60)
                .offset(y: -50)

            waveShape
                .fill(
                    LinearGradient(
                        colors: [config.color.opacity(0.8), config.color.opacity(0.0)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .blur(radius: 10)
                .overlay(
                    waveShape
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.6), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 3
                        )
                        .blur(radius: 5)
                )
        }
        .offset(x: offset)
        .onAppear {
            withAnimation(
                .linear(duration: config.horizontalSpeed)
                .repeatForever(autoreverses: false)
            ) {
                offset = -interval
            }
            randomizeWaveMotion()
        }
    }

    private func randomizeWaveMotion() {
        let randomDuration = Double.random(in: 2.5...5.0)

        let newAmplitude = config.baseAmplitude + CGFloat.random(in: -config.amplitudeRange...config.amplitudeRange)
        let newBaselineOffset = config.baseBaselineOffset + CGFloat.random(in: -config.baselineRange...config.baselineRange)

        withAnimation(.easeInOut(duration: randomDuration)) {
            currentAmplitude = newAmplitude
            currentBaselineOffset = newBaselineOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + randomDuration * 0.9) {
            randomizeWaveMotion()
        }
    }
}

struct SineWaveShape: Shape {
    var interval: CGFloat
    var amplitude: CGFloat
    var baseline: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(amplitude, baseline) }
        set {
            amplitude = newValue.first
            baseline = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: baseline))

        for i in 0...3 {
            drawWaveCycle(to: &path, startX: interval * CGFloat(i))
        }

        path.addLine(to: CGPoint(x: interval * 4, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }

    private func drawWaveCycle(to path: inout Path, startX: CGFloat) {
        let endX = startX + interval
        let cp1 = CGPoint(x: startX + (interval * 0.35), y: baseline - amplitude)
        let cp2 = CGPoint(x: startX + (interval * 0.65), y: baseline + amplitude)
        path.addCurve(to: CGPoint(x: endX, y: baseline), control1: cp1, control2: cp2)
    }
}
