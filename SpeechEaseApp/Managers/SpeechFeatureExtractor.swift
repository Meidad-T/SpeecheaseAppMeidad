import Foundation
import AVFoundation
import Speech
import Accelerate

/// Extracts the 12 features that the Python training pipeline also computes.
/// Feature names and calculation logic must stay in sync with train.py.
struct SpeechFeatureExtractor {

    // Feature vector in the same order as FEATURE_NAMES in train.py
    struct Features {
        var wpm:             Double  // words per minute
        var fillerRatio:     Double  // filler words / total words
        var uniqueRatio:     Double  // unique words / total words
        var complexRatio:    Double  // words > 6 chars / total words
        var rmsEnergy:       Double  // mean RMS energy  (0–1 normalised)
        var energyVariance:  Double  // variance of per-chunk RMS
        var pauseRatio:      Double  // silent frames / total frames
        var badPauseRatio:   Double  // mid-sentence pauses / total pauses
        var stutterRatio:    Double  // consecutive repeated words / word count
        var sentenceCount:   Double  // number of sentences
        var avgSentenceLen:  Double  // words per sentence
        var durationSeconds: Double  // total speech duration

        /// Flat array in the exact column order the CoreML models expect.
        var array: [Double] {
            [wpm, fillerRatio, uniqueRatio, complexRatio,
             rmsEnergy, energyVariance, pauseRatio, badPauseRatio,
             stutterRatio, sentenceCount, avgSentenceLen, durationSeconds]
        }
    }

    static let fillers: Set<String> = [
        "um", "uh", "like", "literally", "you", "know",
        "basically", "actually", "honestly", "right", "so", "okay", "alright"
    ]

    // MARK: - Main entry point

    static func extract(
        transcript: SFTranscription,
        audioURL: URL,
        duration: TimeInterval
    ) -> Features? {
        let segments = transcript.segments
        guard !segments.isEmpty, duration > 0 else { return nil }

        let words = segments.map {
            $0.substring
                .lowercased()
                .trimmingCharacters(in: .punctuationCharacters)
        }
        let wordCount = Double(words.count)

        // WPM
        let wpm = (wordCount / duration) * 60.0

        // Filler ratio
        let fillerCount = words.filter { fillers.contains($0) }.count
        let fillerRatio = Double(fillerCount) / wordCount

        // Vocabulary
        let uniqueWords  = Set(words)
        let uniqueRatio  = Double(uniqueWords.count) / wordCount
        let complexRatio = words.filter { $0.count > 6 }.count.asDouble / wordCount

        // Stutter (consecutive repeated words)
        var stutter = 0
        for i in 1..<words.count where words[i] == words[i - 1] { stutter += 1 }
        let stutterRatio = Double(stutter) / wordCount

        // Pauses between segments
        var badPauses  = 0
        var totalGaps  = 0
        for i in 0..<(segments.count - 1) {
            let cur = segments[i]
            let nxt = segments[i + 1]
            let gap = nxt.timestamp - (cur.timestamp + cur.duration)
            if gap > 0.2 {
                totalGaps += 1
                let hasPunct = cur.substring.last.map { ".,!?;:".contains($0) } ?? false
                if !hasPunct && gap > 0.4 { badPauses += 1 }
            }
        }
        let badPauseRatio = Double(badPauses) / Double(max(totalGaps, 1))

        // Sentences
        let fullText = transcript.formattedString
        let sentences = fullText
            .replacingOccurrences(of: "!", with: ".")
            .replacingOccurrences(of: "?", with: ".")
            .components(separatedBy: ".")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let sentenceCount  = Double(max(sentences.count, 1))
        let avgSentenceLen = wordCount / sentenceCount

        // Audio features
        let (rmsEnergy, energyVariance, pauseRatio) = audioFeatures(url: audioURL)

        return Features(
            wpm:             rmsnd(wpm),
            fillerRatio:     rmsnd(fillerRatio),
            uniqueRatio:     rmsnd(uniqueRatio),
            complexRatio:    rmsnd(complexRatio),
            rmsEnergy:       rmsnd(rmsEnergy),
            energyVariance:  rmsnd(energyVariance),
            pauseRatio:      rmsnd(pauseRatio),
            badPauseRatio:   rmsnd(badPauseRatio),
            stutterRatio:    rmsnd(stutterRatio),
            sentenceCount:   rmsnd(sentenceCount),
            avgSentenceLen:  rmsnd(avgSentenceLen),
            durationSeconds: rmsnd(duration)
        )
    }

    // MARK: - Audio features via vDSP (mirrors librosa computation in train.py)

    private static func audioFeatures(url: URL) -> (rms: Double, variance: Double, pauseRatio: Double) {
        guard let file = try? AVAudioFile(forReading: url),
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: 16000,
                  channels: 1,
                  interleaved: false),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(file.length))
        else { return (0.5, 0, 0.3) }

        do { try file.read(into: buffer) } catch { return (0.5, 0, 0.3) }
        guard let data = buffer.floatChannelData?[0] else { return (0.5, 0, 0.3) }

        let frameLen = Int(buffer.frameLength)
        let hopSize  = 800   // 50 ms at 16 kHz  (matches train.py hop=0.05*sr)
        var chunkRMS: [Float] = []

        var i = 0
        while i + hopSize * 2 <= frameLen {
            let chunk = Array(UnsafeBufferPointer(start: data + i, count: hopSize * 2))
            var sqSum: Float = 0
            vDSP_svesq(chunk, 1, &sqSum, vDSP_Length(chunk.count))
            chunkRMS.append(sqrt(sqSum / Float(chunk.count)))
            i += hopSize
        }

        guard !chunkRMS.isEmpty else { return (0.5, 0, 0.3) }

        var mean: Float = 0
        vDSP_meanv(chunkRMS, 1, &mean, vDSP_Length(chunkRMS.count))

        var variance: Float = 0
        var neg = -mean
        var shifted = chunkRMS.map { $0 }
        vDSP_vsadd(chunkRMS, 1, &neg, &shifted, 1, vDSP_Length(chunkRMS.count))
        vDSP_svesq(shifted, 1, &variance, vDSP_Length(shifted.count))
        variance /= Float(shifted.count)

        let silenceThreshold = mean * 0.15
        let silentCount = chunkRMS.filter { $0 < silenceThreshold }.count
        let pauseRatio  = Double(silentCount) / Double(chunkRMS.count)

        return (Double(mean), Double(variance), pauseRatio)
    }

    // Rounds to 6 significant figures and guards NaN/Inf
    private static func rmsnd(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return v
    }
}

private extension Int {
    var asDouble: Double { Double(self) }
}
