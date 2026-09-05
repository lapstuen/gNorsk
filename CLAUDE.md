# gNorsk CLAUDE.md

Thai language learning app for iOS/iPadOS/macOS (Mac Catalyst).
SwiftUI primary + legacy UIKit. Core Data + CloudKit sync.

---

## Build

```bash
xcodebuild -project gNorsk.xcodeproj -scheme gNorsk -configuration Debug build
xcodebuild test -project gNorsk.xcodeproj -scheme gNorsk -destination 'platform=iOS Simulator,name=iPhone 15'
xcodebuild -project gNorsk.xcodeproj -scheme gNorsk -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build
```

**NEVER auto-build. ASK first: "Skal jeg bygge prosjektet?"**

---

## Directory Structure

```
MainViews/          Root views: MainAppView, GridView, DetailWordView, CreateWordView
SwiftUI/Components/ 25+ reusable components (StandardPage, TTSButtonRow, ThaiSyllableAnalysisView...)
SwiftUI/Views/      Feature views: ActiveLearningView, ReviewDueView, ExerciseView, RecentlyEditedView
SwiftUI/Detailview/ Word detail components
SwiftUI/ThaiAlphaModule/ Thai alphabet teaching (18 files)
Globale/Syllable/   Thai NLP engine (19 files)
  MostImportentFiles/ ThaiIPA.swift, ThaiToneLogic.swift, ThaiSeg.swift
Div/                AppState.swift, SearchView.swift, EditGroupView.swift, ToastView.swift
CoreData/           PersistenceController.swift, gNorsk.xcdatamodeld/
SwiftGeneral/       GLFunctions.swift (~80KB), Logger.swift, APIConfig.swift
StoryBoards/        Legacy UIKit (phasing out)
```

---

## AppState (Div/AppState.swift)

```swift
@Observable class AppState {
    var valgtGruppeId: Int16 = 0       // Selected group ID
    var valgtGruppeNavn: String = ""    // Selected group name
    var currentWordID: NSManagedObjectID?
    var visAlleDetaljer: Bool = true    // false = exercise mode
    var sessionResults: [UUID: Bool] = [:]
    var refreshToken: UUID = UUID()     // Set new UUID to force re-render
    var pendingSearchText: String?      // Triggers auto search nav

    static let autoCreatedWordsGroupId: Int16 = 210
}
```

Inject via `.environment(appState)`, access via `@Environment(AppState.self)`.

---

## Core Data Model

**ThaiWords:** `id`, `thaiWord`, `englishWord`, `ipa`(deprecated), `sentence`, `notes`, `tags`, `image`, `groupId`, `insertDate`, `modifiedDate`, `frequencyRank`, `star`, spaced-rep fields (`learningState`, `dueAt`, `easiness`, `lapses`, etc.)

**Group:** `groupId`, `groupName`, `groupType` (-1=normal active, -9=inactive, 1=freq active, 2=freq done, 3=freq paused, 9=freq inactive), `frequencyFrom/To`

**Group conventions:** `@`=internal, `#`=hidden, `$`=special, no prefix=normal user groups. Frequency names like `"0001-0100"`.

**PersistenceController.shared.container** — always use `viewContext` from environment.

---

## ⚠️ CRITICAL: IPA Strategy — Syllable-Level Only

**DO NOT** generate or improve word-level IPA. We tried. It doesn't work reliably for Thai.

- ❌ `ThaiWords.ipa` — deprecated, kept for backward compat only
- ✅ `ThaiSyllable.ipa` — per-syllable IPA, accurate and reliable
- ✅ TTS buttons (Narisa, Kanya, Google, Forvo, etc.) for audio

**Focus on:** syllable segmentation accuracy, per-syllable IPA mappings, TTS integration.

---

## Thai NLP Engine (Globale/Syllable/)

- **ThaiSeg.swift** — main segmenter: `ThaiSeg().segment(text:) → [ThaiSyllable]`
- **ThaiIPA.swift** — consonant/vowel → IPA mappings
- **ThaiToneLogic.swift** — tone rules: class (MID/HIGH/LOW) × mark × live/dead
- **ThaiSyllable.swift** — `struct ThaiSyllable { onset, nucleus, coda, live, ipa, toneMark, original }`
- **ThaiVowelPatterns.swift** — pre-posed (เ แ โ ใ ไ), post-posed, complex patterns

Always normalize: `text.precomposedStringWithCompatibilityMapping`

---

## Mac Catalyst Sheets (gNorsk sizes)

```swift
.sheet(isPresented: $show) {
    MyView()
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 800, minHeight: 1000)
        #endif
}
```
- Large detail: `1000×1300`, Nested: `900×1200`, Medium: `800×1000`
- Use `List`, never `Form`
- Use `StandardPage {}` wrapper for content layout

---

## Spaced Repetition

`learningState`: 0=new, 1=learning, 2=reviewing. `dueAt` = next review. `easiness` default 2.5 (range 1.3-2.5). Exercise mode: `appState.visAlleDetaljer = false` → GridView filters to `dueAt <= now`.

---

## Conventions

- Norwegian variable names throughout: `valgtGruppeId`, `taleTrening`, `menyNr`
- Views suffixed `View`, VCs suffixed `VC`
- New views → `SwiftUI/Components/` (reusable) or `SwiftUI/Views/` (feature)
- Use `@Observable` not `@StateObject` for new code
- Group ID 0 = all groups, 210 = auto-created words

---

## Quick File Reference

```
Root navigation     MainViews/MainAppView.swift
Vocabulary grid     MainViews/GridView.swift
Word detail         MainViews/DetailWordView.swift
Thai segmentation   Globale/Syllable/MostImportentFiles/ThaiSeg.swift
IPA transcription   Globale/Syllable/MostImportentFiles/ThaiIPA.swift
Tone rules          Globale/Syllable/MostImportentFiles/ThaiToneLogic.swift
Global state        Div/AppState.swift
Core Data           CoreData/PersistenceController.swift
UI components       SwiftUI/Components/
Search              Div/SearchView.swift
Exercise            SwiftUI/Views/ActiveLearningView.swift
```

---

## Common Pitfalls

| Problem | Fix |
|---------|-----|
| Sheet tiny on Mac | Add `.frame(minWidth:minHeight:)` inside `#if targetEnvironment(macCatalyst)` |
| AppState change no re-render | `appState.refreshToken = UUID()` |
| Core Data crash on save | Check `mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy` |
| Thai boxes (□) | Use system font with Thai support or `Sarabun` |
| IPA wrong | Debug syllable segmentation first: `print(ThaiSeg().segment(text:))` |
