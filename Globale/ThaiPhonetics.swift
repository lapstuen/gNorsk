import SwiftUI
import Foundation

// MARK: - Core model

enum ThaiConsonantClass { case mid, high, low }
//enum ThaiTone { case mid, low, falling, high, rising }

struct ThaiPhonetics {

    // MARK: Initial- og coda-tabeller (forenklet)
    static let initialMap: [Character: (ThaiConsonantClass, String)] = [
        "ก": (.mid, "k"),  "จ": (.mid, "tɕ"), "ด": (.mid, "d"),  "ต": (.mid, "t"),
        "บ": (.mid, "p"),  "ป": (.mid, "p"),  "อ": (.mid, "ʔ"),  // อ som bærer
        "ข": (.high,"kʰ"), "ฃ": (.high,"kʰ"), "ฉ": (.high,"tɕʰ"), "ถ": (.high,"tʰ"),
        "ผ": (.high,"pʰ"), "ฝ": (.high,"f"),  "ส": (.high,"s"),  "ห": (.high,"h"),
        "ค": (.low, "kʰ"), "ฅ": (.low, "kʰ"), "ฆ": (.low,"kʰ"),  "ช": (.low,"tɕʰ"),
        "ซ": (.low,"s"),   "ฌ": (.low,"tɕʰ"), "ฑ": (.low,"tʰ"),  "ฒ": (.low,"tʰ"),
        "ท": (.low,"tʰ"),  "ธ": (.low,"tʰ"),  "พ": (.low,"pʰ"),  "ฟ": (.low,"f"),
        "ภ": (.low,"pʰ"),  "ฮ": (.low,"h"),   "ง": (.low,"ŋ"),   "ญ": (.low,"j"),
        "น": (.low,"n"),   "ม": (.low,"m"),   "ย": (.low,"j"),   "ร": (.low,"r"),
        "ล": (.low,"l"),   "ว": (.low,"w"),   "ฐ": (.high,"tʰ")
    ]

    // Sluttkonsonant → dead/live + coda-IPA
    static let codaMap: [Character: (dead: Bool, ipa: String)] = [
        "ก": (true, "k"), "ข": (true, "k"), "ค": (true, "k"),
        "ด": (true, "t"), "จ": (true, "t"), "ต": (true, "t"), "ช": (true,"t"), "ส": (true,"t"),
        "บ": (true, "p"), "ป": (true, "p"), "พ": (true,"p"), "ฟ": (true,"p"),
        "ง": (false,"ŋ"), "น": (false,"n"), "ม": (false,"m"),
        "ว": (false,"w"), "ย": (false,"j"), "ร": (false,"n") // r → n i coda
    ]

    // MARK: Unicode/helpers

    /// Første initial i en streng (over scalars)
    static func firstInitial(in s: String) -> (ThaiConsonantClass, String)? {
        for us in s.precomposedStringWithCanonicalMapping.unicodeScalars {
            let ch = Character(us)
            if let mapped = initialMap[ch] { return mapped }
        }
        return nil
    }

    /// Tonemerke 0–4
    static func toneMark(in s: String) -> Int {
        let s = s.precomposedStringWithCanonicalMapping
        if s.unicodeScalars.contains(where: { $0.value == 0x0E4B }) { return 4 } //
        if s.unicodeScalars.contains(where: { $0.value == 0x0E4A }) { return 3 } //
        if s.unicodeScalars.contains(where: { $0.value == 0x0E49 }) { return 2 } //
        if s.unicodeScalars.contains(where: { $0.value == 0x0E48 }) { return 1 } //
        return 0
    }

    /// Live vs dead (åpen = live)
    static func isLiveSyllable(coda: Character?) -> Bool {
        guard let c = coda, let info = codaMap[c] else { return true }
        return info.dead == false
    }

    // MARK: Vokaler

    /// Diakritiske vokaler og sammensatte mønstre (robust mot tonemerker)
    ///
    /// Det eksplisitte "อ"-nukleuset er langt "ɔː".
    /// Kort "o"-aktig vokal håndteres via egne mønstre som "อ̆" og "็อ".
    static func vowelIPA(in s0: String, coda: Character? = nil) -> (ipa: String, long: Bool)? {
        let s = s0.precomposedStringWithCanonicalMapping

        // สระ อำ (am)
        if s.contains("ำ") { return ("am", true) }

        // Spesialfall: sylable splittet som ั + ว skal behandles som ัว
        if s == "ั" && coda == "ว" { return ("uaː", true) }

        // Enkle diakritiske – sjekk kodepunkter
        var has: Set<UInt32> = []
        for u in s.unicodeScalars { has.insert(u.value) }

        if has.contains(0x0E35) { return ("iː", true) }  //
        if has.contains(0x0E34) { return ("i",  false) } //
        if has.contains(0x0E39) { return ("uː", true) }  //
        if has.contains(0x0E38) { return ("u",  false) } //
        if has.contains(0x0E37) { return ("ɯː", true) }  //
        if has.contains(0x0E36) { return ("ɯ",  false) } //
        if has.contains(0x0E32) { return ("aː", true) }  // า
        if has.contains(0x0E30) || has.contains(0x0E31) { return ("a", false) } // ะ /

        // Prefiks/sammensatte
        if s.contains("เ") && s.contains("าะ") { return ("ɔ",  false) } // เ◌าะ
        if s.contains("เ") && s.contains("อะ") { return ("e",  false) } // เ◌ะ
        if s.contains("แ") && s.contains("ะ")  { return ("ɛ",  false) } // แ◌ะ
        if s.contains("โ") && s.contains("ะ")  { return ("o",  false) } // โ◌ะ
        if s.contains("เ") && s.contains("า") && !s.contains("ะ") { return ("aw", false) } // เ◌า
        if s.contains("เ") && s.contains("ีย") { return ("iaː", true) }  // เ◌ีย
        if s.contains("เ") && s.contains("ือ") { return ("ɯaː", true) }  // เ◌ือ
        if s.contains("ัว") { return ("uaː", true) }                      // ◌ัว
        if s.contains("เ") && !s.contains("ะ") && !s.contains("า") && !s.contains("อ") { return ("eː", true) }
        if s.contains("แ") { return ("ɛː", true) }
        if s.contains("โ") { return ("oː", true) }
        if s.contains("ไ") || s.contains("ใ") { return ("ai", false) }
        if s == "อ̆" { return ("o", false) }
        if s.contains("อ") && !s.contains("เ") && !s.contains("แ") && !s.contains("โ") {
            return ("ɔː", true)
        }

        // Ingen eksplisitt vokal funnet
        return nil
    }

    // MARK: Tone

    static func tone(`class` cls: ThaiConsonantClass, toneMark: Int, live: Bool) -> ThaiTone {
        switch toneMark {
        case 1: return (cls == .low) ? .falling : .low
        case 2: return (cls == .low) ? .high    : .falling
        case 3: return (cls == .low) ? .rising  : .high
        case 4: return (cls == .low) ? .falling : .low   // จี๋ → lav
        default:
            switch cls {
            case .mid:  return live ? .mid : .low
            case .high: return live ? .rising : .low
            case .low:  return live ? .mid : .high
            }
        }
    }

    static func toneDiacritic(_ t: ThaiTone) -> String {
        switch t {
        case .high:    return "˥"
        case .mid:     return "˧"
        case .low:     return "˩"
        case .falling: return "˥˩"
        case .rising:  return "˩˥"
        }
    }
    
    /// Finnes สระ อำ i strengen (både pre- og dekomponert)?
    static func hasSaraAm(_ s: String) -> Bool {
        let s = s.precomposedStringWithCanonicalMapping
        var hasU0E33 = false
        var hasU0E4D = false
        var hasU0E32 = false
        for u in s.unicodeScalars {
            switch u.value {
            case 0x0E33: hasU0E33 = true         // ำ (prekomponert)
            case 0x0E4D: hasU0E4D = true         // ํ  (nikhahit)
            case 0x0E32: hasU0E32 = true         // า
            default: break
            }
        }
        return hasU0E33 || (hasU0E4D && hasU0E32)
    }

    /// Noen stavelseskjerner absorberer en etterfølgende ว som del av vokalen.
    /// Det gjelder særlig ั + ว og hele mønsteret ัว.
    static func vowelConsumesWCoda(in s: String, coda: Character?) -> Bool {
        guard let coda, coda == "ว" else { return false }
        let normalized = s.precomposedStringWithCanonicalMapping
        return normalized == "ั" || normalized.contains("ัว")
    }

    // MARK: IPA hovedfunksjon

    static func ipa(for thai: String) -> String {
        let s = thai.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        guard !s.isEmpty else { return "" }

        // 🔹 Hent første stavelse fra segmentThai (fra ThaiSyllableCore.swift)
        // let firstSyl = ThaiSeg.segmentThai(s).first
        let firstSyl = ThaiSeg.repairPreposedVowelNucleus(ThaiSeg.segmentThai(s)).first

        // Initial (default) …
        var initial = firstInitial(in: s) ?? (.mid, "ʔ")
        // … men hvis segmenteringen fant en onset, bruk den
        if let onsetFirst = firstSyl?.onset.first,
           let mapped = initialMap[onsetFirst] {
            initial = mapped
        }

        // Tone‑mark
        let tMark = toneMark(in: s)

        // Coda – bruk segmenteringens coda hvis tilgjengelig
        var codaChar: Character? = firstSyl?.coda?.first
        var codaIPA  = codaChar.flatMap { codaMap[$0]?.ipa } ?? ""

        // --- สระ อำ (am) spesial ---
        let hasAm = hasSaraAm(s)
        if hasAm {
            codaChar = "ม"
            codaIPA  = "m"
        }

        let foldedWAsVowel = vowelConsumesWCoda(in: s, coda: codaChar)
        let ipaCodaChar = foldedWAsVowel ? nil : codaChar
        if foldedWAsVowel {
            codaIPA = ""
        }

        // Vokal (+ fallbacks) – behold din eksisterende logikk
        let explicitVowel = vowelIPA(in: s, coda: ipaCodaChar)
        let vowelInfo: (ipa: String, long: Bool) = {
            if hasAm { return ("a", true) }
            if let v = explicitVowel { return v }
            if !codaIPA.isEmpty { return ("o", false) }
            return ("a", false)
        }()

        // Live/dead – stol først på segmentering, ellers fallback
        let live = foldedWAsVowel ? true : (firstSyl?.live ?? isLiveSyllable(coda: ipaCodaChar))
        let toneValue = tone(class: initial.0, toneMark: tMark, live: live)
        let nucleus = vowelInfo.ipa + toneDiacritic(toneValue)

        return initial.1 + nucleus + codaIPA
    }

    // MARK: Debug

    static func debugAnalysis(_ thai: String) -> String {
        let s = thai.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping

        let syl = ThaiSeg.segmentThai(s).first   // 🔹 første stavelse
        let onsetShown = syl?.onset ?? "∅"
        let nucleusShown = syl?.nucleus ?? "∅"
        let codaShown = syl?.coda ?? "∅"

        var initInfo = firstInitial(in: s) ?? (.mid, "ʔ")
        if let onsetFirst = syl?.onset.first, let mapped = initialMap[onsetFirst] {
            initInfo = mapped
        }

        let tMark    = toneMark(in: s)
        let vowel    = vowelIPA(in: s, coda: syl?.coda?.first)?.ipa ?? "∅"
        let live     = syl?.live ?? isLiveSyllable(coda: syl?.coda?.first)
        let t        = tone(class: initInfo.0, toneMark: tMark, live: live)
        let outIPA   = ipa(for: s)

        return """
        Thai: \(s)
        onset=\(onsetShown) nucleus=\(nucleusShown) coda=\(codaShown)
        initial=\(initInfo.1) class=\(String(describing: initInfo.0))
        vowel=\(vowel)  live=\(live) toneMark=\(tMark) → \(t)
        IPA=\(outIPA)
        """
    }
}

// MARK: - Mini UI + Preview (Catalyst OK)
