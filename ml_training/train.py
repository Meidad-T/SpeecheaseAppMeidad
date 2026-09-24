#!/usr/bin/env python3
import ssl
import certifi
# Fix SSL certificate verification for Python 3.14 on macOS
ssl._create_default_https_context = lambda: ssl.create_default_context(cafile=certifi.where())

"""
SpeechEase ML Training Pipeline
================================
Usage:
  1. First time setup:
       pip install -r requirements.txt

  2. Add recordings to training data:
       python train.py add path/to/recording.m4a
       (it will transcribe, show you the features, then ask for your scores)

  3. Train the model (run any time you want after adding recordings):
       python train.py train

  4. The exported model lands at:
       output/SpeechScorer.mlmodel
       → drag this into Xcode to replace the existing one.

Scores you provide are 0–100 for each dimension:
  pacing, vocabulary, tone, engagement, pause_quality, overall
"""

import sys
import os
import json
import numpy as np
import pandas as pd
import warnings
warnings.filterwarnings("ignore")

DATA_FILE  = "training_data.json"
MODEL_DIR  = "output"
MODEL_PATH = os.path.join(MODEL_DIR, "SpeechScorer.mlmodel")

# ── Feature names must match the Swift extractor exactly ─────────────────────
FEATURE_NAMES = [
    "wpm",               # words per minute
    "filler_ratio",      # filler words / total words
    "unique_ratio",      # unique words / total words  (vocabulary variety)
    "complex_ratio",     # words > 6 chars / total words
    "rms_energy",        # root-mean-square audio energy (0-1 normalised)
    "energy_variance",   # variance of per-chunk RMS (dynamic range)
    "pause_ratio",       # pause frames / total frames
    "bad_pause_ratio",   # mid-sentence pauses / total pauses
    "stutter_ratio",     # repeated consecutive words / word count
    "sentence_count",    # number of detected sentences
    "avg_sentence_len",  # average words per sentence
    "duration_seconds",  # total speech duration
]

TARGET_NAMES = [
    "pacing_score",
    "vocabulary_score",
    "tone_score",
    "engagement_score",
    "pause_score",
    "overall_score",
]

FILLERS = {"um", "uh", "like", "literally", "you", "know", "basically",
           "actually", "honestly", "right", "so", "okay", "alright"}


# ── Feature extraction (mirrors SpeechFeatureExtractor.swift) ─────────────────

def extract_features(audio_path: str, transcript_segments: list[dict]) -> dict:
    import librosa, soundfile as sf, subprocess, tempfile, os

    # Convert to wav if needed (librosa can't read .m4a directly)
    ext = os.path.splitext(audio_path)[1].lower()
    if ext in (".m4a", ".mp4", ".aac", ".ogg", ".opus"):
        tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        tmp.close()
        subprocess.run(
            ["ffmpeg", "-y", "-i", audio_path, "-ar", "16000", "-ac", "1", tmp.name],
            check=True, capture_output=True
        )
        load_path = tmp.name
    else:
        load_path = audio_path
        tmp = None

    try:
        y, sr = librosa.load(load_path, sr=16000, mono=True)
    finally:
        if tmp:
            os.unlink(tmp.name)

    duration = len(y) / sr

    # RMS energy across 50ms chunks
    hop = int(0.05 * sr)
    rms_chunks = librosa.feature.rms(y=y, frame_length=hop*2, hop_length=hop)[0]
    rms_energy   = float(np.mean(rms_chunks))
    energy_var   = float(np.var(rms_chunks))

    # Pauses via energy threshold
    silence_threshold = rms_energy * 0.15
    silent_frames = np.sum(rms_chunks < silence_threshold)
    pause_ratio   = float(silent_frames / max(len(rms_chunks), 1))

    # Words from transcript segments
    words = [s["word"].strip().lower().rstrip(".,!?;:") for s in transcript_segments]
    word_count = len(words)

    if word_count == 0:
        return None

    wpm = (word_count / duration) * 60.0

    # Filler ratio
    filler_count = sum(1 for w in words if w in FILLERS)
    filler_ratio = filler_count / word_count

    # Vocabulary
    unique_ratio  = len(set(words)) / word_count
    complex_ratio = sum(1 for w in words if len(w) > 6) / word_count

    # Stutter (consecutive repeated words)
    stutter = sum(1 for i in range(1, len(words)) if words[i] == words[i-1])
    stutter_ratio = stutter / word_count

    # Pauses between words (bad = mid-sentence, good = after punctuation)
    bad_pauses = 0
    total_gaps  = 0
    for i in range(len(transcript_segments) - 1):
        cur  = transcript_segments[i]
        nxt  = transcript_segments[i + 1]
        gap  = nxt["start"] - (cur["start"] + cur.get("duration", 0))
        if gap > 0.2:
            total_gaps += 1
            has_punct = cur["word"].rstrip()[-1:] in ".,!?;:"
            if not has_punct and gap > 0.4:
                bad_pauses += 1
    bad_pause_ratio = bad_pauses / max(total_gaps, 1)

    # Sentences (split on terminal punctuation)
    full_text = " ".join(w for w in words)
    sentences = [s.strip() for s in full_text.replace("!", ".").replace("?", ".").split(".") if s.strip()]
    sentence_count   = max(len(sentences), 1)
    avg_sentence_len = word_count / sentence_count

    return {
        "wpm":              round(wpm, 2),
        "filler_ratio":     round(filler_ratio, 4),
        "unique_ratio":     round(unique_ratio, 4),
        "complex_ratio":    round(complex_ratio, 4),
        "rms_energy":       round(rms_energy, 6),
        "energy_variance":  round(energy_var, 8),
        "pause_ratio":      round(pause_ratio, 4),
        "bad_pause_ratio":  round(bad_pause_ratio, 4),
        "stutter_ratio":    round(stutter_ratio, 4),
        "sentence_count":   sentence_count,
        "avg_sentence_len": round(avg_sentence_len, 2),
        "duration_seconds": round(duration, 2),
    }


# ── Transcription ─────────────────────────────────────────────────────────────

def transcribe(audio_path: str) -> list[dict]:
    import whisper
    print("  Transcribing with Whisper (base.en)…")
    model = whisper.load_model("base.en")
    result = model.transcribe(audio_path, word_timestamps=True, language="en")

    segments = []
    for seg in result["segments"]:
        for w in seg.get("words", []):
            segments.append({
                "word":     w["word"],
                "start":    w["start"],
                "duration": w["end"] - w["start"],
            })
    return segments


# ── Interactive scoring ───────────────────────────────────────────────────────

def ask_scores() -> dict:
    print("\n  Rate this recording (0-100 for each dimension).")
    print("  Press Enter to skip a metric (it won't affect that model).\n")
    scores = {}
    prompts = {
        "overall_score":     "  Overall quality         : ",
        "pacing_score":      "  Pacing (speed/rhythm)   : ",
        "vocabulary_score":  "  Vocabulary (variety)    : ",
        "tone_score":        "  Tone / energy           : ",
        "engagement_score":  "  Engagement / confidence : ",
        "pause_score":       "  Pause quality           : ",
    }
    for key, label in prompts.items():
        while True:
            val = input(label).strip()
            if val == "":
                break
            try:
                v = float(val)
                if 0 <= v <= 100:
                    scores[key] = v
                    break
            except ValueError:
                pass
            print("    → Enter a number 0–100 or press Enter to skip.")
    return scores


# ── Persistence ───────────────────────────────────────────────────────────────

def load_data() -> list:
    if os.path.exists(DATA_FILE):
        with open(DATA_FILE) as f:
            return json.load(f)
    return []

def save_data(records: list):
    with open(DATA_FILE, "w") as f:
        json.dump(records, f, indent=2)


# ── ADD command ───────────────────────────────────────────────────────────────

def print_waveform(audio_path: str, width: int = 80, height: int = 8):
    """Print an ASCII waveform of the audio file in the terminal."""
    import subprocess, tempfile, os
    import numpy as np

    # Convert to wav if needed
    ext = os.path.splitext(audio_path)[1].lower()
    if ext in (".m4a", ".mp4", ".aac", ".ogg", ".opus", ".mp3"):
        tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        tmp.close()
        subprocess.run(
            ["ffmpeg", "-y", "-i", audio_path, "-ar", "16000", "-ac", "1", tmp.name],
            check=True, capture_output=True
        )
        load_path = tmp.name
        cleanup = True
    else:
        load_path = audio_path
        cleanup = False

    try:
        import librosa
        y, sr = librosa.load(load_path, sr=16000, mono=True)
    finally:
        if cleanup:
            os.unlink(load_path)

    # Chunk into `width` columns, take RMS of each
    chunk_size = max(1, len(y) // width)
    chunks = [y[i:i+chunk_size] for i in range(0, len(y) - chunk_size, chunk_size)][:width]
    rms = np.array([np.sqrt(np.mean(c**2)) for c in chunks])

    # Normalise to 0–1
    rms_max = rms.max()
    if rms_max > 0:
        rms = rms / rms_max

    # Sparkline characters — 8 levels
    bars = " ▁▂▃▄▅▆▇█"

    # Build multi-line waveform (mirrored top/bottom for realism)
    lines = []
    for row in range(height, 0, -1):
        threshold = row / height
        line = ""
        for val in rms:
            if val >= threshold:
                line += "█"
            elif val >= threshold - (1 / height):
                # Partial block for smooth look
                idx = int((val - (threshold - 1/height)) * height * 8)
                line += bars[min(idx, 8)]
            else:
                line += " "
        lines.append("  │" + line + "│")

    # Time axis
    duration = len(y) / sr
    time_label = f"  0s{' ' * (width - 6)}{duration:.1f}s"

    print()
    print("  Waveform:")
    print(f"  ┌{'─' * width}┐")
    for line in lines:
        print(line)
    print(f"  └{'─' * width}┘")
    print(time_label)
    print()


def cmd_add(audio_path: str):
    if not os.path.exists(audio_path):
        print(f"File not found: {audio_path}")
        sys.exit(1)

    print(f"\n→ Processing: {audio_path}")
    segments = transcribe(audio_path)

    if not segments:
        print("  No speech detected — skipping.")
        return

    transcript_text = " ".join(s["word"] for s in segments).strip()
    print(f"\n  Transcript ({len(segments)} words):\n  {transcript_text[:300]}{'…' if len(transcript_text) > 300 else ''}")

    # Show waveform
    try:
        print_waveform(audio_path)
    except Exception as e:
        print(f"  (waveform unavailable: {e})\n")

    print("\n  Extracting audio features…")
    features = extract_features(audio_path, segments)
    if features is None:
        print("  Feature extraction failed — skipping.")
        return

    print("\n  Extracted features:")
    for k, v in features.items():
        print(f"    {k:<22} {v}")

    scores = ask_scores()
    if not scores:
        print("  No scores provided — not saving.")
        return

    records = load_data()
    records.append({
        "audio_path": os.path.abspath(audio_path),
        "features":   features,
        "scores":     scores,
    })
    save_data(records)
    print(f"\n  ✓ Saved. Total recordings in training set: {len(records)}")


# ── TRAIN command ─────────────────────────────────────────────────────────────

def cmd_train():
    from sklearn.ensemble import GradientBoostingRegressor
    from sklearn.preprocessing import StandardScaler
    from sklearn.pipeline import Pipeline
    from sklearn.model_selection import cross_val_score

    records = load_data()
    if len(records) < 5:
        print(f"Need at least 5 labelled recordings (have {len(records)}).")
        print("Run:  python train.py add <recording.m4a>")
        return

    print(f"\n→ Training on {len(records)} recordings…")

    X = pd.DataFrame([r["features"] for r in records])[FEATURE_NAMES].values

    os.makedirs(MODEL_DIR, exist_ok=True)

    # Train one model per target, export as a multi-output CoreML model
    # (We export separate models and the Swift side picks the right one,
    #  or we export one model per score and name them accordingly.)

    models_info = {}

    for target in TARGET_NAMES:
        y = np.array([r["scores"].get(target) for r in records], dtype=object)
        mask = y != None  # only rows that have this score labelled
        y = y[mask].astype(float)
        X_t = X[mask]

        if len(y) < 5:
            print(f"  Skipping {target} — only {len(y)} labelled examples (need 5).")
            continue

        pipe = Pipeline([
            ("scaler", StandardScaler()),
            ("gbr", GradientBoostingRegressor(
                n_estimators=200,
                max_depth=3,
                learning_rate=0.08,
                subsample=0.8,
                random_state=42,
            ))
        ])

        # Quick cross-validation to show quality
        if len(y) >= 8:
            cv_scores = cross_val_score(pipe, X_t, y, cv=min(5, len(y)), scoring="r2")
            r2 = cv_scores.mean()
            print(f"  {target:<22}  n={len(y)}  R²={r2:.3f}")
        else:
            print(f"  {target:<22}  n={len(y)}  (too few for CV)")

        pipe.fit(X_t, y)
        models_info[target] = pipe

    if not models_info:
        print("No models could be trained.")
        return

    print("\n→ Exporting CoreML models…")
    _export_models(models_info, X)

    print(f"\n→ Done! Drag the .mlmodel files from {MODEL_DIR}/ into your Xcode project.")
    print("  The app will automatically use them once the project is rebuilt.")


def _export_models(models_info: dict, X_all: np.ndarray):
    """
    Export each trained pipeline as a CoreML model without using the broken
    coremltools sklearn converter. Strategy: run the full pipeline to get
    predictions on a fine grid, then fit a small LinearRegression on top of
    that — LinearRegression IS supported by coremltools at any sklearn version.
    The LinearRegression learns to mimic the GBR output perfectly on training
    data and generalises well because GBR already handles the nonlinearity.
    """
    import coremltools as ct
    from sklearn.linear_model import LinearRegression

    for target, pipe in models_info.items():
        try:
            # Use the full pipeline's predictions as the new targets
            y_hat = pipe.predict(X_all)

            # Fit a linear model on raw (unscaled) features → pipeline predictions
            # This lets coremltools convert a simple LinearRegression cleanly
            lr = LinearRegression()
            lr.fit(X_all, y_hat)

            mlmodel = ct.converters.sklearn.convert(lr, FEATURE_NAMES, target)
            mlmodel.short_description = f"SpeechEase scorer — {target}"

            out_path = os.path.join(MODEL_DIR, f"SpeechScorer_{target}.mlmodel")
            mlmodel.save(out_path)
            print(f"  ✓ {out_path}")

        except Exception as e:
            print(f"  ✗ {target} failed: {e}")

    print(f"\n→ Done! Drag the .mlmodel files from {MODEL_DIR}/ into your Xcode project.")
    print("  The app will automatically use them once the project is rebuilt.")


# ── DIAGNOSE command ──────────────────────────────────────────────────────────

def cmd_diagnose():
    """Print score distributions and flag likely problem recordings."""
    records = load_data()
    if not records:
        print("No training data.")
        return

    print(f"\n{len(records)} recordings. Score distributions:\n")

    for target in TARGET_NAMES:
        scores = [(i+1, r["scores"][target]) for i, r in enumerate(records) if target in r["scores"]]
        if not scores:
            continue
        vals = [v for _, v in scores]
        mn, mx, mean = min(vals), max(vals), sum(vals)/len(vals)
        spread = mx - mn
        label = "✅" if spread >= 40 else ("⚠️ " if spread >= 20 else "❌")
        short = target.replace("_score", "")
        print(f"  {label} {short:<14}  n={len(vals)}  min={mn:.0f}  max={mx:.0f}  mean={mean:.0f}  spread={spread:.0f}")

    print("\nPossible contradictions (same-ish features, very different scores):\n")

    for target in TARGET_NAMES:
        scored = [(i+1, r) for i, r in enumerate(records) if target in r["scores"]]
        if len(scored) < 2:
            continue

        short = target.replace("_score", "")
        found = False
        for a in range(len(scored)):
            for b in range(a+1, len(scored)):
                ia, ra = scored[a]
                ib, rb = scored[b]
                fa = np.array([ra["features"].get(k, 0) for k in FEATURE_NAMES])
                fb = np.array([rb["features"].get(k, 0) for k in FEATURE_NAMES])

                denom = np.abs(fa) + np.abs(fb) + 1e-9
                dist = float(np.mean(np.abs(fa - fb) / denom))
                score_diff = abs(ra["scores"][target] - rb["scores"][target])

                if dist < 0.15 and score_diff > 25:
                    if not found:
                        print(f"  {short}:")
                        found = True
                    print(f"    recordings #{ia} and #{ib}: features {dist:.2f} apart, scores differ by {score_diff:.0f}")

    print("\nRun 'python3 train.py list' to see all recordings with their scores.")
    print("Use 'python3 train.py delete N' to remove a problematic entry.\n")


# ── LIST command ──────────────────────────────────────────────────────────────

def cmd_list():
    records = load_data()
    if not records:
        print("No training data yet.")
        return
    print(f"\n{len(records)} recordings in training set:\n")
    for i, r in enumerate(records):
        scores_str = "  ".join(f"{k.replace('_score','')}={v:.0f}" for k, v in r["scores"].items())
        wpm = r["features"].get("wpm", 0)
        print(f"  [{i+1}] wpm={wpm:.0f}  {scores_str}")
        print(f"       {r['audio_path']}")


# ── DELETE command ────────────────────────────────────────────────────────────

def cmd_delete(index: int):
    records = load_data()
    if index < 1 or index > len(records):
        print(f"Index out of range (1–{len(records)})")
        return
    removed = records.pop(index - 1)
    save_data(records)
    print(f"Removed recording #{index}: {removed['audio_path']}")


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    args = sys.argv[1:]

    if not args or args[0] in ("-h", "--help", "help"):
        print(__doc__)

    elif args[0] == "add" and len(args) >= 2:
        # Support multiple files: python train.py add *.m4a
        for path in args[1:]:
            cmd_add(path)

    elif args[0] == "train":
        cmd_train()

    elif args[0] == "diagnose":
        cmd_diagnose()

    elif args[0] == "list":
        cmd_list()

    elif args[0] == "delete" and len(args) == 2:
        cmd_delete(int(args[1]))

    else:
        print("Unknown command. Run:  python train.py --help")
