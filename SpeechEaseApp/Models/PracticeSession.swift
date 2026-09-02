import SwiftUI

enum PracticeFocus: String, CaseIterable, Codable, Identifiable {
    case vocal
    case body
    case interview
    case pacing
    case facial
    case vocab
    case eye
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .vocal: return "Vocal Control"
        case .body: return "Body Language"
        case .interview: return "Interview Prep"
        case .pacing: return "Pacing"
        case .facial: return "Facial Aesthetics"
        case .vocab: return "Vocabulary"
        case .eye: return "Eye Contact"
        }
    }
    
    var subtitle: String {
        switch self {
        case .vocal: return "Pitch & Tone"
        case .body: return "Posture & Gestures"
        case .interview: return "Q&A Strategies"
        case .pacing: return "Speed & Pauses"
        case .facial: return "Expressions"
        case .vocab: return "Word Choice"
        case .eye: return "Engagement"
        }
    }
    
    var icon: String {
        switch self {
        case .vocal: return "mic.fill"
        case .body: return "figure.stand"
        case .interview: return "briefcase.fill"
        case .pacing: return "speedometer"
        case .facial: return "mouth"
        case .vocab: return "text.book.closed.fill"
        case .eye: return "eye.fill"
        }
    }
    
    var requiresVideo: Bool {
        switch self {
        case .body, .facial, .eye, .interview:
            return true
        case .vocal, .pacing, .vocab:
            return false
        }
    }
    
    var defaultColor: Color {
        switch self {
        case .vocal: return .green
        case .body: return .blue
        case .interview: return .orange
        case .pacing: return .pink
        case .facial: return .purple
        case .vocab: return .yellow
        case .eye: return .teal
        }
    }
    
    var description: String {
        switch self {
        case .vocal:
            return """
            Mastering vocal control is the foundation of powerful communication. It's not just about what you say, but how you say it. By learning to modulate your pitch, you can keep listeners engaged and emphasize key points effectively, avoiding the monotony that causes audiences to tune out.
            
            Proper tone conveys emotion and intent. Whether you need to sound authoritative, empathetic, or enthusiastic, your voice is the instrument that delivers that message. Regular practice in this area helps you find your natural resonance and project confidence in any setting.
            """
        case .body:
            return """
            Body language speaks before you say a word. Your posture, gestures, and overall physical presence communicate confidence, openness, and authority. A strong stance can make you feel more powerful, while appropriate hand gestures can help illustrate your ideas and make your storytelling more dynamic.
            
            Understanding body language also helps you read the room. By being aware of non-verbal cues, you can adjust your delivery to better connect with your audience. This section focuses on eliminating nervous tics and cultivating a presence that commands respect and attention.
            """
        case .interview:
            return """
            Interviews are high-stakes conversations where preparation is key. This isn't just about memorizing answers, but about developing the ability to think on your feet and structure your thoughts logically under pressure.
            
            We focus on the STAR method (Situation, Task, Action, Result) to tell compelling stories about your achievements. You'll also learn how to handle difficult questions with grace and turn potential weaknesses into opportunities to demonstrate learning and growth.
            """
        case .pacing:
            return """
            The speed at which you speak significantly impacts comprehension. Speak too fast, and your audience leads; speak too slow, and they lose interest. Mastering pacing involves finding a comfortable rhythm that allows your listeners to absorb your message.
            
            Strategic pauses are a superpower in public speaking. They give your audience time to reflect on a powerful statement and give you a moment to collect your next thought. This section trains you to use silence as effectively as you use words.
            """
        case .facial:
            return """
            Your face is the primary focal point for your audience. Micro-expressions can reveal nervousness or uncertainty even if your voice is steady. Learning to control your facial expressions ensures that your visual cues align with your verbal message.
            
            A genuine smile or a furrowed brow can drastically change the meaning of a sentence. We work on developing an expressive range that feels authentic to you, helping you connect emotionally with your listeners and appear more approachable and trustworthy.
            """
        case .vocab:
            return """
            A rich vocabulary allows you to express complex ideas with precision and clarity. It’s not about using big words to sound smart, but about choosing the *right* word to paint a vivid picture in your listener's mind.
            
            This section helps you expand your active vocabulary and eliminate filler words like "um," "like," and "you know" that dilute your message. You will learn to speak more concisely and persuasively, ensuring every word earns its place in your sentence.
            """
        case .eye:
            return """
            Eye contact is the strongest way to build a connection with your audience. It signals honesty, confidence, and interest. Avoiding eye contact can make you appear shifty or insecure, while staring can be aggressive.
            
            The goal is to maintain natural, engaging eye contact that makes every person in the room feel like you are speaking directly to them. We practice techniques to scan the room effectively and hold gaze just long enough to establish a bond without making it uncomfortable.
            """
        }
    }
    
    var highlightTitle: String {
        switch self {
        case .vocal: return "The Power of Pause"
        case .body: return "Power Posing"
        case .interview: return "The STAR Method"
        case .pacing: return "The 3-Second Rule"
        case .facial: return "The Duchenne Smile"
        case .vocab: return "Rule of Three"
        case .eye: return "The Lighthouse Technique"
        }
    }
    
    var highlightDescription: String {
        switch self {
        case .vocal: return "Silence is loud. Use it to let big ideas land."
        case .body: return "Stand like a superhero for 2 mins to boost confidence!"
        case .interview: return "Situation. Task. Action. Result. Your secret weapon."
        case .pacing: return "Count to three before answering. Own the time."
        case .facial: return "Real smiles reach your eyes. Fake ones don't."
        case .vocab: return "People remember things in threes. Use it."
        case .eye: return "Scan the room like a lighthouse, don't stare."
        }
    }
}

struct SavedColor: Codable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double
    
    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
    
    init(_ color: Color) {
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        self.red = Double(r)
        self.green = Double(g)
        self.blue = Double(b)
        self.opacity = Double(a)
    }
}

// MARK: - Practice History Item
struct PracticeAttempt: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    let date: Date
    let recordingFileName: String
    let speechReport: SpeechReport
    var confidenceScore: Int? // Optional self-rating (0-100)
    var sessionName: String? // Optional name for orphaned history
    
    var score: Int { speechReport.overallScore }
    
    static func == (lhs: PracticeAttempt, rhs: PracticeAttempt) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct PracticeSession: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    private var _focus: PracticeFocus?
    var foci: [PracticeFocus]
    var customIcon: String?   // SF Symbol name chosen by the user
    
    var focus: PracticeFocus {
        get { foci.first ?? .vocal }
        set { foci = [newValue] }
    }
    
    var timeLimitMinutes: Int?
    var enforceTimeLimit: Bool
    var customColor: SavedColor?
    var createdDate: Date? = Date()
    
    var recordingFileName: String?
    var speechReport: SpeechReport?
    
    var history: [PracticeAttempt] = []
    var practiceLog: [Date] = []
    
    var displayColor: Color {
        if let custom = customColor {
            return custom.color
        }
        return foci.first?.defaultColor ?? .blue
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, focus, foci, customIcon, timeLimitMinutes, enforceTimeLimit, customColor, createdDate, recordingFileName, speechReport, practiceLog, history
    }
    
    init(id: UUID = UUID(), name: String, foci: [PracticeFocus], timeLimitMinutes: Int?, enforceTimeLimit: Bool, customColor: SavedColor?, customIcon: String? = nil, createdDate: Date? = Date(), recordingFileName: String? = nil, speechReport: SpeechReport? = nil, practiceLog: [Date] = [], history: [PracticeAttempt] = []) {
        self.id = id
        self.name = name
        self.foci = foci
        self.timeLimitMinutes = timeLimitMinutes
        self.enforceTimeLimit = enforceTimeLimit
        self.customColor = customColor
        self.customIcon = customIcon
        self.createdDate = createdDate
        self.recordingFileName = recordingFileName
        self.speechReport = speechReport
        self.practiceLog = practiceLog
        self.history = history
    }
    
    init(name: String, focus: PracticeFocus, timeLimitMinutes: Int?, enforceTimeLimit: Bool, customColor: SavedColor?) {
        self.init(name: name, foci: [focus], timeLimitMinutes: timeLimitMinutes, enforceTimeLimit: enforceTimeLimit, customColor: customColor)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        timeLimitMinutes = try container.decodeIfPresent(Int.self, forKey: .timeLimitMinutes)
        enforceTimeLimit = try container.decode(Bool.self, forKey: .enforceTimeLimit)
        customColor = try container.decodeIfPresent(SavedColor.self, forKey: .customColor)
        customIcon = try container.decodeIfPresent(String.self, forKey: .customIcon)
        createdDate = try container.decodeIfPresent(Date.self, forKey: .createdDate)
        
        recordingFileName = try container.decodeIfPresent(String.self, forKey: .recordingFileName)
        speechReport = try container.decodeIfPresent(SpeechReport.self, forKey: .speechReport)
        
        practiceLog = try container.decodeIfPresent([Date].self, forKey: .practiceLog) ?? []
        history = try container.decodeIfPresent([PracticeAttempt].self, forKey: .history) ?? []
        
        if let newFoci = try? container.decode([PracticeFocus].self, forKey: .foci) {
            foci = newFoci
        } else if let oldFocus = try? container.decode(PracticeFocus.self, forKey: .focus) {
            foci = [oldFocus]
        } else {
            foci = [.vocal]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(foci, forKey: .foci)
        if let first = foci.first {
             try container.encode(first, forKey: .focus)
        }
        try container.encode(timeLimitMinutes, forKey: .timeLimitMinutes)
        try container.encode(enforceTimeLimit, forKey: .enforceTimeLimit)
        try container.encode(customColor, forKey: .customColor)
        try container.encodeIfPresent(customIcon, forKey: .customIcon)
        try container.encode(createdDate, forKey: .createdDate)
        try container.encode(recordingFileName, forKey: .recordingFileName)
        try container.encode(speechReport, forKey: .speechReport)
        try container.encode(practiceLog, forKey: .practiceLog)
        try container.encode(history, forKey: .history)
    }
}
