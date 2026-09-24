# SpeechEase ML Training Pipeline

## How it works

```
Your recordings + your scores  →  Python training  →  .mlmodel  →  drag into Xcode  →  better analysis
```

The app extracts **12 audio + transcript features** from every recording.
The Python pipeline trains a **Gradient Boosting** regressor on those same 12 features
mapped to the scores *you* give. The more you add, the better it gets.

---

## First-time setup (Mac)

```bash
cd ml_training
pip install -r requirements.txt
```

Whisper's `base.en` model (~140 MB) downloads automatically on first use.

---

## Workflow

### 1 — Add a recording

```bash
python train.py add path/to/recording.m4a
```

It will:
1. Transcribe the audio with Whisper
2. Print the extracted features so you can see what it saw
3. Ask you to rate it 0–100 on each dimension (press Enter to skip any)

You can add multiple files at once:
```bash
python train.py add recordings/*.m4a
```

### 2 — Check what you have

```bash
python train.py list
```

### 3 — Train and export

```bash
python train.py train
```

Needs **at least 5 labelled recordings per dimension**.
Prints cross-validation R² so you can see how well each model fits.
Exports `.mlmodel` files to `output/`.

### 4 — Add the models to Xcode

Drag every `.mlmodel` from `output/` into the **SpeechEaseApp** Xcode target:
- File → Add Files to "SpeechEaseApp"
- Check "Copy items if needed" and the app target

Rebuild and run. The app prints nothing different, but scores are now your model's predictions
whenever an `.mlmodel` is found in the bundle. Without the files, it silently falls back to the
original rule-based scores.

### 5 — Delete a bad entry

```bash
python train.py list        # find the index
python train.py delete 3    # remove entry #3
```

---

## The 12 features

| Feature | What it measures |
|---|---|
| `wpm` | Words per minute |
| `filler_ratio` | um / uh / like / basically … per word |
| `unique_ratio` | Vocabulary variety (unique words / total) |
| `complex_ratio` | Words > 6 characters (sophistication) |
| `rms_energy` | Mean loudness (0–1) |
| `energy_variance` | Dynamic range — does volume change? |
| `pause_ratio` | Fraction of audio that is silence |
| `bad_pause_ratio` | Mid-sentence hesitation pauses |
| `stutter_ratio` | Consecutive repeated words |
| `sentence_count` | How many sentences |
| `avg_sentence_len` | Words per sentence |
| `duration_seconds` | Total speech length |

---

## Tips for good training data

- **Variety matters more than volume.** 20 diverse recordings beat 100 similar ones.
- Score honestly. A 95 should feel noticeably better than a 60.
- Include deliberate "bad" examples: rambling, fast, filled with "um", monotone.
- Once you have ~30+ recordings the model generalises well.
- Re-run `python train.py train` any time — it retrains from scratch on everything.
