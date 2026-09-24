import Foundation
import Speech
import NaturalLanguage
import AVFoundation
import SwiftUI
import Combine

struct SpeechReport: Codable {
    var overallScore: Int
    var pacingScore: Double
    var vocabularyScore: Double
    var toneScore: Double
    var engagementScore: Double
    var pauseScore: Double
    var feedback: String
    var insights: [SpeechInsight] = []
    var narrativeReport: String?
    var detailedAnalysis: String?
    
    var bodyLanguageScore: Double?
    var eyeContactScore: Double?
    var visualInsights: [SpeechInsight]?
    
    var isStrictViolation: Bool = false
    var strictTimeLimit: TimeInterval? = nil
}

struct SpeechInsight: Identifiable, Codable {
    var id = UUID()
    let title: String
    let description: String
    let timestamp: TimeInterval
    let type: InsightType
}

enum InsightType: String, Codable {
    case positive
    case negative
    case neutral
    
    var color: Color {
        switch self {
        case .positive: return .green
        case .negative: return .red
        case .neutral: return .orange
        }
    }
    
    var icon: String {
        switch self {
        case .positive: return "checkmark.circle.fill"
        case .negative: return "exclamationmark.triangle.fill"
        case .neutral: return "info.circle.fill"
        }
    }
}

@MainActor
class SpeechAnalyzer: ObservableObject {
    
    func analyze(
        transcript: SFTranscription,
        audioFile: URL,
        timeLimit: TimeInterval? = nil,
        enforceStrict: Bool = false,
        onProgress: @escaping (String) -> Void = { _ in }
    ) async -> SpeechReport {
        
        var analysisSegments = transcript.segments
        var analysisText = transcript.formattedString
        var isViolation = false
        var duration: Double = 0
        var wordCount: Double = 0
        
        onProgress("Processing Audio...")
        
        do {
            let file = try AVAudioFile(forReading: audioFile)
            duration = Double(file.length) / file.processingFormat.sampleRate
        } catch {
             if let last = transcript.segments.last {
                duration = last.timestamp + last.duration
            }
        }
        
        if enforceStrict, let limit = timeLimit {
            if duration > limit {
                isViolation = true
                analysisSegments = transcript.segments.filter { ($0.timestamp + $0.duration) <= limit }
                analysisText = analysisSegments.map { $0.substring }.joined(separator: " ")
                duration = limit
            }
        }
        
        wordCount = Double(analysisSegments.count)

        var wpm: Double = 0
        var pacingScore: Double = 0

        if duration > 1 && wordCount > 0 {
            wpm = (wordCount / duration) * 60.0
            pacingScore = calculatePacingScore(wpm: wpm)
        }

        let vocabulary = calculateVocabulary(text: analysisText)
        let engagement = calculateEngagement(text: analysisText)
        let tone = await calculateTone(audioUrl: audioFile)

        let contextResult = performContextualAnalysis(segments: analysisSegments, text: analysisText)
        let pauseScore = contextResult.pauseScore
        var insights = contextResult.insights

        // ── ML scoring (replaces rule-based scores when a trained model exists) ──
        var mlPrediction: SpeechMLScorer.Prediction? = nil
        if SpeechMLScorer.isAvailable,
           let sfTranscript = transcript as? SFTranscription,
           let features = SpeechFeatureExtractor.extract(
               transcript: sfTranscript,
               audioURL: audioFile,
               duration: duration) {
            onProgress("Running ML scorer…")
            mlPrediction = SpeechMLScorer.predict(features: features)
        }

        let finalPacing     = mlPrediction?.pacing     ?? pacingScore
        let finalVocabulary = mlPrediction?.vocabulary ?? vocabulary
        let finalTone       = mlPrediction?.tone       ?? tone
        let finalEngagement = mlPrediction?.engagement ?? engagement
        let finalPause      = mlPrediction?.pause      ?? pauseScore
        
        var finalOverallScore = 0.0
        let weightedScore: Double
        if let mlOverall = mlPrediction?.overall {
            // Trust the trained overall score directly
            weightedScore = mlOverall
        } else {
            weightedScore = (finalPacing * 0.25) + (finalVocabulary * 0.15) + (finalEngagement * 0.15) + (finalPause * 0.25) + (finalTone * 0.2)
        }
        
        if isViolation {
            finalOverallScore = max(weightedScore - 20, 0)
            insights.append(SpeechInsight(
                title: "Time Limit Exceeded",
                description: "Speech cut off at \(Int(timeLimit ?? 0))s limit.",
                timestamp: timeLimit ?? 0,
                type: .negative
            ))
        } else {
            finalOverallScore = weightedScore
        }
        
        let finalScoreInt = min(max(Int(finalOverallScore), 0), 100)
        
        let metrics = SpeechMetrics(
            overallScore: finalScoreInt,
            pacingScore: finalPacing,
            pacingWPM: wpm,
            vocabularyScore: finalVocabulary,
            toneScore: finalTone,
            engagementScore: finalEngagement,
            pauseScore: finalPause,
            insights: insights
        )
        
        var report = await AIAnalysisManager.shared.performAnalysis(
            transcript: analysisText,
            metrics: metrics,
            onUpdate: onProgress
        )
        
        report.isStrictViolation = isViolation
        report.strictTimeLimit = enforceStrict ? timeLimit : nil
        
        return report
    }
    
    private func performContextualAnalysis(segments: [SFTranscriptionSegment], text: String) -> (insights: [SpeechInsight], pauseScore: Double) {
        var insights: [SpeechInsight] = []
        
        let tagger = NLTagger(tagSchemes: [.tokenType])
        tagger.string = text
        var sentenceRanges: [Range<String.Index>] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .sentence, scheme: .tokenType) { val, range in
            sentenceRanges.append(range)
            return true
        }
        
        var badPauses = 0
        var goodPauses = 0
        
        for i in 0..<(segments.count - 1) {
            let currentSeg = segments[i]
            let nextSeg = segments[i+1]
            let gap = nextSeg.timestamp - (currentSeg.timestamp + currentSeg.duration)
            
            let hasPunctuation = currentSeg.substring.contains { ".,?!:;".contains($0) }
            
            if hasPunctuation {
                if gap >= 0.5 && gap <= 2.5 {
                    goodPauses += 1
                    if gap > 1.0 {
                        insights.append(SpeechInsight(
                            title: "Dramatic Pause",
                            description: "Effective silence (\(String(format: "%.1f", gap))s) used to separate thoughts.",
                            timestamp: currentSeg.timestamp + currentSeg.duration,
                            type: .positive
                        ))
                    }
                } else if gap > 2.5 {
                    insights.append(SpeechInsight(
                        title: "Long Silence",
                        description: "Silence of \(String(format: "%.1f", gap))s broken the flow.",
                        timestamp: currentSeg.timestamp + currentSeg.duration,
                        type: .negative
                    ))
                }
            } else {
                if gap > 0.4 {
                    badPauses += 1
                    insights.append(SpeechInsight(
                        title: "Hesitation",
                        description: "Unnatural pause (\(String(format: "%.1f", gap))s) mid-sentence.",
                        timestamp: currentSeg.timestamp + currentSeg.duration,
                        type: .negative
                    ))
                }
            }
        }
        
        let fillers = ["um", "uh", "like", "literally", "you know"]
        var fillerCount = 0
        for segment in segments {
            let word = segment.substring.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if fillers.contains(word) {
                fillerCount += 1
                insights.append(SpeechInsight(
                    title: "Filler Word",
                    description: "Detected use of '\(word)'.",
                    timestamp: segment.timestamp,
                    type: .neutral
                ))
            }
        }
        
        if segments.count > 5 {
            for i in 0..<(segments.count - 5) {
                let startSeg = segments[i]
                let endSeg = segments[i+4]
                let duration = endSeg.timestamp + endSeg.duration - startSeg.timestamp
                if duration > 0 {
                    let wpm = (5.0 / duration) * 60.0
                    if wpm > 190 {
                         if insights.last?.title != "Rushed Section" || (insights.last?.timestamp ?? -10) < startSeg.timestamp - 2 {
                            insights.append(SpeechInsight(
                                title: "Rushed Section",
                                description: "~ \(Int(wpm)) WPM. Too fast.",
                                timestamp: startSeg.timestamp,
                                type: .negative
                            ))
                        }
                    }
                }
            }
        }
        
        var score = 100.0
        score -= (Double(badPauses) * 5.0)
        score -= (Double(fillerCount) * 3.0)
        score += min(Double(goodPauses) * 2.0, 10.0)
        
        return (insights.sorted { $0.timestamp < $1.timestamp }, min(max(score, 0), 100))
    }
    
    private func calculatePacingScore(wpm: Double) -> Double {
        if wpm >= 130 && wpm <= 160 {
            return 100
        } else if wpm < 130 {
            return max(0, 100 - (130 - wpm) * 0.8)
        } else {
            return max(0, 100 - (wpm - 160) * 1.0)
        }
    }

    private func calculateTone(audioUrl: URL) async -> Double {
        do {
            let file = try AVAudioFile(forReading: audioUrl)
            if file.length == 0 { return 50 }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return 50 }
            
            try file.read(into: buffer)
            
            guard let channelData = buffer.floatChannelData?[0] else { return 50 }
            let frameLength = Int(buffer.frameLength)
            
            var sumSquares: Float = 0
            let step = 100 
            var count = 0
            
            for i in stride(from: 0, to: frameLength, by: step) {
                let sample = channelData[i]
                sumSquares += sample * sample
                count += 1
            }
            
            if count == 0 { return 50 }
            
            let rms = sqrt(sumSquares / Float(count))
            let volumeScore = min(Double(rms) * 500, 100)
            return max(50, min(volumeScore + 40, 100))
            
        } catch {
            print("Audio analysis failed: \(error)")
            return 50
        }
    }
    
    private func calculateVocabulary(text: String) -> Double {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        
        var wordCount = 0.0
        var uniqueWords = Set<String>()
        var complexWords = 0.0
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            let word = String(text[range]).lowercased()
            if tag != .punctuation && tag != .whitespace {
                wordCount += 1
                uniqueWords.insert(word)
                if word.count > 6 { complexWords += 1 }
            }
            return true
        }
        
        if wordCount == 0 { return 0 }
        
        let typeTokenRatio = Double(uniqueWords.count) / wordCount
        let varietyScore = min(typeTokenRatio * 150, 100)
        let complexityBonus = min((complexWords / wordCount) * 200, 20)
        
        return min(varietyScore + complexityBonus, 100)
    }
    
    private func calculateEngagement(text: String) -> Double {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let (sentiment, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        let score = Double(sentiment?.rawValue ?? "0") ?? 0.0
        let intensity = abs(score)
        return min(50 + (intensity * 50 * 2), 100) 
    }
}

extension AVAudioFile {
    var duration: TimeInterval {
        let sampleRate = processingFormat.sampleRate
        guard sampleRate > 0 else { return 0 }
        return Double(length) / sampleRate
    }
}
