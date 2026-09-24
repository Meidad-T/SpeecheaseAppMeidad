import Foundation
import CoreMotion
import AVFoundation
import Combine

/// Passive "look around the room" coach for practice sessions.
///
/// When motion-capable AirPods are connected and worn, this tracks the speaker's
/// head yaw. If they haven't turned their head (left/right) for `reminderInterval`
/// seconds, it plays a gentle reminder bell and surfaces an on-screen cue. The
/// next time they look around it plays a happy confirmation chime and shows a
/// checkmark. After two ignored reminders in a row it also speaks a spoken
/// prompt via the system voice.
///
/// It is entirely self-gating: if no compatible AirPods are present
/// (`CMHeadphoneMotionManager.isDeviceMotionAvailable == false`) it does nothing,
/// so recording behaves exactly as before. Bell tones are synthesized in-memory
/// (no bundled assets) and play through the current output route (the AirPods).
final class HeadMovementCoach: ObservableObject {

    /// On-screen cue the UI reacts to.
    enum Cue: Equatable {
        case idle       // nothing shown
        case reminder   // "look around" text + animated face
        case looked     // success checkmark (auto-clears)
    }

    /// True while head-tracking is actually running (compatible AirPods present).
    @Published private(set) var isActive = false

    /// True while motion samples are actively arriving from worn AirPods.
    /// Goes false the moment they're removed, and back true when reinserted.
    @Published private(set) var isTracking = false

    /// Drives the on-screen overlay.
    @Published private(set) var cue: Cue = .idle

    /// Short line shown on screen when reminding.
    let reminderText = "Look around & address your audience"

    /// Seconds of no head movement before the reminder fires (and repeats).
    /// DEBUG: set low for testing; production value ~45.
    var reminderInterval: TimeInterval = 10

    /// Yaw deviation (radians) from the resting facing direction that counts as
    /// "looking around". ~0.35 rad ≈ 20°.
    private let turnThreshold: Double = 0.35

    /// If no motion sample arrives for this long, assume the AirPods were removed
    /// (or taken out of the ear) and suspend coaching until samples resume.
    private let motionStaleThreshold: TimeInterval = 2.0

    private let motion = CMHeadphoneMotionManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "HeadMovementCoach.motion"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    // Motion-queue-only state (serialized by the single-op queue)
    private var restingYaw: Double?
    private var inTurn = false

    // Main-only state
    private var lastMovementTime: CFTimeInterval = 0
    private var lastSampleTime: CFTimeInterval = 0
    private var awaitingLook = false
    private var consecutiveReminders = 0
    private var checkTimer: Timer?
    private var clearLookedWork: DispatchWorkItem?

    private var reminderPlayer: AVAudioPlayer?
    private var goodPlayer: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var chosenVoice: AVSpeechSynthesisVoice?

    // MARK: - Lifecycle

    /// Begin coaching. Safe to call unconditionally — it silently no-ops when no
    /// motion-capable AirPods are connected, or motion access is denied.
    func start() {
        guard !isActive else { return }
        guard motion.isDeviceMotionAvailable else { return }

        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .denied, .restricted:
            return
        default:
            break
        }

        prepareTones()

        restingYaw = nil
        inTurn = false
        awaitingLook = false
        consecutiveReminders = 0
        cue = .idle
        lastMovementTime = CACurrentMediaTime()
        lastSampleTime = CACurrentMediaTime()
        isActive = true

        loadVoiceAndPrewarm()

        motion.startDeviceMotionUpdates(to: motionQueue) { [weak self] data, _ in
            guard let self, let yaw = data?.attitude.yaw else { return }
            self.processYaw(yaw)
        }

        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForIdle()
        }
    }

    func stop() {
        guard isActive else { return }
        motion.stopDeviceMotionUpdates()
        checkTimer?.invalidate()
        checkTimer = nil
        clearLookedWork?.cancel()
        reminderPlayer?.stop()
        goodPlayer?.stop()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        cue = .idle
        isTracking = false
        isActive = false
    }

    deinit {
        motion.stopDeviceMotionUpdates()
        checkTimer?.invalidate()
    }

    // MARK: - Motion processing (runs on motionQueue)

    private func processYaw(_ yaw: Double) {
        lastSampleTime = CACurrentMediaTime()

        guard let resting = restingYaw else {
            restingYaw = yaw
            return
        }

        let deviation = Self.angleDelta(yaw, resting)

        // Slowly let the resting direction follow where they mostly face, so a
        // sustained turn doesn't leave us permanently "off-center".
        restingYaw = resting + 0.02 * deviation

        if abs(deviation) > turnThreshold {
            if !inTurn {
                inTurn = true
                DispatchQueue.main.async { [weak self] in self?.registerTurn() }
            }
        } else if abs(deviation) < turnThreshold * 0.5 {
            // Returned near center — arm detection for the next turn.
            inTurn = false
        }
    }

    /// Shortest signed angular difference a - b, wrapped to [-π, π].
    private static func angleDelta(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }

    // MARK: - Coaching logic (runs on main)

    private func registerTurn() {
        lastMovementTime = CACurrentMediaTime()

        // If she's mid-sentence and the speaker looks around, cut her off neatly
        // at the next word boundary rather than letting her finish talking over them.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }

        guard awaitingLook else { return }
        awaitingLook = false
        consecutiveReminders = 0
        goodPlayer?.play()
        flashLooked()
    }

    private func checkForIdle() {
        guard isActive else { return }
        let now = CACurrentMediaTime()

        // Are motion samples still arriving? (AirPods worn and feeding data.)
        let receiving = (now - lastSampleTime) < motionStaleThreshold
        if isTracking != receiving { isTracking = receiving }

        // AirPods removed / not in ear → suspend all demands, like auto-pressing
        // the button off. Don't accumulate idle time so we don't nag on return.
        guard receiving else {
            if cue != .idle { cue = .idle }
            if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
            awaitingLook = false
            consecutiveReminders = 0
            lastMovementTime = now
            return
        }

        guard now - lastMovementTime >= reminderInterval else { return }

        consecutiveReminders += 1
        awaitingLook = true
        reminderPlayer?.play()

        clearLookedWork?.cancel()
        withAnimationCue { self.cue = .reminder }

        // Escalate to a spoken prompt once they've ignored two nudges in a row.
        if consecutiveReminders >= 2 {
            speakReminder()
        }

        // Reset so the reminder repeats every interval until they look.
        lastMovementTime = now
    }

    private func flashLooked() {
        withAnimationCue { self.cue = .looked }
        clearLookedWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.cue == .looked { self.withAnimationCue { self.cue = .idle } }
        }
        clearLookedWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func speakReminder() {
        guard !synthesizer.isSpeaking else { return }
        let utterance = AVSpeechUtterance(string: "Make sure you are looking around to address your audience")
        utterance.voice = chosenVoice   // best installed voice; nil → system default
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        // Speak off the main thread: the first synthesis can otherwise stall the UI
        // while the engine/voice initialize against the active recording session.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.synthesizer.speak(utterance)
        }
    }

    // MARK: - Voice selection & warm-up

    /// Requests Personal Voice access, picks the best installed voice off the main
    /// thread, and warms up the TTS engine so the first spoken prompt is instant.
    private func loadVoiceAndPrewarm() {
        // Personal Voice is the user's own recorded/customized voice (iOS 17+).
        // If granted it becomes selectable and we prefer it over stock voices.
        AVSpeechSynthesizer.requestPersonalVoiceAuthorization { [weak self] _ in
            self?.refreshVoiceSelection()
        }
        refreshVoiceSelection(prewarm: true)
    }

    private func refreshVoiceSelection(prewarm: Bool = false) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let voice = Self.preferredVoice()
            DispatchQueue.main.async { self.chosenVoice = voice }

            if prewarm {
                let warm = AVSpeechUtterance(string: " ")
                warm.volume = 0
                warm.voice = voice
                self.synthesizer.speak(warm)
            }
        }
    }

    /// Best available voice for the user's language:
    /// Personal Voice ≻ premium ≻ enhanced ≻ default (novelty voices excluded).
    /// Returns nil to fall back to the system default.
    private static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let lang = AVSpeechSynthesisVoice.currentLanguageCode()
        let prefix = String(lang.prefix(2))
        let matches = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == lang || $0.language.hasPrefix(prefix)
        }

        // 1) A Personal Voice the user set up wins — their own customized voice.
        if let personal = matches.first(where: { $0.voiceTraits.contains(.isPersonalVoice) }) {
            return personal
        }

        // 2) Otherwise the highest-quality neural voice, skipping novelty voices.
        //    quality.rawValue: default = 1, enhanced = 2, premium = 3 (higher = better).
        let usable = matches.filter { !$0.voiceTraits.contains(.isNoveltyVoice) }
        return usable.max {
            if $0.quality.rawValue != $1.quality.rawValue {
                return $0.quality.rawValue < $1.quality.rawValue
            }
            // Prefer an exact language match at equal quality.
            let ea = ($0.language == lang) ? 1 : 0
            let eb = ($1.language == lang) ? 1 : 0
            return ea < eb
        }
    }

    /// Publishes a cue change with a light animation so views transition smoothly.
    private func withAnimationCue(_ change: @escaping () -> Void) {
        change()
    }

    // MARK: - Tone synthesis

    private func prepareTones() {
        guard reminderPlayer == nil else { return }

        // Gentle, low descending two-note chime — a calm nudge to look around.
        let reminder = Self.makeChime(notes: [
            (freq: 587.33, start: 0.00, dur: 0.55, gain: 0.5),   // D5
            (freq: 440.00, start: 0.16, dur: 0.65, gain: 0.5),   // A4 (soothing descent)
        ])
        // Happy ascending two-note chime — positive reinforcement when they look.
        let good = Self.makeChime(notes: [
            (freq: 784,  start: 0.00, dur: 0.28, gain: 0.55),   // G5
            (freq: 1175, start: 0.11, dur: 0.40, gain: 0.65),   // D6
        ])

        reminderPlayer = try? AVAudioPlayer(data: reminder)
        goodPlayer = try? AVAudioPlayer(data: good)
        reminderPlayer?.volume = 0.5
        goodPlayer?.volume = 0.5
        reminderPlayer?.prepareToPlay()
        goodPlayer?.prepareToPlay()
    }

    /// Synthesizes a short bell-like chime as 16-bit PCM mono WAV data.
    /// Each note is a decaying sine with two added harmonics for a bell timbre.
    private static func makeChime(
        notes: [(freq: Double, start: Double, dur: Double, gain: Double)],
        sampleRate: Double = 44_100
    ) -> Data {
        let total = notes.map { $0.start + $0.dur }.max() ?? 0.5
        let frameCount = Int(total * sampleRate) + 1
        var buffer = [Double](repeating: 0, count: frameCount)

        for note in notes {
            let startFrame = Int(note.start * sampleRate)
            let durFrames = Int(note.dur * sampleRate)
            let decay = 5.0 / note.dur          // ~e^-5 by the end of the note
            let attack = min(0.02, note.dur * 0.2)   // short fade-in kills the harsh click
            for n in 0..<durFrames {
                let idx = startFrame + n
                if idx >= frameCount { break }
                let t = Double(n) / sampleRate
                let atk = attack > 0 ? min(1.0, t / attack) : 1.0
                let env = atk * exp(-t * decay)
                let w = 2 * Double.pi * note.freq * t
                // Softer harmonic mix (less high-frequency energy = warmer, less piercing).
                let s = sin(w) + 0.35 * sin(2 * w) + 0.12 * sin(3 * w)
                buffer[idx] += s * env * note.gain
            }
        }

        // Normalize to avoid clipping.
        let peak = buffer.reduce(0.0) { max($0, abs($1)) }
        let norm = peak > 0 ? 0.9 / peak : 1.0

        var pcm = Data(capacity: frameCount * 2)
        for sample in buffer {
            let v = max(-1.0, min(1.0, sample * norm))
            let i = Int16(v * Double(Int16.max))
            pcm.append(UInt8(truncatingIfNeeded: i))
            pcm.append(UInt8(truncatingIfNeeded: i >> 8))
        }

        return wavData(pcm: pcm, sampleRate: Int(sampleRate))
    }

    /// Wraps 16-bit mono PCM in a minimal WAV container.
    private static func wavData(pcm: Data, sampleRate: Int) -> Data {
        let channels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = pcm.count

        var d = Data()
        func str(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }

        str("RIFF")
        u32(UInt32(36 + dataSize))
        str("WAVE")
        str("fmt ")
        u32(16)
        u16(1)                          // PCM
        u16(UInt16(channels))
        u32(UInt32(sampleRate))
        u32(UInt32(byteRate))
        u16(UInt16(blockAlign))
        u16(UInt16(bitsPerSample))
        str("data")
        u32(UInt32(dataSize))
        d.append(pcm)
        return d
    }
}
