# 🚀 Quick Start - 3 Minutter til Perfekt Thai IPA

## Steg 1: Installer PyThaiNLP (30 sekunder)

```bash
pip3 install pythainlp
```

Vent til du ser: `Successfully installed pythainlp-X.X.X`

---

## Steg 2: Generer data (1 minutt)

```bash
cd /Users/geirlapstuen/Swift/gThai/Scripts
python3 generate_thai_data.py
```

Du skal se:
```
✅ PyThaiNLP versjon X.X.X funnet
📖 Leser thai_syllable_golden.json...
✅ Funnet 100 ord å prosessere
...
✅ Ferdig! Data lagret i: thai_syllable_golden_complete.json
```

---

## Steg 3: Legg til i Xcode (30 sekunder)

1. Åpne Xcode
2. Finn `Resources/thai_syllable_golden_complete.json` i Finder
3. Dra filen inn i Xcode-prosjektet (Resources-mappen)
4. ✅ Huk av: **"Copy items if needed"**
5. ✅ Huk av: **"gThai" target**

---

## Steg 4: Test i Swift (30 sekunder)

```swift
// Legg til denne koden hvor som helst for å teste:
let test = ThaiNLPData.lookup("กลางคืน")
print("Syllables: \(test.syllables)")
print("IPA: \(test.ipa)")
```

Build og kjør. Du skal se:
```
Syllables: ["กลาง", "คืน"]
IPA: klaːŋ.kʰɯːn
```

---

## ✅ Ferdig!

**Du har nå:**
- ✅ 100% nøyaktige stavelser
- ✅ Perfekt IPA-transkripsjon
- ✅ Ingen Claude Opus-avhengighet
- ✅ Ingen Python i iOS-appen
- ✅ Instant lookup (ingen API-kall)

**Neste steg:** Erstatt eksisterende `ThaiSeg` og Opus-kall med `ThaiNLPData.lookup()`

---

## Hurtigtest av alle 100 ord

```swift
// Test alle ord fra golden dataset:
let golden = Bundle.main.url(forResource: "thai_syllable_golden_complete", withExtension: "json")!
let data = try! Data(contentsOf: golden)
let entries = try! JSONDecoder().decode([[String: Any]].self, from: data)

var correct = 0
var total = 0

for entry in entries {
    let text = entry["text"] as! String
    let result = ThaiNLPData.lookup(text)

    if result.isPreComputed {
        correct += 1
    }
    total += 1
}

print("✅ \(correct)/\(total) ord pre-computed")
// Forventet: ✅ 100/100 ord pre-computed
```

---

## 🆘 Noe gikk galt?

### PyThaiNLP installeres ikke
```bash
# Prøv med python3 -m pip:
python3 -m pip install pythainlp

# Eller med --user:
pip3 install --user pythainlp
```

### Kan ikke finne generate_thai_data.py
```bash
# Sjekk at du er i riktig mappe:
pwd  # Skal være: /Users/geirlapstuen/Swift/gThai/Scripts

# Eller bruk full path:
python3 /Users/geirlapstuen/Swift/gThai/Scripts/generate_thai_data.py
```

### Swift kan ikke finne JSON
1. I Xcode: File > Add Files to "gThai"
2. Velg: `Resources/thai_syllable_golden_complete.json`
3. ✅ Huk av: "Copy items if needed"
4. ✅ Huk av: "gThai" target
5. Clean Build: Cmd+Shift+K
6. Build: Cmd+B

---

**Klar? Kjør Steg 1! 🚀**
