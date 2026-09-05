//
//  ThaiIPA.swift
//  gThai
//
//  Bygger IPA-strenger for thai-stavelser (onset/vokal/coda + tone-diacritics)
//

import Foundation

// Bruk samme tone-enum du allerede har (tilpass navn om nødvendig)
public enum ThaiTone {
    case mid, low, falling, high, rising
}

enum ThaiIPA {

    // MARK: - IPA mapping for initial consonants (onsets)
    static let ipaOnsetMap: [Character: String] = [
        "ก":"k", "ข":"kʰ", "ฃ":"kʰ", "ค":"kʰ", "ฅ":"kʰ", "ฆ":"kʰ", "ง":"ŋ",
        "จ":"t͡ɕ", "ฉ":"t͡ɕʰ", "ช":"t͡ɕʰ", "ฌ":"t͡ɕʰ", "ญ":"j",
        "ฎ":"d", "ฏ":"t", "ฐ":"tʰ", "ฑ":"tʰ", "ฒ":"tʰ", "ณ":"n",
        "ด":"d", "ต":"t", "ถ":"tʰ", "ท":"tʰ", "ธ":"tʰ", "น":"n",
        "บ":"b", "ป":"p", "ผ":"pʰ", "พ":"pʰ", "ฟ":"f", "ภ":"pʰ", "ม":"m",
        "ย":"j", "ร":"r", "ล":"l", "ว":"w", "ฬ":"l",
        "ศ":"s", "ษ":"s", "ส":"s", "ซ":"s",
        "ห":"h", "ฮ":"h", "อ":"ʔ",
        "ฤ":"rɯ", "ฦ":"lɯ"
    ]

    // MARK: - IPA for vowels (clusters)
    // NB: Inkluder ไ/ใ og kort ɔ-varianter tidlig
    static let ipaVowelClusters: [String: String] = [
        // --- diftonger (standard IPA for thai: ia/ɯa/ua uten lengdetegn ː —
        // lengdetegnet er kun for lange monoftonger som aː/iː/uː/ɔː)
        "ไ":"aj", "ใ":"aj",
        "เอา":"aw", "เา":"aw",   // เา uten อ (เขา, เรา, เข้า osv.) er den vanlige stavemåten
        "เอีย":"ia",
        "เอือ":"ɯa",
        "ัว":"ua", "วะ":"ua", "วา":"ua",

        // --- ɔ (kort)
        "เาะ":"ɔ", "เอาะ":"ɔ", "็อ":"ɔ",

        // --- standard-sett (forenklet)
        "เอะ":"ɤ", "เอ":"ɤː",
        "แอ":"ɛː", "แอะ":"ɛ",
        "โอ":"oː", "โอะ":"o",
        "ออ":"ɔː", "อะ":"a", "อา":"aː",
        "เออ":"ɤː", "เออะ":"ɤ",
        
        // --- enkeltvokaler
        "เ":"eː",   // bar เ foran koda (uten อะ/ ็ /annen forkorting) → lang e (f.eks. เทศ, เลข)
        "เ็":"e",   // เ + mai taikhu (kort-merke) foran koda → kort e (f.eks. เด็ก, เก็บ)
        "โ":"oː",   // bar โ uten อ (f.eks. โท, โรง) → lang o
        "ั":"a", "า":"aː",
        "ำ":"a",    // sara am – kort vokal (ทำ→tʰam, ตำ→tam); den implisitte ม-koda legges til i ipaSyllableWithTone
        "ิ":"i", "ี":"iː",
        "ึ":"ɯ", "ื":"ɯː",
        "ุ":"u", "ู":"uː",
        "ะ":"a",

        // --- ื + อ kombinasjoner
        "ื้อ":"ɯː",  // sara ue + mai tho + อ (som i ซื้อ)
        "ือ":"ɯː",   // sara ue + อ (uten tone)
        
        // --- แ-vokaler
        "แ":"ɛː",
        
        // --- เ-vokaler (fjerner duplikater)
        "เือ":"ɯː", "เือะ":"ɯ",
        "เีย":"ia", "เียะ":"ia",

        // --- extra เ-mønstre som kan forekomme i nucleus
        "สือ":"ɯa",
        "เสือ":"ɯa",
        "เื่อ":"ɯa"
    ]

    private static func nucleusConsumesCodaAsVowel(nucleus: String?, coda: Character?) -> Bool {
        guard let nucleus, let coda else { return false }
        let normalized = nucleus.precomposedStringWithCanonicalMapping
        return coda == "ว" && (normalized == "ั" || normalized.contains("ัว"))
    }

    // MARK: - IPA for codas
    static let ipaCodaMap: [Character: String] = [
        "ก":"k", "ข":"k", "ค":"k", "ฆ":"k",
        "ด":"t", "ต":"t", "ถ":"t", "ท":"t", "ธ":"t", "ฎ":"t", "ฏ":"t", "ฐ":"t", "ฑ":"t", "ฒ":"t",
        "จ":"t", "ฉ":"t", "ช":"t", "ฌ":"t", "ศ":"t", "ษ":"t", "ส":"t",
        "บ":"p", "ป":"p", "พ":"p", "ฟ":"p", "ภ":"p",
        "น":"n", "ณ":"n", "ญ":"n",
        "ม":"m",
        "ง":"ŋ",
        "ย":"j", "ว":"w", "ร":"n", "ล":"n", "ฬ":"n"
    ]

    // MARK: - Onset → IPA

    static func ipaForOnsetChar(_ ch: Character?) -> String {
        guard let ch else { return "" }
        return ipaOnsetMap[ch] ?? String(ch)
    }

    static func ipaForOnsetCluster(_ onset: String?) -> String {
        guard let onset else { return "" }
        
        // อย = j (not ʔj)
        if onset == "อย" {
            return "j"
        }

        // ทร = s (historisk unntak: ทรง, ทราบ, ทราย, แทรก, อินทรีย์ ...)
        if onset == "ทร" {
            return "s"
        }

        // ห + sonorant = kun sonorant-lyd (ห er stum)
        if onset.hasPrefix("ห") && onset.count == 2 {
            let secondChar = onset.dropFirst().first!
            let sonorants: Set<Character> = ["ม","น","ง","ย","ร","ล","ว"]
            if sonorants.contains(secondChar) {
                return ipaOnsetMap[secondChar] ?? String(secondChar)
            }
        }
        
        // vanlig mapping for andre clusters
        var out = ""
        for ch in onset {
            out += ipaOnsetMap[ch] ?? String(ch)
        }
        return out
    }

    // MARK: - Vowel → IPA

    static func ipaForVowel(nucleus: String?, coda: Character?) -> String {
        guard var s = nucleus, !s.isEmpty else { return "" }

        // normaliser (fjern tonemerker/små tegn – behold ˇː osv. hvis de forekommer)
        let strip: Set<Character> = ["่","้","๊","๋","์","ํ", "\u{200C}", "\u{200D}"]
        s.removeAll { strip.contains($0) }

        // robuste sjekker for ไ/ใ
        if s.contains("ไ") || s.contains("ใ") { return "aj" }

        // "เ◌ื + อ" → เอือ (ɯːa diftong)
        let hasE = s.unicodeScalars.contains { Character($0) == "เ" }
        let hasSaraUe = s.unicodeScalars.contains { Character($0) == "ื" }
        let hasO = s.unicodeScalars.contains { Character($0) == "อ" }
        if hasE && hasSaraUe && hasO { return "ɯa" }

        // "เ◌ีย" → เรียน-type patterns
        // NB: unicodeScalars, ikke String.contains — "เ" + "ี"/"ิ" slås sammen
        // til ÉN Character når de settes sammen i nucleus-strengen (samme
        // grafemklynge-fenomen som andre steder denne økten), så et vanlig
        // String.contains på ett enkelt-tegn ville aldri matche.
        let hasSaraIi = s.unicodeScalars.contains { Character($0) == "ี" }
        let hasYo = s.unicodeScalars.contains { Character($0) == "ย" }
        if hasE && hasSaraIi && hasYo {
            return "ia"
        }

        // "เ◌ิ"-familien: mange segmenteringer → behandle samlet
        let hasSaraI = s.unicodeScalars.contains { Character($0) == "ิ" }
        if hasE && hasSaraI {
            return (coda != nil) ? "ɤː" : "ɤ"
        }

        if s == "เอิ" { return (coda != nil) ? "ɤː" : "ɤ" }

        // Bar "เ" + koda "ย" (เคย, เนย, เลย ...) er en egen kjent diftong (ɤːj),
        // ikke det vanlige "เ" + koda → eː-mønsteret (เทศ, เลข ...).
        if s == "เ" && coda == "ย" { return "ɤː" }

        if s == "ั" && coda == "ว" { return "ua" }
        if let v = ipaVowelClusters[s] { return v }

        if s == "อ̆" { return "o" }   // implisitt kort vokal (CC-mønster, f.eks. คน)
        if s == "อ" { return "ɔː" }
        return s
    }

    // MARK: - Coda → IPA
    static func ipaForCoda(_ coda: Character?) -> String {
        guard let coda else { return "" }
        return ipaCodaMap[coda] ?? String(coda)
    }

    // MARK: - Tone diacritics på vokalen
    static func addTone(on vowelIPA: String, tone: ThaiTone) -> String {
        let diacritic: Character?
        switch tone {
        case .high:    diacritic = "\u{0301}" // acute
        case .low:     diacritic = "\u{0300}" // grave
        case .falling: diacritic = "\u{0302}" // circumflex
        case .rising:  diacritic = "\u{030C}" // caron
        case .mid:     diacritic = nil
        }
        guard let diacritic else { return vowelIPA }

        // Sett tonemerket rett etter FØRSTE vokalbokstav (ikke lengdetegn ː),
        // slik at diftonger (f.eks. "ua" i "ัว") får merket på hovedvokalen —
        // "ùa", ikke "uà" — i stedet for bakerst på hele vokalstrengen.
        var chars = Array(vowelIPA)
        guard let firstVowelIndex = chars.indices.first(where: { chars[$0] != "ː" }) else {
            return vowelIPA
        }
        chars.insert(diacritic, at: firstVowelIndex + 1)
        return String(chars)
    }

    // MARK: - Bygg hele stavelsen

    /// อ som bærer + ย (f.eks. "อยาก") gir sammen j-lyden, men segmenteringen
    /// legger dette som onset="ʔ" + nucleus som starter med "อย" (f.eks. "อยา"),
    /// i stedet for onset="อย" som "อย"-regelen i `ipaForOnsetCluster` forventer.
    /// Normaliser til riktig form her, felles for alle ipaSyllable*-variantene.
    private static func normalizedOnsetAndNucleus(onset: String?, nucleus: String?) -> (String?, String?) {
        if onset == "ʔ", let n = nucleus, n.hasPrefix("อย") {
            return ("อย", String(n.dropFirst(2)))
        }
        return (onset, nucleus)
    }

    static func ipaSyllable(onset: String?, nucleus: String?, coda: Character?) -> String {
        let (onset, nucleus) = normalizedOnsetAndNucleus(onset: onset, nucleus: nucleus)
        let effectiveCoda = nucleusConsumesCodaAsVowel(nucleus: nucleus, coda: coda) ? nil : coda
        return ipaForOnsetCluster(onset) + ipaForVowel(nucleus: nucleus, coda: coda) + ipaForCoda(effectiveCoda)
    }

    static func ipaSyllable(onset: Character?, nucleus: String?, coda: Character?) -> String {
        let effectiveCoda = nucleusConsumesCodaAsVowel(nucleus: nucleus, coda: coda) ? nil : coda
        return ipaForOnsetChar(onset) + ipaForVowel(nucleus: nucleus, coda: coda) + ipaForCoda(effectiveCoda)
    }

    // MARK: - Bygg med tone + valgfri glottalstopp
    static func ipaSyllableWithTone(
        onset: String?,
        nucleus: String?,
        coda: Character?,
        tone: ThaiTone,
        addGlottalIfOpenDead: Bool
    ) -> String {
        let (onset, nucleus) = normalizedOnsetAndNucleus(onset: onset, nucleus: nucleus)
        let effectiveCoda = nucleusConsumesCodaAsVowel(nucleus: nucleus, coda: coda) ? nil : coda
        let o = ipaForOnsetCluster(onset)
        let v = ipaForVowel(nucleus: nucleus, coda: coda)
        let vMarked = addTone(on: v, tone: tone)
        var c = ipaForCoda(effectiveCoda)
        if c.isEmpty, let nucleus, nucleus.contains("ำ") {
            // สระอำ (sara am) har en implisitt ม-koda som ikke er en egen konsonant i stavelsen
            c = "m"
        } else if addGlottalIfOpenDead && c.isEmpty {
            c = "ʔ"
        }
        return o + vMarked + c
    }

    // Kompatibilitet
    static func ipaForVowelCluster(_ nucleus: String?) -> String {
        return ipaForVowel(nucleus: nucleus, coda: nil)
    }
}
