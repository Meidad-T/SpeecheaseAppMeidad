import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import Speech
import CoreMedia

struct PracticeSessionView: View {
    @Binding var session: PracticeSession
    var onSave: (PracticeSession) -> Void
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var speechManager = SpeechRecognizerManager()
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var timer: Timer?
    @State private var currentTime: TimeInterval = 0
    @State private var totalDuration: TimeInterval = 0
    
    @State private var selectedTab = "New"
    @State private var isImporting = false
    @State private var isAnalyzing = false
    @State private var analysisStatus: String = "Processing..."
    
    @State private var showFullTranscript = false
    
    @State private var showTranscript = false
    @State private var showSummary = false
    @State private var showMetrics = false
    @State private var showScore = false
    @State private var isResultMode = false
    
    @State private var showErrorAlert = false
    @State private var errorAlertMessage = ""
    
    @State private var showResetConfirmation = false
    
    @State private var confidenceScore: Int = 50
    
    @State private var showRecordingChoice = false
    @State private var showAudioRecorder = false
    @State private var showVideoRecorder = false
    
    var activeFoci: [PracticeFocus] {
        session.foci
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                MeshBackground()
                
                ScrollView {
                    VStack(spacing: isResultMode ? 10 : 30) {
                        if !isResultMode {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(activeFoci) { focus in
                                        Label(focus.title, systemImage: focus.icon)
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(.primary.opacity(0.05), in: Capsule())
                                            .overlay(Capsule().stroke(.primary.opacity(0.2), lineWidth: 1))
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                            .scrollBounceBehavior(.basedOnSize)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                        
                        Picker("Session Mode", selection: $selectedTab) {
                             Text("New Attempt").tag("New")
                             Text("History").tag("Past")
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .onChange(of: selectedTab) { _, newValue in
                        }
                        .confirmationDialog("Practice Another Time?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
                            Button("Reset & Record", role: .destructive) {
                                resetAnalysisState()
                                showRecordingChoice = true
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will reset the current lesson, warning you to submit another recording for analysis.")
                        }
                        
                        if selectedTab == "New" {
                            startNewSessionView
                        } else {
                            pastAttemptsList
                        }
                    }
                    .padding()
                }
            }
            .overlay {
                if isAnalyzing {
                    AnalyzingOverlayView(statusText: analysisStatus)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .disabled(isAnalyzing)
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: session.foci.contains(where: { $0.requiresVideo }) ? [.movie, .video] : [.audio],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .sheet(isPresented: $showFullTranscript) {
                if let filename = session.recordingFileName,
                   let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    
                    FullTranscriptView(
                        text: speechManager.transcript,
                        audioUrl: docDir.appendingPathComponent(filename),
                        transcription: speechManager.transcriptionResult
                    )
                } else {
                    FullTranscriptView(text: speechManager.transcript, audioUrl: nil, transcription: nil)
                }
            }
            .fullScreenCover(isPresented: $showAudioRecorder) {
                LiveSessionView(
                    timeLimitSeconds: session.enforceTimeLimit ? Double(session.timeLimitMinutes ?? 0) * 60.0 : nil,
                    onFinish: { result in
                        showAudioRecorder = false
                        handleRecordingResult(result)
                    },
                    onCancel: {
                         showAudioRecorder = false
                    }
                )
            }
            .fullScreenCover(isPresented: $showVideoRecorder) {
                CameraRecordingSheet(
                    externalAnalysisStatus: $analysisStatus,
                    timeLimitSeconds: session.enforceTimeLimit ? Double(session.timeLimitMinutes ?? 0) * 60.0 : nil
                ) { result in
                    handleRecordingResult(result)
                }
            }
        }
        .alert("Analysis Issue", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {
                resetAnalysisState()
                isImporting = true 
            }
        } message: {
            Text(errorAlertMessage)
        }
        .onAppear {
            showRecordingChoice = true
            
            DispatchQueue.global(qos: .userInitiated).async {
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
                try? session.setActive(true)
            }
            
            if let filename = session.recordingFileName {
                guard let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
                let url = docDir.appendingPathComponent(filename)
                
                if speechManager.transcript.isEmpty {
                     speechManager.transcribeAudioFile(url: url)
                }
            }
        }
    }
    
    func deleteAttempt(_ attempt: PracticeAttempt) {
        if let index = session.history.firstIndex(where: { $0.id == attempt.id }) {
            withAnimation {
                session.history.remove(at: index)
                onSave(session)
            }
        }
    }
    
    func handleRecordingResult(_ result: Result<URL, Error>) {
        handleFileImport(result.map { [$0] })
    }

    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            let ext = url.pathExtension.isEmpty ? (session.foci.contains(where: { $0.requiresVideo }) ? "mov" : "m4a") : url.pathExtension
            let uniqueName = "\(UUID().uuidString).\(ext)"
            
            guard let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let destUrl = docDir.appendingPathComponent(uniqueName)
            
            do {
                if FileManager.default.fileExists(atPath: destUrl.path) {
                    try FileManager.default.removeItem(at: destUrl)
                }
                
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    try FileManager.default.copyItem(at: url, to: destUrl)
                } else {
                    try FileManager.default.copyItem(at: url, to: destUrl)
                }
                
                DispatchQueue.main.async {
                    session.recordingFileName = uniqueName
                    session.speechReport = nil
                    
                    speechManager.transcribeAudioFile(url: destUrl)
                    
                    self.startAnalysis()
                }
            } catch {
                print("Error: \(error)")
            }
            
        case .failure(let error):
            print("Import failed: \(error)")
        }
    }
    
    func startAnalysis() {
        guard let _ = session.recordingFileName else { return }
        
        withAnimation {
            isAnalyzing = true
            analysisStatus = "Transcribing..."
        }
        
        Task { @MainActor in
            while speechManager.isProcessing {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            
            if let error = speechManager.errorMessage {
                handleError("Transcription failed: \(error)")
            } else if let result = speechManager.transcriptionResult, 
                      !result.formattedString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                performAnalysis(transcript: result)
            } else {
                handleError("No words detected! Please select another file!")
            }
        }
    }
    
    func handleError(_ message: String) {
        withAnimation {
            isAnalyzing = false
            errorAlertMessage = message
            showErrorAlert = true
        }
    }
    
    func performAnalysis(transcript: SFTranscription) {
        isAnalyzing = true
        analysisStatus = "Analyzing Speech..."
        
        Task {
            guard let filename = session.recordingFileName,
                  let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let fileUrl = docDir.appendingPathComponent(filename)
            
            let timeLimit = session.enforceTimeLimit ? Double(session.timeLimitMinutes ?? 0) * 60.0 : nil
            
            let analyzer = SpeechAnalyzer()
            
            var report = await analyzer.analyze(
                transcript: transcript,
                audioFile: fileUrl,
                timeLimit: timeLimit,
                enforceStrict: session.enforceTimeLimit,
                onProgress: { status in
                    Task { @MainActor in
                        self.analysisStatus = status
                    }
                }
            )
            
            if session.foci.contains(where: { $0.requiresVideo }) {
                await MainActor.run { analysisStatus = "Analyzing Body Language..." }
                let videoAnalyzer = BodyLanguageAnalyzer()
                let videoReport = await videoAnalyzer.analyzeVideo(url: fileUrl)
                
                report.bodyLanguageScore = videoReport.score
                report.eyeContactScore = videoReport.eyeContactScore
                report.visualInsights = videoReport.insights
                report.insights.append(contentsOf: videoReport.insights)
                
                let combinedScore = (Double(report.overallScore) * 0.6) + (videoReport.score * 0.4)
                report.overallScore = Int(combinedScore)
            }
            
            await MainActor.run {
                session.speechReport = report
                
                let newAttempt = PracticeAttempt(
                    date: Date(),
                    recordingFileName: filename,
                    speechReport: report,
                    confidenceScore: confidenceScore
                )
                session.history.append(newAttempt)
                session.practiceLog.append(Date())
                onSave(session)
                
                isAnalyzing = false
                
                if showVideoRecorder {
                     showVideoRecorder = false
                }
                if showAudioRecorder {
                    showAudioRecorder = false
                }
                
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    isResultMode = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation {
                        showTranscript = true
                    }
                    
                    withAnimation(.spring().delay(0.2)) {
                        showSummary = true
                    }
                    withAnimation(.spring().delay(0.6)) {
                        showMetrics = true
                    }
                    withAnimation(.spring().delay(1.0)) {
                        showScore = true
                    }
                }
            }
        }
    }
    
    func resetAnalysisState() {
        session.recordingFileName = nil
        session.speechReport = nil
        confidenceScore = 50
        showScore = false
        showMetrics = false
        showSummary = false
        showTranscript = false
        isResultMode = false
        speechManager.reset()
    }
    
    @ViewBuilder
    private var startNewSessionView: some View {
        if showRecordingChoice {
            VStack(spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ready to Practice?")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Choose how you want to start")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                }
                .padding(.bottom, 10)
                
                Button {
                    if session.recordingFileName != nil {
                        resetAnalysisState()
                    }
                    
                    if session.foci.contains(where: { $0.requiresVideo }) {
                        showVideoRecorder = true
                    } else {
                        showAudioRecorder = true
                    }
                    showRecordingChoice = false
                } label: {
                    RecordLiveActionCard(
                        session: session,
                        requiresVideo: session.foci.contains(where: { $0.requiresVideo })
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    if session.recordingFileName != nil {
                        resetAnalysisState()
                    }
                    isImporting = true
                    showRecordingChoice = false
                } label: {
                    UploadActionCard()
                }
                .buttonStyle(.plain)
                
                if session.recordingFileName != nil {
                    Button {
                        withAnimation {
                            showRecordingChoice = false
                        }
                    } label: {
                        Text("Back to Selected File")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.top, 20)
            
        } else if let filename = session.recordingFileName {
            VStack(spacing: 0) {
                if !isResultMode {
                    FileStatusCard(
                        filename: filename,
                        isProcessing: speechManager.isProcessing,
                        isReady: !speechManager.transcript.isEmpty,
                        onReplace: {
                            resetAnalysisState()
                            showRecordingChoice = true
                        }
                    )
                    .disabled(isAnalyzing)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .padding(.bottom, 20)
                }
            }
            
            LazyVStack(spacing: 15) {
                if showScore, let report = session.speechReport {
                    ResultsScoreHeader(score: report.overallScore, feedback: report.feedback)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                if showMetrics, let report = session.speechReport {
                    ResultsMetricsGrid(report: report, foci: activeFoci)
                        .transition(.scale.combined(with: .opacity))
                    
                    if let insights = report.visualInsights, !insights.isEmpty {
                        ResultsInsightsList(userInsights: insights)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.horizontal, 4)
                    }
                }
                
                if showSummary {
                    ResultsAISummary(report: session.speechReport)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                if showTranscript {
                    TranscriptPreviewCard(
                        text: speechManager.transcript,
                        onViewFull: { showFullTranscript = true }
                    )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    
                    if !session.history.isEmpty {
                        ProgressTrendGraph(
                            history: session.history,
                            currentScore: session.speechReport?.overallScore,
                            currentConfidence: confidenceScore
                        )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.bottom, 10)
                    }
                    
                    ConfidenceRater(score: $confidenceScore)
                        .transition(.scale.combined(with: .opacity))
                        .padding(.bottom, 20)
                        .onChange(of: confidenceScore) { _, newValue in
                            if let lastIdx = session.history.indices.last {
                                session.history[lastIdx].confidenceScore = newValue
                                onSave(session)
                            }
                        }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showScore)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showMetrics)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showSummary)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showTranscript)
            
        } else {
            VStack(spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ready to Practice?")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Choose how you want to start")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                }
                .padding(.bottom, 10)
                
                Button {
                    if session.foci.contains(where: { $0.requiresVideo }) {
                        showVideoRecorder = true
                    } else {
                        showAudioRecorder = true
                    }
                } label: {
                    RecordLiveActionCard(
                        session: session,
                        requiresVideo: session.foci.contains(where: { $0.requiresVideo })
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    isImporting = true
                } label: {
                    UploadActionCard()
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)
        }
    }
    
    @ViewBuilder
    private var pastAttemptsList: some View {
        PastAttemptsListView(
            history: session.history.sorted(by: { $0.date > $1.date }),
            onDelete: deleteAttempt
        )
    }
}

struct TranscriptPreviewCard: View {
    let text: String
    var onViewFull: () -> Void
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Transcript", systemImage: "quote.opening")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(text.isEmpty ? "Transcribing..." : text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if !text.isEmpty {
                    Button(action: onViewFull) {
                        HStack {
                            Spacer()
                            Text("View Full")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.cyan)
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption)
                                .foregroundStyle(.cyan)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct FullTranscriptView: View {
    let text: String
    let audioUrl: URL?
    let transcription: SFTranscription?
    @Environment(\.dismiss) var dismiss
    
    @State private var audioPlayer: AVPlayer?
    @State private var isPlaying: Bool = false
    @State private var currentTime: TimeInterval = 0
    @State private var totalDuration: TimeInterval = 0
    @State private var timeObserver: Any?
    
    var body: some View {
        NavigationStack {
            ZStack {
                MeshBackground()
                
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if let transcription = transcription, let _ = audioUrl {
                                FlowLayout(spacing: 6) {
                                    ForEach(transcription.segments.indices, id: \.self) { index in
                                        let segment = transcription.segments[index]
                                        let isHighlighted = currentTime >= segment.timestamp && currentTime < (segment.timestamp + segment.duration)
                                        
                                        Text(segment.substring)
                                            .font(.body)
                                            .fontWeight(isHighlighted ? .bold : .regular)
                                            .foregroundStyle(isHighlighted ? Color.accentColor : .primary)
                                            .padding(.horizontal, 2)
                                            .padding(.vertical, 1)
                                            .background(
                                                isHighlighted ? Color.accentColor.opacity(0.1) : Color.clear
                                            )
                                            .cornerRadius(4)
                                            .onTapGesture {
                                                seek(to: segment.timestamp)
                                            }
                                    }
                                }
                            } else {
                                Text(text)
                                    .font(.body)
                                    .lineSpacing(6)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .padding()
                        .padding(.bottom, 100)
                    }
                    
                    if let _ = audioUrl {
                        VStack(spacing: 12) {
                            HStack(spacing: 16) {
                                Button(action: togglePlayback) {
                                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 44))
                                        .foregroundStyle(Color.accentColor)
                                        .shadow(color: Color.accentColor.opacity(0.3), radius: 10)
                                }
                                .buttonStyle(.plain)
                                
                                VStack(spacing: 4) {
                                    Slider(value: Binding(
                                        get: { currentTime },
                                        set: { seek(to: $0) }
                                    ), in: 0...totalDuration)
                                    .tint(Color.accentColor)
                                    
                                    HStack {
                                        Text(formatTime(currentTime))
                                        Spacer()
                                        Text(formatTime(totalDuration))
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(20, corners: [.topLeft, .topRight])
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
                    }
                }
            }
            .navigationTitle("Full Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { 
                        stopPlayer()
                        dismiss() 
                    }
                }
            }
            .onAppear(perform: setupPlayer)
            .onDisappear(perform: stopPlayer)
        }
    }
    
    func setupPlayer() {
        guard let url = audioUrl else { return }
        
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        
        let playerItem = AVPlayerItem(url: url)
        audioPlayer = AVPlayer(playerItem: playerItem)
        
        Task {
            do {
                if let duration = try await audioPlayer?.currentItem?.asset.load(.duration) {
                    await MainActor.run {
                        self.totalDuration = CMTimeGetSeconds(duration)
                    }
                }
            } catch {
                print("Failed to load duration: \(error)")
            }
        }
        
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = audioPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            self.currentTime = CMTimeGetSeconds(time)
            self.isPlaying = self.audioPlayer?.timeControlStatus == .playing
        }
    }
    
    func togglePlayback() {
        guard let player = audioPlayer else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= totalDuration - 0.5 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        }
    }
    
    func stopPlayer() {
        audioPlayer?.pause()
        if let observer = timeObserver {
            audioPlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
        audioPlayer = nil
        isPlaying = false
    }
    
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        audioPlayer?.seek(to: cmTime)
        currentTime = time
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape( RoundedCorner(radius: radius, corners: corners) )
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.headline)
            .foregroundStyle(isSelected ? (Color(UIColor.systemBackground)) : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? .primary : Color.clear)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct PastAttemptsListView: View {
    let history: [PracticeAttempt]
    @State private var selectedAttempt: PracticeAttempt?
    var onDelete: (PracticeAttempt) -> Void = { _ in }
    
    var body: some View {
        VStack {
            if history.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No past attempts yet")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                ForEach(history) { attempt in
                    Button {
                        selectedAttempt = attempt
                    } label: {
                        GlassCard {
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .stroke(.secondary.opacity(0.2), lineWidth: 4)
                                        .frame(width: 50, height: 50)
                                    Circle()
                                        .trim(from: 0, to: CGFloat(attempt.score) / 100)
                                        .stroke(scoreColor(attempt.score), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                        .frame(width: 50, height: 50)
                                        .shadow(color: scoreColor(attempt.score).opacity(0.5), radius: 5)
                                    Text("\(attempt.score)")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.primary)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(attempt.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(attempt.speechReport.feedback)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary.opacity(0.3))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            onDelete(attempt)
                        } label: {
                            Label("Delete Result", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedAttempt != nil },
            set: { if !$0 { selectedAttempt = nil } }
        )) {
            if let attempt = selectedAttempt {
                AnalysisResultView(report: attempt.speechReport)
            }
        }
    }
    
    func scoreColor(_ score: Int) -> Color {
        return score >= 90 ? .green : (score >= 70 ? .cyan : (score >= 50 ? .orange : .red))
    }
}

struct FileStatusCard: View {
    let filename: String
    let isProcessing: Bool
    let isReady: Bool
    let onReplace: () -> Void
    
    var body: some View {
        GlassCard {
            HStack(spacing: 16) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(isProcessing ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(Color.cyan.gradient))
                    .shadow(color: (isProcessing ? Color.orange : Color.cyan).opacity(0.4), radius: 8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected File")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    Text(filename)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    if isProcessing {
                        Text("Processing...")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if isReady {
                        Text("Ready")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
                
                Spacer()
                
                Button(action: onReplace) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .padding(8)
                        .background(.primary.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
    }
}

struct RecordLiveActionCard: View {
    let session: PracticeSession
    let requiresVideo: Bool
    @State private var animate = false

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        let radius: CGFloat = isIPad ? 30 : 20

        ZStack(alignment: .bottom) {
            Color.black

            // Wave with gradient mask — no hard clip edge
            AnimatedGlowWaveView()
                .frame(height: isIPad ? 140 : 110)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.5), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(0.85)

            // Orange gradient accent
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.5, blue: 0.0).opacity(0.22),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Decorative icon
            HStack {
                Spacer()
                Image(systemName: requiresVideo ? "figure.stand" : "mic.fill")
                    .font(.system(size: isIPad ? 250 : 160))
                    .foregroundStyle(.white)
                    .opacity(0.1)
                    .offset(x: isIPad ? 40 : 20, y: isIPad ? 20 : 10)
                    .scaleEffect(animate ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: animate)
            }

            // Text content
            HStack {
                VStack(alignment: .leading, spacing: isIPad ? 10 : 4) {
                    HStack(spacing: 8) {
                        Image(systemName: requiresVideo ? "video.fill" : "mic.fill")
                            .font(isIPad ? .headline : .subheadline)
                        Text(requiresVideo ? "Camera Mode" : "Microphone Mode")
                            .font(isIPad ? .subheadline : .caption)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, isIPad ? 12 : 10)
                    .padding(.vertical, isIPad ? 6 : 4)
                    .background(.white.opacity(0.25), in: Capsule())
                    .foregroundStyle(.white)

                    Text("Record Live")
                        .font(.system(size: isIPad ? 36 : 28, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 3)

                    Text(requiresVideo ? "Analyze body language & speech" : "Analyze vocal tone & clarity")
                        .font(isIPad ? .title3 : .subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.2), radius: 2)
                        .padding(.top, isIPad ? 4 : 2)

                    Spacer()

                    HStack {
                        Text("Start Session")
                            .fontWeight(.bold)
                        Image(systemName: "arrow.right")
                    }
                    .font(isIPad ? .title3 : .headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, isIPad ? 24 : 16)
                    .padding(.vertical, isIPad ? 14 : 10)
                    .background(
                        Capsule()
                            .fill(.white)
                            .shadow(color: Color(red: 1.0, green: 0.7, blue: 0.2).opacity(0.5), radius: 8, x: 0, y: 2)
                    )
                    .padding(.bottom, isIPad ? 0 : 5)
                }
                .padding(isIPad ? 30 : 20)

                Spacer()
            }
        }
        .frame(height: isIPad ? 240 : 180)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .shadow(color: Color(red: 1.0, green: 0.6, blue: 0.1).opacity(0.5), radius: isIPad ? 20 : 15, y: isIPad ? 10 : 6)
        .onAppear {
            animate = true
        }
    }
}

struct UploadActionCard: View {
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: isIPad ? 24 : 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: isIPad ? 24 : 16)
                        .strokeBorder(.tertiary.opacity(0.5), lineWidth: 1.5)
                )
            
            GeometryReader { geo in
                HStack {
                    Spacer()
                    Image(systemName: "square.and.arrow.up.fill")
                        .font(.system(size: isIPad ? 140 : 100))
                        .foregroundStyle(.secondary)
                        .opacity(0.05)
                        .offset(x: isIPad ? 30 : 10, y: isIPad ? 30 : 10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: isIPad ? 24 : 16))
            
            HStack {
                VStack(alignment: .leading, spacing: isIPad ? 6 : 4) {
                    Text("Upload Existing")
                        .font(isIPad ? .title3 : .headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    
                    Text("Import a file from your library")
                        .font(isIPad ? .body : .caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "folder.fill")
                    .font(isIPad ? .title : .title3)
                    .foregroundStyle(.secondary)
                    .padding(isIPad ? 16 : 10)
                    .background(.secondary.opacity(0.1), in: Circle())
            }
            .padding(isIPad ? 30 : 20)
        }
        .frame(height: isIPad ? 120 : 80)
    }
}
