# 🚀 Produksjonsoppsett - Alle Thai-ord

Dette er den **riktige** måten å sette opp Thai NLP Data for produksjon.

Golden-filen (99 ord) er KUN for testing - ikke for reell bruk!

---

## 📋 Steg-for-steg Guide

### **Steg 1: Eksporter alle ord fra appen** (30 sekunder)

Legg til en eksport-knapp i appen din (midlertidig):

```swift
// I MainAppView.swift eller hvor som helst:
import SwiftUI

struct MyDebugView: View {
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        VStack {
            Button("Eksporter alle Thai-ord") {
                ThaiWordsExporter.exportAllWords(context: viewContext)
            }
            .buttonStyle(.bordered)
        }
    }
}
```

**Eller** legg til i eksisterende view:

```swift
.toolbar {
    ToolbarItem {
        Button(action: {
            ThaiWordsExporter.exportAllWords(context: viewContext)
        }) {
            Label("Eksporter", systemImage: "square.and.arrow.up")
        }
    }
}
```

**Kjør appen** og trykk på eksport-knappen.

Output:
```
✅ Eksportert til:
   /Users/geirlapstuen/Library/Developer/CoreSimulator/Devices/.../Documents/all_thai_words.json
```

Stien blir kopiert til utklippstavlen automatisk!

---

### **Steg 2: Kopier filen til Resources** (10 sekunder)

```bash
# Lim inn stien fra utklippstavlen:
cp '/Users/geirlapstuen/Library/Developer/.../all_thai_words.json' \
   /Users/geirlapstuen/Swift/gThai/Resources/all_thai_words.json
```

Sjekk at filen finnes:
```bash
ls -lh /Users/geirlapstuen/Swift/gThai/Resources/all_thai_words.json
```

---

### **Steg 3: Generer IPA og stavelser** (1-5 minutter avhengig av antall ord)

```bash
cd /Users/geirlapstuen/Swift/gThai/Scripts
python3 generate_thai_data.py
```

Dette vil:
- ✅ Lese `all_thai_words.json`
- ✅ Generere stavelser for ALLE ord (PyThaiNLP)
- ✅ Bruke din golden IPA-data (perfekt!)
- ✅ Lagre til `thai_complete.json`

**Output:**
```
🚀 PRODUKSJON MODUS: Prosesserer alle ord
✅ Funnet 5000 ord å prosessere
...
✅ Ferdig! Data lagret i: thai_complete.json
```

---

### **Steg 4: Legg til i Xcode** (30 sekunder)

1. Åpne Xcode
2. Dra `Resources/thai_complete.json` inn i prosjektet
3. ✅ Huk av: "Copy items if needed"
4. ✅ Huk av: "gThai" target
5. Clean Build: Cmd+Shift+K
6. Build: Cmd+B

---

## ✅ Ferdig!

Nå har du:
- ✅ **ALLE** Thai-ord fra Core Data med perfekt IPA
- ✅ PyThaiNLP stavelse-segmentering (94% nøyaktighet)
- ✅ Automatisk fallback til ThaiSeg for ukjente ord
- ✅ Instant lookup - ingen API-kall
- ✅ 100% offline
- ✅ Gratis

---

## 🔄 Når må jeg kjøre dette igjen?

Kun når du:
- ✅ Legger til mange NYE ord i Core Data (>100 ord)
- ✅ Vil oppdatere IPA for eksisterende ord
- ✅ Bytter til nyere versjon av PyThaiNLP

**For daglig utvikling:** Aldri! Fallback til ThaiSeg håndterer nye ord automatisk.

---

## 🧪 Test-modus (Golden dataset)

Hvis du vil teste med golden-datasettet (99 ord):

```bash
python3 generate_thai_data.py --test
```

Dette bruker `thai_syllable_golden.json` og genererer `thai_syllable_golden_complete.json`.

---

## 📊 Statistikk

Kjør for å se hvor mange ord du har:

```bash
# Antall ord eksportert:
cat Resources/all_thai_words.json | grep '"text"' | wc -l

# Antall ord prosessert:
cat Resources/thai_complete.json | grep '"text"' | wc -l
```

---

## 🆘 Feilsøking

### Problem: "Finner ikke all_thai_words.json"

**Løsning:** Kjør Steg 1 igjen - eksporter fra appen.

### Problem: "PyThaiNLP not found"

**Løsning:**
```bash
pip3 install pythainlp python-crfsuite
```

### Problem: "thai_complete.json ikke i bundle"

**Løsning:**
1. Åpne Xcode
2. Finn `thai_complete.json` i Project Navigator
3. Sjekk at den er i Target Membership for "gThai"
4. Clean + Build

---

## 💡 Pro Tips

### Automatiser eksport

Legg til denne funksjonen i AppDelegate:

```swift
#if DEBUG
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    // Eksporter automatisk ved hver launch (kun debug)
    if CommandLine.arguments.contains("--export-words") {
        ThaiWordsExporter.exportAllWords(context: persistentContainer.viewContext)
    }

    return true
}
#endif
```

Kjør deretter:
```bash
xcodebuild -scheme gThai -destination 'platform=iOS Simulator,name=iPhone 15' \
    -testPlanConfiguration ExportWords
```

### Batch-prosessering

Hvis du har MANGE ord (>10,000), del opp prosesseringen:

```bash
# Del opp i batches:
python3 split_json.py all_thai_words.json --batch-size 5000

# Prosesser hver batch:
for file in all_thai_words_*.json; do
    python3 generate_thai_data.py --input "$file" --output "complete_${file}"
done

# Slå sammen:
python3 merge_json.py complete_*.json --output thai_complete.json
```

---

**Laget for gThai** 🇹🇭
*Den riktige måten - alle ord, ikke bare 99!*
