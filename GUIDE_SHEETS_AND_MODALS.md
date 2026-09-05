# Guide: Sheets, Modals og Vinduer i gThai

**KRITISK: Les denne FØR du lager nye sheets/modals/vinduer!**

Denne guiden dokumenterer alle feil som er gjort og hvordan det skal gjøres riktig.

---

## 🚨 VIKTIGSTE REGLER

### 1. ALLTID Sjekk Eksisterende Kode Først
- Søk i prosjektet: `grep -r "\.sheet\|present.*ViewController" --include="*.swift"`
- Sjekk gInfo for samme funksjonalitet
- ALDRI lag noe på nytt som allerede eksisterer
- **VI HAR JOBBET I MÅNEDER - RESPEKTER DET!**

### 2. Plattformforskjeller er KRITISKE

```swift
// ❌ FEIL - Hardkodet størrelse uten plattformsjekk
.sheet(isPresented: $showSheet) {
    MyView().frame(width: 800, height: 1000)
}

// ✅ RIKTIG - Plattformspesifikk størrelse
.sheet(isPresented: $showSheet) {
    MyView()
    #if targetEnvironment(macCatalyst)
        .frame(minWidth: 800, minHeight: 1000)
    #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    #endif
}
```

### 3. UIKit vs SwiftUI Presentation

**For UIKit ViewControllers (som MarkdownViewController):**

```swift
// ❌ FEIL - Bruker SwiftUI sheet direkte
.sheet(isPresented: $show) {
    UIViewControllerWrapper(...)
}

// ✅ RIKTIG - Bruker UIKit present() som gInfo gjør
let vc = MarkdownViewController()
vc.modalPresentationStyle = .formSheet
vc.preferredContentSize = CGSize(width: 1075, height: 1300)
viewController.present(vc, animated: true)
```

---

## 📋 Sjekkliste for Nye Sheets/Modals

Før du skriver EN LINJE kode:

- [ ] **Har vi dette allerede?** Søk i prosjektet
- [ ] **Finnes dette i gInfo?** Kopier derfra hvis mulig
- [ ] **Hvilken plattform?** Mac, iPad, iPhone - alle tre?
- [ ] **UIKit eller SwiftUI?** UIKit VCs trenger spesiell håndtering
- [ ] **Størrelse definert?** Sjekk plattformspesifikke størrelser
- [ ] **Testet på alle plattformer?** iPhone, iPad, Mac

---

## 🎯 Standard Størrelser (macCatalyst)

Basert på eksisterende vinduer i gThai:

```swift
// DetailWordView (hovedvindu)
.frame(minWidth: 1000, minHeight: 1300)  // Normal
.frame(minWidth: 900, minHeight: 1200)   // Nested

// DetailWordView2 (nested)
.frame(minWidth: 900, minHeight: 1200)

// AddSentenceView
.frame(width: 800, height: 1200)

// MarkdownViewController (UIKit)
preferredContentSize = CGSize(width: 1075, height: 1300)

// ToneExplanationView
.frame(minWidth: 800, minHeight: 1200)
```

**På iPhone/iPad:** IKKE sett hardkodede størrelser - bruk `.presentationDetents([.large])`

---

## 🔧 Mønstre som FUNGERER

### Mønster 1: Enkel SwiftUI Sheet

```swift
struct MyView: View {
    @State private var showSheet = false

    var body: some View {
        Button("Åpne") { showSheet = true }
        .sheet(isPresented: $showSheet) {
            SheetContentView()
            #if targetEnvironment(macCatalyst)
                .frame(minWidth: 800, minHeight: 1000)
            #else
                .presentationDetents([.large])
            #endif
        }
    }
}
```

### Mønster 2: UIKit ViewController fra SwiftUI

Se `MarkdownEditorWrapper.swift` for fullstendig eksempel.

**Nøkkelpunkter:**
- Bruk `UIViewControllerRepresentable`
- Sett `modalPresentationStyle` og `preferredContentSize`
- Bruk UIKit `present()` direkte, ikke SwiftUI `.sheet()`
- Håndter callbacks via Coordinator

### Mønster 3: Conditional Presentation (nested vs normal)

```swift
struct MyDetailView: View {
    let isNested: Bool

    var body: some View {
        content
        #if targetEnvironment(macCatalyst)
            .frame(
                minWidth: isNested ? 900 : 1000,
                minHeight: isNested ? 1200 : 1300
            )
        #else
            .presentationDetents([.large])
        #endif
    }
}
```

---

## ❌ VANLIGE FEIL (UNNGÅ DISSE!)

### Feil 1: Glemme Plattformsjekk
```swift
// ❌ Dette gjør iPhone ubrukelig!
.sheet(isPresented: $show) {
    MyView().frame(width: 800, height: 1000)
}
```

### Feil 2: Feil Wrapper for UIKit
```swift
// ❌ SwiftUI sheet + UIKit VC = layout problemer
.sheet(isPresented: $show) {
    UIViewControllerRepresentable { ... }
        .frame(width: 800, height: 1000)
}

// ✅ Bruk UIKit present direkte
```

### Feil 3: Hardkode Alle Størrelser
```swift
// ❌ Ikke hardkode .frame() på image/button størrelser
Image(systemName: "photo")
    .frame(width: 200, height: 200)  // Dette er OK for ikoner

// Men IKKE for hele vinduer uten plattformsjekk!
```

### Feil 4: Ikke Teste på Alle Plattformer
- **MÅ TESTE:** iPhone, iPad, Mac
- En stor Mac-size kan gjøre iPhone helt ubrukelig
- iPad kan trenge andre detents enn iPhone

### Feil 5: Finne Opp Hjulet På Nytt
```swift
// ❌ Lage ny løsning uten å sjekke eksisterende kode
// ✅ SØK FØRST: grep -r "lignende funksjonalitet"
```

---

## 🔍 Debugging Tips

### Problem: Sheet er for liten/stor
1. Sjekk om plattformsjekk mangler
2. Sammenlign med lignende sheets i prosjektet
3. Sjekk gInfo for samme funksjonalitet

### Problem: UIKit VC layout er feil
1. Er `modalPresentationStyle` satt?
2. Er `preferredContentSize` satt?
3. Bruker du SwiftUI `.sheet()` i stedet for UIKit `present()`?

### Problem: Fungerer på Mac men ikke iPhone
1. Du har glemt `#if targetEnvironment(macCatalyst)`
2. Legg til `.presentationDetents([.large])` for iOS

---

## 📚 Eksempler fra gThai

### ✅ AddSentenceView (RIKTIG)
```swift
.sheet(isPresented: $showingAddSentence) {
    AddSentenceView(word: word)
    #if targetEnvironment(macCatalyst)
        .frame(width: 800, height: 1200)
    #endif
}
```

### ✅ MarkdownEditorWrapper (UIKit - RIKTIG)
Se `SwiftUI/Views/MarkdownEditorWrapper.swift`
- Bruker UIViewControllerRepresentable
- Setter modalPresentationStyle og preferredContentSize
- Presenterer via UIKit present()

### ✅ ToneExplanationView (RIKTIG)
```swift
.sheet(item: $selectedInfo) { info in
    ToneExplanationView(info: info)
    #if os(macOS) || targetEnvironment(macCatalyst)
        .frame(minWidth: 800, minHeight: 1200)
    #endif
}
```

---

## 🎓 Lærdom fra gInfo

### gInfo Mønster for UIKit Presentation
```swift
let vc = MarkdownViewController()
vc.modalPresentationStyle = .formSheet
vc.preferredContentSize = CGSize(width: 1075, height: 1300)
vc.markdownText = text

vc.onSave = { newText, _, _, _ in
    self.updateText(newText)
}

self.present(vc, animated: true)
```

**VIKTIG:** Dette fungerer perfekt i gInfo. Når vi wrapper dette i SwiftUI, må vi beholde NØYAKTIG samme mønster!

---

## 🚀 Rask Referanse

### Før du lager ny sheet:
1. `grep -r "\.sheet.*isPresented" --include="*.swift" | grep -v Binary`
2. Se på eksisterende implementasjoner
3. Kopier mønster fra lignende sheet
4. Legg til plattformsjekk
5. Test på alle plattformer

### Størrelser å huske:
- **Store vinduer (detail):** ~1000x1300 (Mac)
- **Medium vinduer (forms):** ~800x1200 (Mac)
- **UIKit modals:** 1075x1300 (gInfo standard)
- **iPhone/iPad:** `.presentationDetents([.large])`

---

## 🎨 MODERNE LAYOUT-PRINSIPPER (ChatGPT Best Practices)

### 1. ALDRI Hardkode Størrelser på Hovedinnhold
```swift
// ❌ FEIL
var body: some View {
    VStack {
        // innhold
    }
    .frame(width: 800, height: 600)  // IKKE gjør dette!
}

// ✅ RIKTIG
var body: some View {
    StandardPage {  // Bruker maxWidth: .infinity
        VStack {
            // innhold
        }
    }
}
```

### 2. Bruk StandardPage for Alt Nytt Innhold
```swift
// StandardPage håndterer:
// - Sentrering av innhold
// - Maks-bredde (600-700pt)
// - Padding
// - Fungerer både på iPhone og Mac

struct MyNewView: View {
    var body: some View {
        StandardPage {
            // Ditt innhold her
        }
    }
}
```

### 3. Size Class > Plattformsjekk
```swift
// ❌ UNNGÅ (når mulig)
#if targetEnvironment(macCatalyst)
    .font(.largeTitle)
#else
    .font(.title)
#endif

// ✅ FORETREKK
@Environment(\.horizontalSizeClass) var sizeClass

var body: some View {
    Text("Tittel")
        .font(sizeClass == .compact ? .title : .largeTitle)
}
```

### 4. .frame() Kun for Max/Min - IKKE Piksel-Layout
```swift
// ❌ FEIL - Bruker .frame som layout-verktøy
Text("Hello")
    .frame(width: 100, height: 50)

// ✅ RIKTIG - Bruker .frame for begrensninger
ScrollView {
    content
}
.frame(maxWidth: 700)  // Begrenser maksbredde
```

### 5. Alle Views Skal Være Reusable
```swift
// ✅ Kan brukes i NavigationStack, Sheet, WindowGroup
struct MyView: View {
    var body: some View {
        StandardPage {
            // Innhold
        }
        // IKKE .navigationTitle her hvis reusable
    }
}

// Legg navigationTitle der view brukes:
NavigationStack {
    MyView()
        .navigationTitle("Min Tittel")
}
```

### 6. Alltid Kompilerbare Previews
```swift
// ❌ FEIL - Komplisert preview
#Preview {
    #if os(macOS)
        MyView().frame(width: 800)
    #else
        MyView()
    #endif
}

// ✅ RIKTIG - Enkel, kompilerbar preview
#Preview {
    MyView()
}
```

---

## ⚡ TL;DR - De 5 Gullreglene

1. **SØK FØR DU LAGER** - Vi har måneder med arbeid allerede
2. **BRUK StandardPage** - For alt nytt innhold
3. **Size Class > #if** - Når mulig, bruk size class
4. **Ingen Hardkodede Størrelser** - Bruk maxWidth/minWidth
5. **KOPIER FRA gInfo** - Når i tvil, gjør som gInfo

---

**Sist oppdatert:** 2025-12-12
**Vedlikeholdes av:** Claude (les denne FØR hver ny sheet!)
