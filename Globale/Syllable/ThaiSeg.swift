//
//  ThaiSeg.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/24/25.
// 


import Foundation

enum VowelLength { case short, long, unknown }

// MARK: - Segmenteringsnavnerom
enum ThaiSeg {
    // Små helpers
    // Én liten tabell for sonorante kodaer
 static let sonorantCoda: Set<Character> = ["ม","น","ง","ว","ย","ร","ล"]

/// Hent vokallengde fra samme kilde du allerede bruker (IPA):
    /// Hent vokallengde fra samme kilde du allerede bruker (IPA),
    /// men kortslutt først når vi ser den thailandske kort-markøren.
    static func vowelLength(for nucleus: String?) -> VowelLength {
        guard let nucleus else { return .unknown }

        print("🔍 vowelLength called with nucleus: '\(nucleus)'")

        // Thai-kortmarkører → kort
        if nucleus.contains("ะ") { return .short }
        if nucleus.contains("็") { return .short }   // mai taikhu gir kort i praksis

        // Special case: single ว or วอ should be SHORT when it has a coda
        // (it's the implicit vowel, not a long diphthong)
        if nucleus == "ว" || nucleus == "วอ" { return .short }

        // Explicit "อ" corresponds to long ɔː; the short inherent vowel uses "อ̆".
        if nucleus == "อ" { return .long }

        // Bruk IPA som fasit
        let ipa = ThaiIPA.ipaForVowel(nucleus: nucleus, coda: nil)
        print("🔍   IPA for '\(nucleus)' = '\(ipa)'")

        // monoftonger med ː → lang
        if ipa.contains("ː") {
            print("🔍   Contains ː → LONG")
            return .long
        }

        // diftonger er lange selv uten ː
        let longDiphthongs: Set<String> = ["aj","aw","ia","ɯa","ua","ej","oj","ɛj","ɔj","ɤj"]
        if longDiphthongs.contains(ipa) {
            print("🔍   Is long diphthong → LONG")
            return .long
        }

        print("🔍   Default → SHORT")
        return .short
    }
    
    @inlinable static func firstToneMark(in s: String) -> Character? {
        for ch in s {
            for us in ch.unicodeScalars {
                let c = Character(us)
                if toneMarks.contains(c) { return c }   // toneMarks = ["่","้","๊","๋"]
            }
        }
        return nil
    }
    
    // MARK: - Helpers (bygger på eksisterende konstanter)
    @inline(__always) private static func isDiacritic(_ c: Character) -> Bool {
        // tone + små kombinerende tegn du allerede har i 'vowels'
        return toneMarks.contains(c) || c == silencer || c == maiHanakat || c == "็" || c == "ํ"
    }

    @inline(__always) private static func isVowelSignAfter(_ c: Character) -> Bool {
        // eksplisitte vokaltegn som står ETTER en base (ikke de pre-posed เ แ โ ใ ไ)
        return vowels.contains(c) && !preposedVowels.contains(c) && !toneMarks.contains(c)
    }
    
    @inlinable static func advance(_ i: inout Int, limit: Int) -> Bool { i += 1; return i < limit }

    @inlinable static func peek(_ a: [Character], _ i: Int, _ k: Int) -> Character? {
        let j = i + k; return (0..<a.count).contains(j) ? a[j] : nil
    }

    @inlinable static func isVowelStarter(_ c: Character?) -> Bool {
        guard let c else { return false }
        return preposedVowels.contains(c) || vowels.contains(c) || toneMarks.contains(c) || c == "อ"
    }

    @inlinable static func isValidInitialCluster(_ c1: Character, _ c2: Character) -> Bool {
        initialClusterTable[c1]?.contains(c2) ?? false
    }

    @inlinable static func ch(_ c: Character?) -> String { c.map(String.init) ?? "∅" }

    @inlinable static func rem(_ chars: [Character], _ i: Int) -> String {
        (i < chars.count) ? String(chars[i...]) : "∅"
    }

    @inlinable static func wnd(_ chars: [Character], _ i: Int) -> (Character?, Character?, Character?) {
        (peek(chars, i, 1), peek(chars, i, 2), peek(chars, i, 3))
    }

    @inlinable static func charHasVowelOrTone(_ ch: Character?) -> Bool {
        guard let ch else { return false }
        for s in ch.unicodeScalars {
            let c = Character(s)
            if preposedVowels.contains(c) || vowels.contains(c) || toneMarks.contains(c) || c == "อ" { return true }
        }
        return false
    }

    @inlinable static func hasVowelOrTone(_ ch: Character) -> Bool {
        for s in String(ch) { if vowels.contains(s) || toneMarks.contains(s) || preposedVowels.contains(s) { return true } }
        return false
    }

    @inlinable static func collectMarks(from ch: Character) -> String {
        var out = ""; for us in String(ch).unicodeScalars {
            let c = Character(us); if vowels.contains(c) || toneMarks.contains(c) { out.append(c) }
        }; return out
    }

    @inlinable static func baseConsonant(_ ch: Character?) -> Character? {
        guard let ch else { return nil }
        for s in ch.unicodeScalars { let c = Character(s); if ("ก"..."ฮ").contains(c) { return c } }
        return nil
    }

    @inlinable static func isConsonant(_ c: Character) -> Bool {
        ("ก"..."ฮ").contains(c) && !vowels.contains(c) && !toneMarks.contains(c) && !preposedVowels.contains(c)
    }

    @inlinable static func isVowelOrTone(_ c: Character) -> Bool {
        vowels.contains(c) || toneMarks.contains(c) || preposedVowels.contains(c)
    }

    @inlinable static func leadingConsonant(in ch: Character) -> Character? {
        for us in String(ch).unicodeScalars { let c = Character(us); if isConsonant(c) { return c } }
        return nil
    }

    @inlinable static func containsVowelOrTone(_ ch: Character) -> Bool {
        for us in String(ch).unicodeScalars {
            let c = Character(us)
            if vowels.contains(c) || toneMarks.contains(c) || preposedVowels.contains(c) || c == "อ" { return true }
        }
        return false
    }

    @inlinable static func isBoundary(_ ch: Character?) -> Bool {
        guard let ch else { return true }
        let isThaiLetter = ("ก"..."ฮ").contains(ch) || preposedVowels.contains(ch) || vowels.contains(ch) || toneMarks.contains(ch) || ch == "อ"
        return !isThaiLetter
    }

    // Kluster‑spising
    @inlinable static func eatInitialCluster(in chars: [Character], i: inout Int, onset: inout String, hasPendingVowel: Bool = false) -> String {
        var carried = ""
        // Unntak: hvis vi allerede har en ั-vokal på vent (f.eks. "หัว", der ห+ั
        // er én grafemklynge), skal ว kombineres med den til diftongen "ัว" —
        // ikke slukes som ห-นำ-kluster (som ville gitt "หว" → uttalt "w").
        if onset == "ห", i < chars.count, let baseChar = baseConsonant(chars[i]), hanamFollowers.contains(baseChar),
           !(baseChar == "ว" && hasPendingVowel) {
            let g = chars[i]
            onset.append(baseChar)
            for us in String(g).unicodeScalars {
                let sc = Character(us)
                if vowels.contains(sc) || toneMarks.contains(sc) || preposedVowels.contains(sc) { carried.append(sc) }
            }
            if !advance(&i, limit: chars.count) { return carried }
        }
        while i < chars.count {
            let g = chars[i]
            guard let base = baseConsonant(g), isConsonant(base) else { break }
            let c1 = onset.last!; if !isValidInitialCluster(c1, base) { break }
            onset.append(base)
            for us in g.unicodeScalars {
                let sc = Character(us)
                if vowels.contains(sc) || toneMarks.contains(sc) || preposedVowels.contains(sc) || sc == "อ" { carried.append(sc) }
            }
            if !advance(&i, limit: chars.count) { break }
            if showPrint { print("🟢 eatCluster: base='\(base)', carried='\(carried)' i=\(i)") }
        }
        return carried
    }

    // Live/Dead
static func isLiveSyllable(nucleus: String, coda: Character?) -> Bool {
    print("🔍 isLiveSyllable: nucleus='\(nucleus)' coda='\(String(describing: coda))'")

    let vlen = vowelLength(for: nucleus)
    print("🔍   vowelLength = \(vlen)")

    if case .long = vlen {
        print("🔍   → LIVE (long vowel)")
        return true
    }

    if let c = coda {
        print("🔍   coda exists: '\(c)'")
        print("🔍   sonorantCoda set: \(sonorantCoda)")
        let isSonorant = sonorantCoda.contains(c)
        print("🔍   isSonorant = \(isSonorant)")
        if isSonorant {
            print("🔍   → LIVE (sonorant coda)")
            return true
        }
    } else {
        print("🔍   no coda")
    }

    print("🔍   → DEAD")
    return false
}
    
     static func shouldTakeAsCoda(at i: Int, in chars: [Character]) -> (take: Bool, advanceTo: Int) {
        let cand = chars[i]
        // kandidat må i praksis kunne være final – bruk dine eksisterende tabeller
        // Allow consonant codas or ะ vowel as final
        guard allowedCoda.contains(cand) || hanamFollowers.contains(cand) || cand == "ะ" else { return (false, i) }

        var j = i + 1

        // 1) Spis diakritika/tonemerker som hører til samme stavelse
        while j < chars.count, isDiacritic(chars[j]) { j += 1 }

        // 2) Slutt på ord → cand er koda
        if j >= chars.count { return (true, j) }

        let next = chars[j]

        // 3) Eksplisitt vokaltegn etter cand → cand var IKKE koda (lar nucleus håndtere)
        if isVowelSignAfter(next) { return (false, i) }

        // 3.5) If next character has silencer mark ์, don't take cand as coda
        // The silenced consonant should attach to the previous syllable
        if next == silencer || (j + 1 < chars.count && chars[j + 1] == silencer) {
            if showPrint { print("🟠 → Next has silencer, don't take '\(cand)' as coda") }
            return (false, i)
        }

        // 4) Thai diphthong/triphthong regler
        if showPrint { print("🟠 shouldTakeAsCoda: cand='\(cand)' next='\(next)'") }

        // 4a) ษ + า → ikke ta som coda (original rule)
        if cand == "ษ" && next == "า" {
            if showPrint { print("🟠 → IKKE ta ษ som coda, la 'ษา' være egen stavelse") }
            return (false, i)
        }

        // 4a2) ฬ + า → ikke ta som coda (for กีฬา)
        if cand == "ฬ" && next == "า" {
            if showPrint { print("🟠 → IKKE ta ฬ som coda, la 'ฬา' være egen stavelse") }
            return (false, i)
        }
        
        // 4b) เ◌ีย + น/ม/ง → ikke ta ย som coda (Thai triphthongs)
        if cand == "ย" && (next == "น" || next == "ม" || next == "ง") {
            if showPrint { print("🟠 → Checking เ◌ีย pattern for ย + \(next)") }
            // Sjekk om dette er del av เ◌ีย mønster ved å se bakover
            // เรียน = เ + ร + ี + ย + น, så ved i=3 (ย) skal chars[i-1] være ี
            
            // Debug: print context
            if showPrint { 
                let context = (max(0, i-3)..<min(chars.count, i+3)).map { chars[$0] }
                print("🟠 → Context around ย at i=\(i): \(context.map(String.init).joined())")
                if i >= 1 { print("🟠 → chars[i-1] = '\(chars[i-1])'") }
                if i >= 2 { print("🟠 → chars[i-2] = '\(chars[i-2])'") }
                if i >= 3 { print("🟠 → chars[i-3] = '\(chars[i-3])'") }
            }
            
            // Look for ี in nearby positions (check Unicode scalars within each character)
            var foundSaraI = false
            for offset in 1...min(3, i) {
                let charAtPos = chars[i-offset]
                // Check if this character contains ี as one of its Unicode scalars
                if charAtPos.unicodeScalars.contains(where: { Character($0) == "ี" }) {
                    foundSaraI = true
                    if showPrint { print("🟠 → Found ี within character at position i-\(offset): '\(charAtPos)'") }
                    break
                }
            }
            
            if foundSaraI {
                if showPrint { print("🟠 → IKKE ta ย som coda i เ◌ีย mønster - returning (false, \(i))") }
                return (false, i)
            } else {
                if showPrint { print("🟠 → No ี found, not a เ◌ีย pattern") }
            }
        }
        
        // 4c) ย + า → ikke ta ย som coda hvis det starter ordet eller følger vokal
        // Dette håndterer อยาก og lignende tilfeller
        if cand == "ย" && next == "า" {
            if showPrint { print("🟠 → IKKE ta ย som coda foran า (diphthong ยา)") }
            return (false, i)
        }
        
        // 4d) เ◌ื่ + อ → ikke ta อ som coda (เพื่อ type)
        // Also handle variations where tone mark might be at different positions
        if cand == "อ" {
            // เพื่อ: เ + พ + ื + ่ + อ, so อ at position i should not be coda
            // Check for ื and tone marks in nearby positions
            if i >= 1 && (chars[i-1] == "ื" || (i >= 2 && chars[i-2] == "ื" && toneMarks.contains(chars[i-1]))) {
                if showPrint { print("🟠 → IKKE ta อ som coda i เ◌ื(่)อ mønster") }
                return (false, i)
            }
        }
        
        // 4e) ต + ล + aa → ikke ta ล som coda (implicit vowel)
        if cand == "ล" && next == "า" && i >= 1 {
            if chars[i-1] == "ต" {
                if showPrint { print("🟠 → IKKE ta ล som coda i ตลา mønster") }
                return (false, i)
            }
        }
        
        // 5) Standard logikk: ta som coda hvis neste er konsonant, ellers ikke
        if Self.isConsonant(next) {
            if showPrint { print("🟠 → Generic rule: ta '\(cand)' som coda siden neste er konsonant '\(next)' - returning (true, \(j))") }
            return (true, j)
        }

        // 6) Fallback: ikke ta som koda (la neste stavelse håndtere)
        if showPrint { print("🟠 → Fallback: ikke ta '\(cand)' som coda - returning (false, \(i))") }
        return (false, i)
    }

    // MARK: - Word-level syllable segmentation
    /// Segments a single Thai word into syllables, optimized for word boundaries from HybridSegmentation
    static func segmentWordIntoSyllables(_ word: String) -> [ThaiSyllable] {
        // Use the existing segmentation logic but with word-level optimization
        var syllables = ThaiSeg.repairPreposedVowelNucleus(ThaiSeg.segmentThai(word))

        // Post-processing: Fix known misegmentations
        syllables = fixMissegmentedWords(syllables, originalWord: word)

        if showPrint {
            print("🔤 [WORD-SYLLABLE] '\(word)' → \(syllables.count) syllables:")
            for (i, syl) in syllables.enumerated() {
                print("🔤   [\(i+1)] '\(syl.original)' onset='\(syl.onset)' nucleus='\(syl.nucleus)' coda='\(syl.coda ?? "ø")'")
            }
        }

        return syllables
    }

    /// Fix common misegmentations where a single syllable is split incorrectly
    private static func fixMissegmentedWords(_ syllables: [ThaiSyllable], originalWord: String) -> [ThaiSyllable] {
        // Debug logging for problematic words
        let debugWords = ["ขึ้นรถ", "คอมพิวเตอร์", "จันทร์"]
        if debugWords.contains(originalWord) {
            print("🔴🔴🔴 fixMissegmentedWords called for '\(originalWord)'")
            print("  Input syllables count: \(syllables.count)")
            for (i, syl) in syllables.enumerated() {
                print("    [\(i)] '\(syl.original)'")
            }
        }

        // Special case for จันทร์ - should be one syllable
        if syllables.count == 3 &&
           originalWord == "จันทร์" &&
           syllables[0].original.contains("จัน") &&
           syllables[1].original == "ท" &&
           syllables[2].original.contains("ร์") {
            print("  ✅ จันทร์ fix matched!")
            // Merge all three into จันทร์
            let merged = ThaiSyllable(
                onset: "จ",
                nucleus: "ั",
                coda: "นทร์", // The whole นทร์ acts as coda (น is pronounced, ทร์ is silent)
                live: false,
                ipa: nil,
                toneMark: nil,
                range: syllables[0].range.lowerBound..<syllables[2].range.upperBound,
                original: "จันทร์",
                start: syllables[0].start,
                end: syllables[2].end
            )
            return [merged]
        }

        // Special case: if we have ร · ถ as separate syllables, merge them into รถ
        // Also handle เตอ · ร์ → เตอร์ pattern
        // Also handle ศัพ · ท์ → ศัพท์ pattern
        if syllables.count >= 2 {
            var fixed: [ThaiSyllable] = []
            var i = 0
            while i < syllables.count {
                // General rule: merge ร and ถ into รถ
                if i + 1 < syllables.count &&
                   syllables[i].original == "ร" &&
                   syllables[i+1].original == "ถ" {
                    print("  ✅ ร + ถ → รถ fix matched!")
                    // Merge ร and ถ into รถ
                    let mergedOriginal = "รถ"
                    let merged = ThaiSyllable(
                        onset: "ร",
                        nucleus: "อ̆", // implicit short vowel
                        coda: "ถ",
                        live: false, // รถ is a dead syllable
                        ipa: nil,
                        toneMark: nil,
                        range: syllables[i].range.lowerBound..<syllables[i+1].range.upperBound,
                        original: mergedOriginal,
                        start: syllables[i].start,
                        end: syllables[i+1].end
                    )
                    fixed.append(merged)
                    i += 2
                } else if i + 1 < syllables.count &&
                          syllables[i].original == "เตอ" &&
                          syllables[i+1].original == "ร์" {
                    print("  ✅ เตอ + ร์ → เตอร์ fix matched!")
                    // Merge เตอ and ร์ into เตอร์
                    let mergedOriginal = "เตอร์"
                    let merged = ThaiSyllable(
                        onset: "ต",
                        nucleus: "เอ",
                        coda: "ร์", // silenced ร as coda
                        live: false, // เตอร์ is a dead syllable
                        ipa: nil,
                        toneMark: syllables[i].toneMark ?? syllables[i+1].toneMark,
                        range: syllables[i].range.lowerBound..<syllables[i+1].range.upperBound,
                        original: mergedOriginal,
                        start: syllables[i].start,
                        end: syllables[i+1].end
                    )
                    fixed.append(merged)
                    i += 2
                } else {
                    // Check if this needs the generic silencer rule
                    // But only if it wasn't handled by specific rules above
                    if i + 1 < syllables.count &&
                       syllables[i+1].original.contains("์") &&
                       syllables[i+1].original.count <= 2 &&
                       // Exclude patterns handled above
                       !(syllables[i].original == "เตอ" && syllables[i+1].original == "ร์") {
                        // Generic rule: If next syllable is just a consonant with silencer
                        print("  ✅ Generic silencer fix: '\(syllables[i].original)' + '\(syllables[i+1].original)'")
                        let mergedOriginal = syllables[i].original + syllables[i+1].original
                        let merged = ThaiSyllable(
                            onset: syllables[i].onset,
                            nucleus: syllables[i].nucleus,
                            coda: syllables[i+1].original, // silenced consonant as coda
                            live: false, // syllables with silenced codas are dead
                            ipa: nil,
                            toneMark: syllables[i].toneMark,
                            range: syllables[i].range.lowerBound..<syllables[i+1].range.upperBound,
                            original: mergedOriginal,
                            start: syllables[i].start,
                            end: syllables[i+1].end
                        )
                        fixed.append(merged)
                        i += 2
                    } else {
                        fixed.append(syllables[i])
                        i += 1
                    }
                }
            }
            if fixed.count != syllables.count {
                if debugWords.contains(originalWord) {
                    print("  📌 Returning fixed syllables (count changed from \(syllables.count) to \(fixed.count))")
                }
                return fixed
            } else if debugWords.contains(originalWord) {
                print("  ⚠️ No fixes applied in loop")
            }
        }

        // If we have exactly 2 syllables and the second one is just a single consonant,
        // it's likely a misegmentation - merge them
        if syllables.count == 2 {
            let syl1 = syllables[0]
            let syl2 = syllables[1]

            // Check if second syllable is just a lone consonant (no explicit vowel, no tone mark)
            // Examples: พว + ก should be พวก as one syllable
            // But วัน + นี้ should NOT be merged (นี้ has explicit vowel and tone mark)
            let hasExplicitVowel = syl2.nucleus != "อ" && syl2.nucleus != ""
            let hasToneMark = syl2.toneMark != nil

            if syl2.original.count == 1 &&
               ThaiSeg.isConsonant(syl2.original.first!) &&
               !hasExplicitVowel &&
               !hasToneMark {
                // Merge: first syllable's structure + second as coda
                let mergedOriginal = syl1.original + syl2.original
                let codaChar = syl2.original.first!
                let codaString = String(codaChar)

                print("🔧 MERGE FIX: '\(syl1.original)' + '\(syl2.original)'")
                print("🔧   syl1.nucleus = '\(syl1.nucleus)'")
                print("🔧   coda = '\(codaChar)'")
                let vlen = vowelLength(for: syl1.nucleus)
                print("🔧   vowelLength = \(vlen)")
                let isLive = ThaiSeg.isLiveSyllable(nucleus: syl1.nucleus, coda: codaChar)
                print("🔧   isLive = \(isLive)")

                let merged = ThaiSyllable(
                    onset: syl1.onset,
                    nucleus: syl1.nucleus,
                    coda: codaString,
                    live: isLive,
                    ipa: nil,
                    toneMark: syl1.toneMark,
                    range: syl1.range.lowerBound..<syl2.range.upperBound,
                    original: mergedOriginal,
                    start: syl1.start,
                    end: syl2.end
                )
                return [merged]
            } else {
                print("🔧 NO MERGE: '\(syl1.original)' + '\(syl2.original)'")
                print("🔧   syl2.nucleus = '\(syl2.nucleus)' (hasExplicitVowel = \(hasExplicitVowel))")
                print("🔧   syl2.toneMark = '\(String(describing: syl2.toneMark))' (hasToneMark = \(hasToneMark))")
                print("🔧   syl2.original.count = \(syl2.original.count)")
            }
        }

        return syllables
    }

    // MARK: - Serialized Syllable Format

    /// Formaterer thai-tekst til JSON-array: "สวัสดี" → ["สวัส","ดี"]
    /// Bruker segmentThai() til å dele opp i stavelser.
    static func formatAsJSONArray(_ text: String) -> String {
        let syllables = ThaiSeg.segmentThai(text)
        guard !syllables.isEmpty else { return text }

        let parts = syllables.map { "\"\($0.original)\"" }
        return "[" + parts.joined(separator: ",") + "]"
    }

    /// Formaterer thai-tekst til JSON-array med mellomrom: "สวัสดี" → ["สวัส", "ดี"]
    static func formatAsJSONArraySpaced(_ text: String) -> String {
        let syllables = ThaiSeg.segmentThai(text)
        guard !syllables.isEmpty else { return text }

        let parts = syllables.map { "\"\($0.original)\"" }
        return "[" + parts.joined(separator: ", ") + "]"
    }

    /// Backwards-compatible wrapper for older call sites.
    static func formatWithBrackets(_ text: String) -> String {
        formatAsJSONArray(text)
    }

    /// Backwards-compatible wrapper for older call sites.
    static func formatWithBracketsSpaced(_ text: String) -> String {
        formatAsJSONArraySpaced(text)
    }
}

// MARK: - Debug-navnerom
enum ThaiDebug {
    @inlinable static func dbgOK(_ raw: String, _ i: Int) -> Bool {
        guard DBG_ON else { return false }
        if let f = DBG_ONLY_WORD, !raw.contains(f) { return false }
        return i >= DBG_MIN_I
    }
    @inlinable static func probeBegin(_ stage: String, i: Int, raw: String, chars: [Character]) {
        if dbgOK(raw, i) { print("🟢 probeBegin [\(stage)] i=\(i) rem='\(ThaiSeg.rem(chars, i))'") }
    }
    @inlinable static func probeStep(_ i0: Int, _ i1: Int, why: String, raw: String) {
        if dbgOK(raw, min(i0, i1)) { print("🟢 [STEP] i: \(i0) → \(i1)  why=\(why)") }
    }
    @inlinable static func probeEmit(_ s: ThaiSyllable, i: Int, raw: String) {
        if dbgOK(raw, i) { print("🟢 [EMIT] \(s.onset) | \(s.nucleus) | \(s.coda ?? "ø")  live=\(s.live)") }
    }
    
    /// Slår sammen feil-splittede preposed-klustre etter segmentering.
    ///  - เ◌ + (อะ)  → เ◌อะ   (kort ɤ)
    ///  - เ◌ + (อ)   → เ◌อ    (lang ɤː)
    ///  - ◌็ + (อ)   → ◌็อ    (kort ɔ)
   
        /// Slå sammen feil-splittede preposed-vokaler:
        ///  - เ◌ + อะ  → เ◌อะ   (kort ɤ)
        ///  - เ◌ + อ    → เ◌อ    (lang ɤː)
        ///  - ◌็ + อ    → ◌็อ    (kort ɔ)
        ///  - เ◌ื + อ   → เอือ   (ɯa)
        @inlinable
        static func repairPreposedVowelNucleus(_ syls: [ThaiSyllable]) -> [ThaiSyllable] {
            guard syls.count >= 2 else { return syls }
            var out: [ThaiSyllable] = []
            var i = 0

            @inline(__always)
            func stripTones(_ s: String) -> String {
                let strip: Set<Character> = ["่","้","๊","๋","์","ํ","\u{200C}","\u{200D}"]
                return String(s.filter { !strip.contains($0) })
            }

            while i < syls.count {
                let cur = syls[i]

                if i + 1 < syls.count {
                    let nxt = syls[i + 1]

                    // normaliser for trygge sammenligninger
                    let curNuc = stripTones(cur.nucleus)
                    let nxtNuc = stripTones(nxt.nucleus)
                    let nxtOrig = stripTones(nxt.original)

                    let looksPreposedE = curNuc.contains("เ")
                    let nextIsCarrierO = (nxt.onset == "อ" || nxt.onset == "ʔ" || nxt.onset.isEmpty)
                    let nextHasNoCoda  = (nxt.coda == nil || nxt.coda == "ø")

                    // A) เ◌ + อะ → เ◌อะ
                    let shouldMergeShort =
                        looksPreposedE && nextIsCarrierO && nextHasNoCoda &&
                        (nxtNuc == "ะ" || nxtOrig == "อะ")

                    // B) เ◌ + อ → เ◌อ
                    let shouldMergeLong =
                        looksPreposedE && nextIsCarrierO && nextHasNoCoda &&
                        (nxtNuc.isEmpty || nxtOrig == "อ")

                    // C) ◌็ + อ → ◌็อ
                    let looksMaiTaikhu = curNuc.contains("็")
                    let shouldMergeShortAw =
                        looksMaiTaikhu && nextIsCarrierO && nextHasNoCoda &&
                        (nxtNuc.isEmpty || nxtOrig == "อ")

                    // D) เ◌ื + อ → เอือ   (ɯa)
                    //   – cur-nucleus inneholder både preposed เ og
                    //   – neste stavelse er "อ" (carrier) uten koda
                    let containsSaraUe = curNuc.unicodeScalars.contains { Character($0) == "ื" }
                    let looksEPlusSaraUe = looksPreposedE && containsSaraUe
                    let shouldMergeEua =
                        looksEPlusSaraUe && nextIsCarrierO && nextHasNoCoda &&
                        (nxtNuc.isEmpty || nxtOrig == "อ")

                    if shouldMergeShort || shouldMergeLong || shouldMergeShortAw || shouldMergeEua {
                        let mergedNucleus: String = {
                            if shouldMergeShort    { return cur.nucleus + "อะ" } // เ◌ะ + อะ → เ◌อะ
                            if shouldMergeLong     { return cur.nucleus + "อ" }   // เ◌ + อ   → เ◌อ
                            if shouldMergeShortAw  { return cur.nucleus + "อ" }   // ◌็ + อ   → ◌็อ
                            /* shouldMergeEua */    return cur.nucleus + "อ"       // เ◌ื + อ  → เอือ
                        }()

                        let lower = min(cur.range.lowerBound, nxt.range.lowerBound)
                        let upper = max(cur.range.upperBound, nxt.range.upperBound)
                        let mergedRange = lower..<upper

                        let merged = ThaiSyllable(
                            onset:   cur.onset,
                            nucleus: mergedNucleus,
                            coda:    cur.coda,
                            live:    cur.live,
                            ipa:     nil,
                            toneMark: cur.toneMark ?? nxt.toneMark,
                            range:   mergedRange,
                            original: cur.original + nxt.original,
                            start:   mergedRange.lowerBound,
                            end:     mergedRange.upperBound
                        )

                        out.append(merged)
                        i += 2
                        continue
                    }
                }

                out.append(cur)
                i += 1
            }
            return out
        }
    }
