import Foundation
import CoreML

/// Runs the trained GradientBoosting models exported by train.py.
/// Falls back gracefully to nil if a model file isn't in the bundle yet.
///
/// Model files to add to Xcode (drag into project, check "Copy if needed"):
///   SpeechScorer_pacing_score.mlmodel
///   SpeechScorer_vocabulary_score.mlmodel
///   SpeechScorer_tone_score.mlmodel
///   SpeechScorer_engagement_score.mlmodel
///   SpeechScorer_pause_score.mlmodel
///   SpeechScorer_overall_score.mlmodel
struct SpeechMLScorer {

    // Cached model instances (nil until a model file is present in the bundle)
    private static var pacingModel:     MLModel? = loadModel("SpeechScorer_pacing_score")
    private static var vocabularyModel: MLModel? = loadModel("SpeechScorer_vocabulary_score")
    private static var toneModel:       MLModel? = loadModel("SpeechScorer_tone_score")
    private static var engagementModel: MLModel? = loadModel("SpeechScorer_engagement_score")
    private static var pauseModel:      MLModel? = loadModel("SpeechScorer_pause_score")
    private static var overallModel:    MLModel? = loadModel("SpeechScorer_overall_score")

    /// Returns true when at least the overall model is loaded.
    static var isAvailable: Bool { overallModel != nil }

    struct Prediction {
        var pacing:     Double?
        var vocabulary: Double?
        var tone:       Double?
        var engagement: Double?
        var pause:      Double?
        var overall:    Double?
    }

    static func predict(features: SpeechFeatureExtractor.Features) -> Prediction {
        var p = Prediction()
        let input = featureProvider(features.array)

        p.pacing     = run(pacingModel,     input: input)
        p.vocabulary = run(vocabularyModel, input: input)
        p.tone       = run(toneModel,       input: input)
        p.engagement = run(engagementModel, input: input)
        p.pause      = run(pauseModel,      input: input)
        p.overall    = run(overallModel,    input: input)

        return p
    }

    // MARK: - Private helpers

    private static func loadModel(_ name: String) -> MLModel? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc")
                     ?? Bundle.main.url(forResource: name, withExtension: "mlmodel")
        else { return nil }
        return try? MLModel(contentsOf: url)
    }

    private static func featureProvider(_ values: [Double]) -> MLDictionaryFeatureProvider? {
        let featureNames = [
            "wpm", "filler_ratio", "unique_ratio", "complex_ratio",
            "rms_energy", "energy_variance", "pause_ratio", "bad_pause_ratio",
            "stutter_ratio", "sentence_count", "avg_sentence_len", "duration_seconds"
        ]
        var dict: [String: MLFeatureValue] = [:]
        for (name, val) in zip(featureNames, values) {
            dict[name] = MLFeatureValue(double: val)
        }
        return try? MLDictionaryFeatureProvider(dictionary: dict)
    }

    private static func run(_ model: MLModel?, input: MLFeatureProvider?) -> Double? {
        guard let model, let input else { return nil }
        guard let out = try? model.prediction(from: input) else { return nil }
        // The output feature name matches the target name used during training
        for name in out.featureNames {
            let v = out.featureValue(for: name)?.doubleValue ?? 0
            return min(max(v, 0), 100)
        }
        return nil
    }
}
