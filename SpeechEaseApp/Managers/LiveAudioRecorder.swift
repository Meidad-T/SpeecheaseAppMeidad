import SwiftUI
import AVFoundation
import Combine

@MainActor
class LiveAudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var duration: TimeInterval = 0
    @Published var audioLevel: Float = 0
    
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingURL: URL?
    
    override init() {
        super.init()
    }
    
    func prepare() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Session error: \(error)")
        }
    }
    
    func startRecording() {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docDir.appendingPathComponent("live_rec_\(Date().timeIntervalSince1970).m4a")
        self.recordingURL = url
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.delegate = self
            newRecorder.isMeteringEnabled = true
            
            if newRecorder.record() {
                self.audioRecorder = newRecorder
                self.isRecording = true
                self.startTimer()
            }
        } catch {
            print("Recording failed: \(error)")
        }
    }
    
    func stopRecording() -> URL? {
        audioRecorder?.stop()
        isRecording = false
        timer?.invalidate()
        let url = recordingURL
        recordingURL = nil
        return url
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let rec = self.audioRecorder else { return }

                // Guard against route changes (e.g. AirPods removed) that can make
                // currentTime report negative — keep the displayed time monotonic.
                if rec.isRecording {
                    self.duration = max(self.duration, rec.currentTime)
                }

                rec.updateMeters()
                let power = rec.averagePower(forChannel: 0)
                
                let minDb: Float = -50.0
                let normalized = max(0.0, (power - minDb) / (0 - minDb))
                self.audioLevel = normalized
            }
        }
    }
}
