import SwiftUI
import AVFoundation

struct CameraRecordingSheet: View {
    @Environment(\.dismiss) var dismiss
    var onFinish: (Result<URL, Error>) -> Void

    @StateObject private var cameraManager = CameraRecordingManager()
    @StateObject private var headCoach = HeadMovementCoach()
    @AppStorage("headCoachEnabled") private var headCoachEnabled = true

    var externalAnalysisStatus: Binding<String>? = nil
    var timeLimitSeconds: Double? = nil

    init(externalAnalysisStatus: Binding<String>? = nil, timeLimitSeconds: Double? = nil, onFinish: @escaping (Result<URL, Error>) -> Void) {
        self.externalAnalysisStatus = externalAnalysisStatus
        self.timeLimitSeconds = timeLimitSeconds
        self.onFinish = onFinish
    }
    
    @State private var showSettings = false
    
    enum SettingsPage {
        case main
        case motion
        case themes
        case audio
    }
    @State private var currentSettingsPage: SettingsPage = .main
    
    enum CountdownOption: Int, CaseIterable {
        case off = 0
        case three = 3
        case five = 5
        case ten = 10
        case twenty = 20
        
        var display: String {
            switch self {
            case .off: return "Off"
            default: return "\(self.rawValue)s"
            }
        }
    }
    @State private var countdownDuration: CountdownOption = .off
    @State private var isCountingDown = false
    @State private var showTimerSelection = false
    @State private var countdownValue = 0
    @State private var countdownTask: Task<Void, Never>?
    @State private var isAnalyzing = false
    @State private var pendingAutoFinish = false
    
    @State private var deviceOrientation: UIDeviceOrientation = .portrait

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                
                let isUpsideDown = deviceOrientation == .portraitUpsideDown
                let isLandscape = geo.size.width > geo.size.height
                
                if isLandscape || isUpsideDown {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        
                        VStack(spacing: 30) {
                            Image(systemName: isUpsideDown ? "iphone.gen3" : "iphone.gen3.turn.right")
                                .font(.system(size: 100))
                                .foregroundStyle(.white)
                                .symbolEffect(.bounce, options: .repeating)
                            
                            Text(isUpsideDown ? "UPSIDE DOWN" : "PORTRAIT MODE ONLY")
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            
                            Text(isUpsideDown ? "Please turn your device right side up." : "The Camera Lesson requires Portrait mode\nfor accurate body language analysis.")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                
                            Button {
                                dismiss()
                            } label: {
                                Text("Cancel")
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 40)
                                    .padding(.vertical, 15)
                                    .background(.white.opacity(0.2), in: Capsule())
                            }
                            .padding(.top, 20)
                        }
                    }
                    .transition(.opacity)
                } else {
                    VStack {
                        ZStack {
                            if cameraManager.isRecording {
                                Text(formattedDuration)
                                    .font(.system(size: 40, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                            }
                            
                            HStack {
                                if !cameraManager.isRecording {
                                    Button {
                                        dismiss()
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.title2)
                                            .foregroundStyle(.primary)
                                            .padding(10)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Circle())
                                    }
                                } else {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 12, height: 12)
                                }
                                
                                Spacer()
                                
                                Button {
                                    withAnimation {
                                        showSettings.toggle()
                                        currentSettingsPage = .main
                                    }
                                } label: {
                                    Image(systemName: "gearshape.fill")
                                        .font(.title2)
                                        .foregroundStyle(.primary)
                                        .padding(10)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                        .shadow(radius: 2)
                                }
                                .disabled(cameraManager.isRecording)
                                .opacity(cameraManager.isRecording ? 0 : 1)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 20)
                        
                        ZStack(alignment: .topTrailing) {
                            CameraViewWrapper(manager: cameraManager)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                            
                            if isAnalyzing {
                                ZStack {
                                    Color.black.opacity(0.3)
                                    
                                    AnalysisGradientOverlay()
                                        .opacity(0.85)
                                    
                                    VStack(spacing: 12) {
                                        LottieView(filename: "video-processing")
                                            .frame(width: 375, height: 375)
                                            .offset(y: 20) 

                                        if let statusBinding = externalAnalysisStatus {
                                            AnimatedProcessingText(text: statusBinding.wrappedValue)
                                                .transition(.opacity)
                                                .id("statusText")
                                                .padding(.bottom, 60)
                                        }
                                    }
                                    .offset(y: -20)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                                .transition(.opacity)
                                .zIndex(50)
                            }
                            
                            if isCountingDown {
                                Text("\(countdownValue)")
                                    .font(.system(size: 150, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                    .transition(.scale.combined(with: .opacity))
                            }
                            
                            if showTimerSelection {
                                Color.black.opacity(0.001)
                                    .onTapGesture { withAnimation { showTimerSelection = false } }
                            }
                            
                            if showSettings {
                                ZStack(alignment: .topTrailing) {
                                    Color.black.opacity(0.001).ignoresSafeArea()
                                        .onTapGesture { withAnimation { showSettings = false; currentSettingsPage = .main } }
                                    settingsMenu.transition(.scale.combined(with: .opacity))
                                }
                                .zIndex(100)
                            }
                        }
                        .frame(maxHeight: .infinity)
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                        .overlay(alignment: .top) {
                            HeadCoachOverlay(coach: headCoach)
                                .padding(.top, 28)
                        }
                        
                        VStack(spacing: 20) {
                            if let recordedURL = cameraManager.recordedVideoURL, !cameraManager.isRecording {
                                HStack(spacing: 20) {
                                    Button {
                                        cameraManager.reset()
                                    } label: {
                                        Image(systemName: "arrow.counterclockwise")
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                            .frame(width: 56, height: 56)
                                            .background(Color.gray)
                                            .clipShape(Circle())
                                            .shadow(radius: 4)
                                    }
                                    
                                    if isAnalyzing {
                                         ProgressView()
                                            .tint(.primary)
                                            .frame(maxWidth: .infinity)
                                    } else {
                                        SlideToFinishButton(text: "Slide to Finish") {
                                            withAnimation {
                                                isAnalyzing = true
                                            }
                                            
                                            if externalAnalysisStatus != nil {
                                                onFinish(.success(recordedURL))
                                            } else {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                                    onFinish(.success(recordedURL))
                                                    dismiss()
                                                }
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                                .padding(.horizontal, 40)
                                .padding(.bottom, 30)
                            } else {
                                HStack(spacing: 30) {
                                    if !cameraManager.isRecording && !isCountingDown {
                                        Button {
                                            withAnimation { showTimerSelection.toggle() }
                                        } label: {
                                            VStack(spacing: 2) {
                                                Image(systemName: "timer").font(.title2)
                                                Text(countdownDuration == .off ? "Off" : "\(countdownDuration.rawValue)s")
                                                    .font(.caption).fontWeight(.bold)
                                            }
                                            .foregroundStyle(.white)
                                            .frame(width: 50, height: 50)
                                            .background(Color.black.opacity(0.3))
                                            .clipShape(Circle())
                                        }
                                        .overlay(alignment: .bottom) {
                                            if showTimerSelection {
                                                timerSelectionMenu
                                                    .offset(y: -60)
                                                    .transition(.scale.combined(with: .opacity).animation(.spring(duration: 0.3)))
                                            }
                                        }
                                        .zIndex(100)
                                        .transition(.scale.combined(with: .opacity))
                                    }
                                    
                                    Button {
                                        if cameraManager.isRecording {
                                            cameraManager.stopRecordingTrigger = true
                                        } else if isCountingDown {
                                            cancelCountdown()
                                        } else {
                                            startRecordingSequence()
                                        }
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .stroke(Color.primary.opacity(0.2), lineWidth: 4)
                                                .frame(width: 80, height: 80)
                                            
                                            RoundedRectangle(cornerRadius: cameraManager.isRecording || isCountingDown ? 8 : 40)
                                                .fill(Color.red)
                                                .frame(width: cameraManager.isRecording || isCountingDown ? 32 : 64, height: cameraManager.isRecording || isCountingDown ? 32 : 64)
                                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: cameraManager.isRecording || isCountingDown)
                                        }
                                    }
                                    
                                    if !cameraManager.isRecording && !isCountingDown {
                                        Spacer().frame(width: 50)
                                    }
                                }
                                .padding(.bottom, 30)
                            }
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                deviceOrientation = UIDevice.current.orientation
            }
            .onAppear {
                deviceOrientation = UIDevice.current.orientation
            }
            .onChange(of: cameraManager.recordingDuration) { _, newDuration in
                if let limit = timeLimitSeconds, limit > 0, cameraManager.isRecording, newDuration >= limit {
                    cameraManager.stopRecordingTrigger = true
                    pendingAutoFinish = true
                }
            }
            .onChange(of: cameraManager.recordedVideoURL) { _, url in
                guard pendingAutoFinish, let url = url else { return }
                pendingAutoFinish = false
                withAnimation { isAnalyzing = true }
                if externalAnalysisStatus != nil {
                    onFinish(.success(url))
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        onFinish(.success(url))
                        dismiss()
                    }
                }
            }
            .onChange(of: cameraManager.isRecording) { _, recording in
                if recording && headCoachEnabled {
                    headCoach.start()
                } else {
                    headCoach.stop()
                }
            }
            .onChange(of: headCoachEnabled) { _, enabled in
                if enabled && cameraManager.isRecording {
                    headCoach.start()
                } else if !enabled {
                    headCoach.stop()
                }
            }
            .onDisappear {
                headCoach.stop()
            }
        }
    }
    
    private var formattedDuration: String {
        let duration = Int(cameraManager.recordingDuration)
        let minutes = duration / 60
        let seconds = duration % 60
        let elapsed = String(format: "%02d:%02d", minutes, seconds)
        if let limit = timeLimitSeconds, limit > 0 {
            let remaining = max(0, Int(limit) - duration)
            let rm = remaining / 60, rs = remaining % 60
            return "\(elapsed) / \(String(format: "%02d:%02d", rm, rs))"
        }
        return elapsed
    }
    
    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        withAnimation {
            isCountingDown = false
        }
    }
    
    private func startRecordingSequence() {
        if countdownDuration == .off {
            cameraManager.startRecordingTrigger = true
        } else {
            countdownValue = countdownDuration.rawValue
            isCountingDown = true
            
            countdownTask?.cancel()
            countdownTask = Task { @MainActor in
                while countdownValue > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { return }
                    
                    if countdownValue > 1 {
                        withAnimation {
                            countdownValue -= 1
                        }
                    } else {
                        withAnimation {
                            isCountingDown = false
                        }
                        cameraManager.startRecordingTrigger = true
                        return
                    }
                }
            }
        }
    }
    
    var timerSelectionMenu: some View {
        VStack(spacing: 0) {
            ForEach(CountdownOption.allCases, id: \.self) { option in
                Button {
                    withAnimation {
                        countdownDuration = option
                        showTimerSelection = false
                    }
                } label: {
                    HStack {
                        Text(option.display)
                            .fontWeight(countdownDuration == option ? .bold : .regular)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        if countdownDuration == option {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding()
                    .background(Color.primary.opacity(0.05))
                }
                
                if option != CountdownOption.allCases.last {
                    Divider()
                }
            }
        }
        .frame(width: 150)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
    }
    
    var settingsMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            if currentSettingsPage != .main {
                Button {
                    withAnimation {
                        if currentSettingsPage == .themes {
                            currentSettingsPage = .motion
                        } else {
                            currentSettingsPage = .main
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                }
                .padding(.bottom, 10)
            } else {
                Text("Settings")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(.bottom, 10)
            }
            
            Divider().padding(.bottom, 10)
            
            switch currentSettingsPage {
            case .main:
                VStack(spacing: 8) {
                    settingsRow(title: "Motion Visualizers", icon: "hand.raised.fill", color: .purple) {
                        currentSettingsPage = .motion
                    }

                    settingsRow(title: "Audio", icon: "mic.fill", color: .blue) {
                        currentSettingsPage = .audio
                    }

                    Divider().padding(.vertical, 2)

                    Toggle(isOn: $headCoachEnabled) {
                        HStack {
                            Image(systemName: "airpods.pro")
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.teal)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            Text("Look-Around Coach")
                                .foregroundStyle(.primary)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                    .tint(Color("AccentColor"))
                }
                
            case .motion:
                VStack(alignment: .leading, spacing: 16) {
                    Text("Motion Visualizers")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Hand Lines", isOn: $cameraManager.showHandLines)
                            .tint(Color("AccentColor"))
                        Toggle("Body Lines", isOn: $cameraManager.showBodyLines)
                            .tint(Color("AccentColor"))
                        Toggle("Face Lines", isOn: $cameraManager.showFaceLines)
                            .tint(Color("AccentColor"))
                    }
                    
                    Divider()
                    
                    settingsRow(title: "Color Themes", icon: "paintpalette.fill", color: .pink) {
                        currentSettingsPage = .themes
                    }
                }
                
            case .themes:
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose Theme")
                        .font(.headline)
                    
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(CameraRecordingManager.CameraTheme.themes) { theme in
                                Button {
                                    withAnimation {
                                        cameraManager.applyTheme(theme)
                                    }
                                } label: {
                                    HStack(spacing: 0) {
                                        Rectangle().fill(theme.hand)
                                        Rectangle().fill(theme.body)
                                        Rectangle().fill(theme.face)
                                    }
                                    .frame(height: 40)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 300)
                }
                
            case .audio:
                VStack(alignment: .leading, spacing: 12) {
                    Text("Audio Input")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    Toggle("Enable Mic", isOn: $cameraManager.isAudioEnabled)
                        .tint(Color("AccentColor"))
                    
                    Text("Disabling the mic will result in no speech transcript analysis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(24)
        .frame(width: 320)
        .padding(16)
        .shadow(radius: 10)
    }
    
    func settingsRow(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation { action() } }) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
                Text(title)
                    .foregroundStyle(.primary)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SlideToFinishButton: View {
    var text: String
    var action: () -> Void

    @State private var offset: CGFloat = 0
    private let height: CGFloat = 60

    var body: some View {
        GeometryReader { geo in
            let maxDrag = geo.size.width - height

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))

                Text(text)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity)
                    .opacity(offset > 10 ? 0 : 1)
                    .animation(.easeOut, value: offset)

                ZStack {
                    Circle()
                        .fill(Color.white)
                        .shadow(radius: 2)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.black)
                }
                .frame(width: height - 8, height: height - 8)
                .padding(.leading, 4)
                .offset(x: offset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.width > 0 {
                                offset = min(max(0, value.translation.width), maxDrag)
                            }
                        }
                        .onEnded { value in
                            if offset > (maxDrag * 0.8) {
                                HapticManager.shared.notification(type: .success)
                                action()
                                withAnimation { offset = 0 }
                            } else {
                                withAnimation(.spring()) {
                                    offset = 0
                                }
                            }
                        }
                )
            }
            .frame(width: geo.size.width)
            .clipShape(Capsule())
        }
        .frame(height: height)
    }
}
