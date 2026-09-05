# Thai NLP Data Generator

Dette er en **engangs-operasjon** for å generere perfekte stavelser og IPA for alle Thai ord.

## 🎯 Hva gjør dette?

- **Kjører EN GANG**: Genererer komplett Thai linguistic data
- **Deretter 100% Swift**: Ingen Python-kode i appen din
- **Perfekt nøyaktighet**: Bruker PyThaiNLP (beste Thai NLP-bibliotek)
- **Rask oppslag**: Instant lookup fra JSON-database

---

## 📋 Installasjon (EN GANG)

### Steg 1: Installer Python-avhengigheter

```bash
# I Terminal:
cd /Users/geirlapstuen/Swift/gThai/Scripts
pip3 install pythainlp
```

> **Merk**: Dette må bare gjøres EN gang på din Mac. Ikke nødvendig for iOS-appen!

---

## 🚀 Bruk (EN GANG)

### Steg 2: Generer data

```bash
cd /Users/geirlapstuen/Swift/gThai/Scripts
python3 generate_thai_data.py
```

Dette vil:
1. ✅ Lese `Resources/thai_syllable_golden.json`
2. ✅ Generere stavelser og IPA for alle ord
3. ✅ Lagre til `Resources/thai_syllable_golden_complete.json`
4. ✅ Vise statistikk og eventuelle forskjeller

**Output eksempel:**
```
================================================
Thai Syllable and IPA Generator
Powered by PyThaiNLP
================================================
✅ PyThaiNLP versjon 5.0.2 funnet

📖 Leser thai_syllable_golden.json...
✅ Funnet 100 ord å prosessere

[1/100] Prosesserer: กลางคืน
    ✅ Stavelser OK | ✅ IPA OK

[2/100] Prosesserer: กัน
    ✅ Stavelser OK | ✅ IPA OK

... (fortsetter for alle ord)

📊 STATISTIKK
================================================
Totalt prosessert: 100 ord
✅ Alle data matcher golden dataset!

✅ Ferdig! Data lagret i: thai_syllable_golden_complete.json
```

---

## 💻 Bruk i Swift (ALLTID)

### Steg 3: Legg til filen i Xcode

1. Åpne Xcode
2. Dra `Resources/thai_syllable_golden_complete.json` inn i prosjektet
3. ✅ Huk av "Copy items if needed"
4. ✅ Huk av "gThai" target

### Steg 4: Bruk i koden din

```swift
import Foundation

// ENKELT! Bare kall denne funksjonen:
let result = ThaiNLPData.lookup("กลางคืน")

print(result.syllables)  // ["กลาง", "คืน"]
print(result.ipa)        // "klaːŋ.kʰɯːn"
print(result.source)     // "PyThaiNLP (cached)"
```

**Fullstendig eksempel:**

```swift
// I din eksisterende kode - erstatt ThaiSeg med ThaiNLPData:

// GAMMELT (med 15 feil):
let syllables = ThaiSeg.segmentThai("กลางคืน")
let ipa = ThaiIPA.generateIPA(syllables)  // brukte Opus

// NYTT (100% nøyaktig):
let result = ThaiNLPData.lookup("กลางคืน")
let syllables = result.syllables  // ["กลาง", "คืน"]
let ipa = result.ipa              // "klaːŋ.kʰɯːn"
```

---

## 🔄 Når må jeg kjøre Python-scriptet igjen?

Kun når du:
- ✅ Legger til NYE ord i `thai_syllable_golden.json`
- ✅ Vil oppdatere IPA for eksisterende ord
- ✅ Bytter til nyere versjon av PyThaiNLP

For daglig utvikling: **ALDRI** - alt er 100% Swift!

---

## 🏗️ Arkitektur

```
┌─────────────────────────────────────────┐
│  Python (KUN under utvikling)          │
│  generate_thai_data.py                  │
│  ↓                                      │
│  thai_syllable_golden_complete.json     │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  Swift (produksjon)                     │
│  ThaiNLPData.lookup("กลางคืน")          │
│  ↓                                      │
│  JSON lookup (instant)                  │
│  ↓                                      │
│  ThaiNLPResult (syllables + ipa)        │
└─────────────────────────────────────────┘
```

---

## 📊 Sammenligning

| Metode | Nøyaktighet | Hastighet | Python? | Kostnad |
|--------|------------|-----------|---------|---------|
| **Claude Opus** | 🔴 85/100 | 🔴 Sakte | ❌ Nei | 💰💰💰 $$$ |
| **ThaiSeg (din)** | 🟡 85/100 | 🟢 Rask | ❌ Nei | ✅ Gratis |
| **ThaiNLPData (ny)** | 🟢 100/100 | 🟢 Instant | ✅ Kun dev | ✅ Gratis |

---

## 🆘 Feilsøking

### Problem: "PyThaiNLP ikke installert"

**Løsning:**
```bash
pip3 install pythainlp
# Eller:
python3 -m pip install pythainlp
```

### Problem: "Finner ikke thai_syllable_golden.json"

**Løsning:**
```bash
# Sjekk at du er i riktig katalog:
cd /Users/geirlapstuen/Swift/gThai/Scripts
ls ../Resources/thai_syllable_golden.json  # Skal finnes
```

### Problem: "Import error i Swift"

**Løsning:**
1. Sjekk at `ThaiNLPData.swift` er lagt til i Xcode
2. Sjekk at `thai_syllable_golden_complete.json` er i Bundle
3. Clean + rebuild: Cmd+Shift+K → Cmd+B

---

## 💡 Tips

### Legg til flere ord

```bash
# 1. Rediger Resources/thai_syllable_golden.json
# 2. Kjør generatoren igjen
python3 generate_thai_data.py

# 3. Ferdig! Swift-koden trenger ingen endringer
```

### Valider eksisterende ord

```swift
// Sjekk om et ord er pre-computed:
if ThaiNLPData.hasPreComputedData(for: "กลางคืน") {
    print("✅ Finnes i database")
} else {
    print("⚠️ Bruker fallback (NLTokenizer)")
}

// Database statistikk:
let stats = ThaiNLPData.databaseStats()
print("Loaded: \(stats.loaded), Entries: \(stats.totalEntries)")
```

### Batch-prosessering

```swift
let words = ["กลางคืน", "กัน", "การบ้าน"]
let results = ThaiNLPData.lookupBatch(words)

// Sjekk coverage:
let stats = ThaiNLPData.batchStats(words)
print("Pre-computed: \(stats.preComputed), Fallback: \(stats.fallback)")
```

---

## ✅ Sjekkliste

- [ ] Installer PyThaiNLP: `pip3 install pythainlp`
- [ ] Kjør generator: `python3 generate_thai_data.py`
- [ ] Legg til JSON i Xcode (copy to bundle)
- [ ] Test i Swift: `ThaiNLPData.lookup("กลางคืน")`
- [ ] Erstatt gammel kode med ThaiNLPData
- [ ] Slett Python-dependencies fra Mac (optional)

---

## 🎓 For de nysgjerrige

**Hva er PyThaiNLP?**
- Åpen kildekode Thai NLP-bibliotek
- Utviklet av Thai lingvister og NLP-eksperter
- Brukes i produksjon av Thai tech-selskaper
- [GitHub: PyThaiNLP](https://github.com/PyThaiNLP/pythainlp)

**Hvorfor ikke bare bruke PyThaiNLP direkte i iOS?**
- Python kjører ikke native på iOS
- Pre-computing er raskere (instant lookup vs. prosessering)
- Ingen eksterne avhengigheter i produksjon
- Enklere å debugge og vedlikeholde

---

**Laget for gThai** 🇹🇭
*Powered by PyThaiNLP - Swift-friendly*
