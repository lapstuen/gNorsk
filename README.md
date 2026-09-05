# gThai - Thai Language Learning App

A comprehensive iOS/iPadOS/macOS application for learning Thai language with advanced syllable segmentation, IPA transcription, and spaced repetition learning.

## Features

### 🇹🇭 Thai Language Processing
- **Advanced Syllable Segmentation** - Automatic Thai word breakdown into syllables
- **IPA Transcription** - Phonetic transcription for accurate pronunciation
- **Tone Analysis** - Thai tone rule implementation with visual indicators
- **Color-Coded Consonants** - Visual learning aid with consonant class colors

### 📚 Vocabulary Management
- **Flexible Organization** - Group words by topic, difficulty, or frequency
- **Frequency-Based Learning** - Learn high-frequency words first (1-5000 rank)
- **Rich Metadata** - Images, example sentences, notes, and tags
- **CloudKit Sync** - Automatic sync across all your Apple devices

### 🎓 Smart Learning System
- **Spaced Repetition** - Scientifically-proven review scheduling
- **Adaptive Difficulty** - Learns from your performance
- **Exercise Mode** - Focused practice with only due words
- **Progress Tracking** - Monitor your learning journey

### 🔍 Powerful Search
- **Multi-Mode Search** - Thai text, English, IPA, or tags
- **Search History** - Quick access to recent searches
- **Instant Results** - Fast Core Data queries

### 📱 Universal App
- **iPhone** - Optimized portrait interface
- **iPad** - Full-featured tablet experience
- **macOS** - Mac Catalyst support with proper window sizing

## Screenshots

[Add screenshots here]

## Requirements

- **iOS:** 17.0 or later
- **iPadOS:** 17.0 or later
- **macOS:** 14.0 or later (Mac Catalyst)
- **Xcode:** 15.0 or later (for development)

## Installation

### From Source

1. **Clone the repository:**
   ```bash
   git clone [repository-url]
   cd gThai
   ```

2. **Open in Xcode:**
   ```bash
   open gThai.xcodeproj
   ```

3. **Build and run:**
   - Select target device (iPhone/iPad/Mac)
   - Press `Cmd+R` or click the Run button

### Build from Command Line

```bash
# iOS/iPadOS
xcodebuild -project gThai.xcodeproj -scheme gThai -configuration Debug build

# macOS (Mac Catalyst)
xcodebuild -project gThai.xcodeproj -scheme gThai \
  -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build

# Run tests
xcodebuild test -project gThai.xcodeproj -scheme gThai \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Quick Start Guide

### Creating Your First Word

1. Launch gThai
2. Tap **"Add new word"**
3. Enter Thai text (e.g., "สวัสดี")
4. Add English translation ("Hello")
5. Save - IPA and syllable analysis generated automatically!

### Organizing with Groups

1. Open hamburger menu (☰)
2. Select **"Groups"**
3. Create new group or select existing
4. All new words are added to the current group

### Learning with Exercise Mode

1. Tap **"Exercise"** on main screen
2. Only due words are shown
3. Tap a word to practice
4. Rate your confidence: Again / Hard / Good / Easy
5. Word is rescheduled based on your answer

### Review Schedule

1. Tap **"Review Due"** to see upcoming reviews
2. Words are sorted by due date
3. Green = due now, Yellow = due soon

## Project Structure

```
gThai/
├── MainViews/              # Core navigation screens
├── SwiftUI/
│   ├── Components/         # Reusable UI components
│   ├── Views/              # Feature-specific views
│   └── ThaiAlphaModule/    # Thai alphabet teaching
├── Globale/
│   └── Syllable/           # Thai NLP engine (segmentation, IPA, tones)
├── CoreData/               # Data model & persistence
├── Div/                    # Utilities (AppState, Search, etc.)
├── SwiftGeneral/           # Helper functions
└── Resources/              # Assets & resources
```

## Architecture

### Technology Stack
- **UI:** SwiftUI with `@Observable` state management
- **Data:** Core Data with `NSPersistentCloudKitContainer`
- **Thai NLP:** Custom syllable segmentation engine
- **Platforms:** Universal iOS/iPadOS/macOS

### Key Components

**AppState** - Global state management with `@Observable`
```swift
@Observable class AppState {
    var valgtGruppeId: Int16           // Selected group
    var visAlleDetaljer: Bool          // Exercise mode toggle
    var sessionResults: [UUID: Bool]   // Learning session tracking
}
```

**ThaiWords Entity** - Core vocabulary model
- Thai text, English translation, IPA transcription
- Learning state (new/learning/reviewing)
- Spaced repetition fields (dueAt, repetitions, easiness)
- Metadata (group, tags, notes, images)

**Thai Segmentation Engine**
- Input: Thai text → Output: Array of syllables
- Each syllable: onset, nucleus, coda, IPA, tone mark
- Tone rules based on consonant class, vowel length, tone mark

## Development

### For Developers

See **[CLAUDE.md](./CLAUDE.md)** for comprehensive development documentation including:
- Detailed architecture overview
- Core Data model reference
- Thai NLP engine internals
- SwiftUI component library
- Development conventions
- Testing strategy

### For UI Changes

**IMPORTANT:** Read **[GUIDE_SHEETS_AND_MODALS.md](./GUIDE_SHEETS_AND_MODALS.md)** before creating any sheets or modals. This guide contains critical platform-specific sizing requirements.

### Running Tests

```bash
# All tests
xcodebuild test -project gThai.xcodeproj -scheme gThai \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# Specific test plan
xcodebuild test -project gThai.xcodeproj -testPlan gThaiTestPlan
```

### Code Style

- **Naming:** Mix of Norwegian and English (historical)
- **State Management:** Prefer `@Observable` over `@StateObject`
- **Views:** SwiftUI for all new code
- **Components:** Reusable components in `SwiftUI/Components/`

## Thai Language Processing

### Syllable Segmentation

The app includes a sophisticated Thai syllable segmentation engine:

```swift
let segmenter = ThaiSeg()
let syllables = segmenter.segment(text: "สวัสดี")

// Result:
// Syllable 1: ส-วะ (sà, Low tone)
// Syllable 2: ด-ี (diː, Mid tone)
```

### IPA Strategy: Why Syllable-Level?

**Important Design Decision:**

After extensive development using advanced AI models, we determined that **automatic word-level IPA transcription for Thai is extremely challenging** due to:
- Complex tone sandhi and contextual pronunciation changes
- Dialectal variations and connected speech rules
- The need for years of linguistic research

**Our Solution:**

gThai focuses on **syllable-level IPA transcription**, which is:
- ✅ **Reliable** - Consistent and accurate per syllable
- ✅ **Educational** - Helps learners understand pronunciation building blocks
- ✅ **Practical** - Combined with multiple TTS engines for actual listening

**In the App:**

When viewing a word like "อาหารทะเล" (seafood):
1. **Syllable breakdown** shows: ["อา", "หาร", "ทะ", "เล"]
2. **Info buttons (i)** on each syllable reveal its IPA transcription
3. **TTS buttons** (Narisa, Kanya, Google, etc.) let you hear the pronunciation
4. **Syllable details** show tone, consonant class, and phonetic structure

This approach provides both visual learning (syllable IPA) and audio learning (TTS), making it more effective than attempting unreliable word-level automatic transcription.

### IPA Transcription (Per Syllable)

Automatic per-syllable IPA generation using:
- Consonant class mapping (MID/HIGH/LOW)
- Vowel pattern recognition
- Tone mark interpretation
- Live/dead syllable detection

### Tone Rules

Implements complete Thai tone rules:
- 5 tones: Mid, Low, Falling, High, Rising
- Based on: consonant class + vowel length + tone mark + syllable type
- Visual indicators in UI

## Data Model

### ThaiWords Entity

| Field | Type | Purpose |
|-------|------|---------|
| `thaiWord` | String | Thai text |
| `englishWord` | String | English translation |
| `ipa` | String? | IPA transcription |
| `learningState` | Int16 | 0=new, 1=learning, 2=reviewing |
| `dueAt` | Date? | Next review date |
| `easiness` | Double | Difficulty factor (1.3-2.5) |
| `groupId` | Int16 | Group assignment |

### Group Entity

| Field | Type | Purpose |
|-------|------|---------|
| `groupId` | Int16 | Numeric ID |
| `groupName` | String | Display name |
| `groupType` | Int16 | Normal, frequency, etc. |
| `frequencyFrom` | Int32 | Frequency range start |
| `frequencyTo` | Int32 | Frequency range end |

## Spaced Repetition Algorithm

The app uses a modified SM-2 algorithm:

1. **New words** - `learningState = 0`, no dueAt
2. **Learning** - `learningState = 1`, short intervals (10min, 1day)
3. **Reviewing** - `learningState = 2`, exponential intervals

**Review Ratings:**
- **Again** (0) - Restart learning, dueAt = now + 10min
- **Hard** (1) - Decrease easiness, dueAt = interval × 0.5
- **Good** (2) - Keep easiness, dueAt = interval × 1.0
- **Easy** (3) - Increase easiness, dueAt = interval × 1.5

**Easiness Factor:**
- Range: 1.3 to 2.5
- Adjusts based on performance
- Personalizes review intervals

## Contributing

[Add contribution guidelines if open source]

## Design Decisions (Not Bugs!)

**Word-Level IPA Not Generated:**
- This is a **deliberate design choice**, not a missing feature
- After months of development, we determined word-level IPA is too complex for reliable automation
- We use **syllable-level IPA** instead, which is accurate and pedagogically effective
- See "IPA Strategy: Why Syllable-Level?" section above

## Known Issues

- Legacy UIKit storyboards still present (being migrated to SwiftUI)
- Some Norwegian variable names throughout codebase

## Roadmap

- [ ] Complete SwiftUI migration (remove all storyboards)
- [ ] Improve syllable segmentation accuracy
- [ ] Enhanced per-syllable IPA metadata
- [ ] Thai dictionary API integration
- [ ] Pronunciation analysis (speech recognition)
- [ ] Semantic analysis of Thai text
- [ ] Adaptive difficulty improvements
- [ ] Community word lists

**Not Planned:**
- ❌ Automatic word-level IPA generation (tried for months, not achievable reliably)

## License

[Add license information]

## Credits

**Developer:** Geir Lapstuen

**Thai Linguistics Resources:**
- Thai consonant classification
- Tone rule references
- IPA transcription standards

**Technologies:**
- SwiftUI
- Core Data
- CloudKit
- Mac Catalyst

## Support

For issues, questions, or feedback:
- [Add contact information]
- [Add issue tracker link]

## Documentation

- **[CLAUDE.md](./CLAUDE.md)** - Comprehensive developer documentation
- **[GUIDE_SHEETS_AND_MODALS.md](./GUIDE_SHEETS_AND_MODALS.md)** - UI development guide
- **[Dokumentation/](./Dokumentation/)** - Additional technical documentation

---

**Version:** 1.0
**Last Updated:** 2026-01-15
**Platforms:** iOS 17+, iPadOS 17+, macOS 14+
