# SpeechEase 🦜

SpeechEase is an AI-powered conversational partner and speech coaching companion designed to help users prepare for interviews, public speaking, and daily presentations. It delivers a real-time, low-latency conversational experience with diagnostic feedback.

---

## 🎨 Design Vision & Brand Identity

* **UI Style**: Inspired by the conversational flow and feel of **Gemini Live**, tailored for native iOS.
* **Color Palette**: Modern, high-contrast, premium interface highlighting **vibrant oranges and warm yellows**.
* **Mascot**: An orange parrot (the master of vocal speech and mimicry) guiding the user through the learning journey.

---

## 🚀 Core Features

### 1. Learn Journey (Duolingo-Style Path) 🛣️
Selecting any speech topic (e.g., Vocal Variety, Body Language) opens an interactive, step-by-step learning path. Users progress sequentially through lessons, unlocking milestones, quizzes, and exercises.

#### Design Inspiration:
![Duolingo Learn Path Inspo](Docs/Assets/duolingo_path.png)

---

### 2. Metrics & Gamification Bar 🏆
The top of the dashboard displays core user performance statistics at a glance, motivating daily practice:
* **Streak**: Consecutive days practiced.
* **Speech Score**: Aggregated indicator of fluency, pitch control, and confidence.
* **Hearts/Lives**: Progression gating metrics.

#### Design Inspiration:
![Metrics Bar Inspo](Docs/Assets/metrics_bar.png)

---

### 3. Gemini Live Practice Arena 🎙️
An interactive practice environment where users configure custom mock interviews and presentations:
* **Custom Roles**: Choose or define target professions/scenarios (e.g., iOS Engineer, Product Manager, Keynote Speaker).
* **Question Limits**: Set the number of interview prompts.
* **Gemini Dialogues**: Gemini asks questions, listens to speech input, handles interrupts, and dynamically chooses to either ask follow-up questions or proceed.
* **Hiring Likelihood Score**: Post-interview analysis providing an objective percentage indicating recruitment likelihood along with speech metrics and suggestions.

---

## 🤖 ML Speech Scoring (Training Pipeline)

The app ships with a trainable ML scoring system. Instead of fixed rule-based scores, you can train a personal model on your own recordings and it learns *your* definition of good speech.

### How it works
- **Mac**: Python script (`ml_training/train.py`) uses Whisper to transcribe recordings, extracts 12 audio/transcript features, and trains a GradientBoosting model on scores you provide.
- **iPhone**: The exported `.mlmodel` files are bundled in Xcode. The app automatically uses them for scoring — and falls back to rule-based scores if no model is present.

### Full instructions
See **[`ml_training/README.md`](ml_training/README.md)** for the complete step-by-step guide.

### Quick reference (run from `ml_training/` folder)

```bash
# One-time setup
pip3 install -r requirements.txt
brew install ffmpeg

# Add a recording + score it interactively (repeat as many times as you want)
python3 train.py add /path/to/recording.m4a

# See all recordings in your training set
python3 train.py list

# Train the model (needs 5+ recordings per metric)
python3 train.py train

# → Drag output/*.mlmodel into Xcode, rebuild the app
```

### Notes
- All training data is stored in `ml_training/training_data.json` — it accumulates across sessions.
- Each `train` run retrains from scratch on *all* data, so adding more recordings and retraining always produces a better model.
- Recordings score 6 dimensions independently: **pacing, vocabulary, tone, engagement, pause quality, overall**. You can skip any you don't want to rate.
- The `.mlmodel` files in Xcode are replaced (not stacked) each time — just overwrite them and rebuild.

---



To keep code clean and scalable, files are divided by function:
* `Models/`: Standard data models and schemas (e.g., `LearnTopic.swift`).
* `UIComponents/`: Reusable interface objects (e.g., `ProgressRing.swift`).
* `Features/`: Scope-specific components grouped by app features:
  * `Features/Learn/`: Files related to lessons and paths (`LearnView.swift`, `LearnTopicCard.swift`, `TopicDetailView.swift`).
  * `Features/Practice/`: Real-time voice and role interaction views.
  * `Features/Progress/`: Analytics and performance summaries.
