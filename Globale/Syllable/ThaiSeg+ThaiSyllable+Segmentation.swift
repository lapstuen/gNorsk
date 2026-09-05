//
//  ThaiSyllable+Segmentation.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/24/25.
//


import Foundation
import SwiftUI
import CoreData

extension ThaiSeg {
    
    // hovedfunksjonen for stavelser!!
    static func segmentThai(_ raw: String) -> [ThaiSyllable] {
        if let override = ThaiPronunciationOverrides.syllables(for: raw) {
            if showPrint { print("🟣 [OVERRIDE] \(raw) → \(override.map { $0.original })") }
            return override
        }
        let text  = raw.precomposedStringWithCanonicalMapping
        let chars = Array(text)
        var i = 0
        var out: [ThaiSyllable] = []
        
        if showPrint { print("🟢🟣 [START] \(raw)") }
        
        while i < chars.count {
            // START på stavelsen
            let syllStart = i
            
            // 0) Preposed vokaler
            var pre = ""
            var onset = ""
            var carried = ""
            var tone: Character? = nil
            
            while i < chars.count, preposedVowels.contains(chars[i]) {
                pre.append(chars[i])
                if !ThaiSeg.advance(&i, limit: chars.count) { break }
            }
            var sawVowel = !pre.isEmpty
            if showPrint { print("🟢 sawVowel init = \(sawVowel) (pre.isEmpty=\(pre.isEmpty))") }
            
            // 1) ONSET
            ThaiDebug.probeBegin("ONSET", i: i, raw: raw, chars: chars)
            guard i < chars.count else { break }
            
            let ch = chars[i]
            let base = ThaiSeg.baseConsonant(ch) ?? ch
            
            if base == "อ", ThaiSeg.charHasVowelOrTone(ch) {
                // bærer-tilfellet: null onset (ʔ), nucleus tar hele "อ…" senere
                onset = "ʔ"
                // i økes IKKE her – nucleus spiser grafemet ved i
            } else if ThaiSeg.isConsonant(base) {
                // legg bare base‑konsonanten
                onset.append(base)
                
                // flytt evt. vokaler/tonemerker fra SAMME grafem til 'carried'
                for us in String(ch).unicodeScalars {
                    let m = Character(us)
                    if vowels.contains(m)          { carried.append(m); sawVowel = true }
                    if toneMarks.contains(m)       { carried.append(m); tone = m }
                    if preposedVowels.contains(m)  { carried.append(m) }
                }
                
                // Vi har konsumert grafemet ved i → trygg økning
                _ = ThaiSeg.advance(&i, limit: chars.count)
                
                // Utvid onset med lovlig kluster (ekstra konsonanter).
                // NB: eatInitialCluster legger kun BASE-konsonanter i onset og
                // flytter markene til 'carried'.
                let extra = ThaiSeg.eatInitialCluster(in: chars, i: &i, onset: &onset, hasPendingVowel: carried.contains("ั"))
                if !extra.isEmpty {
                    carried += extra
                    // NB: itererer på unicodeScalars, ikke Character — flere
                    // kombinasjonsmerker uten grunntegn (f.eks. vokal+tonemerke
                    // "ุ่") slås sammen til ÉN Character i Swift, så et vanlig
                    // Character-basert `for c in extra` ville aldri matche
                    // verken vowels- eller toneMarks-settet.
                    for scalar in extra.unicodeScalars {
                        let c = Character(scalar)
                        if toneMarks.contains(c) { tone = c }
                        if vowels.contains(c)    { sawVowel = true }
                    }
                }
                
                if showPrint { print("🟢 onset='\(onset)' carried='\(carried)' i=\(i)") }
            } else {
                // ikke-konsonant → hopp til neste grafem
                _ = ThaiSeg.advance(&i, limit: chars.count)
                continue
            }
            
            // 2) NUCLEUS
            ThaiDebug.probeBegin("NUCLEUS", i: i, raw: raw, chars: chars)
            var post = ""

            // CRITICAL: Check for complex vowel patterns FIRST (like ื้อ)
            // This must happen BEFORE other nucleus processing
            if !carried.isEmpty && i < chars.count {
                if showPrint {
                    print("🔍 CHECKING COMPLEX VOWEL PATTERNS:")
                    print("   carried='\(carried)'")
                    print("   current position i=\(i)")
                    if i < chars.count { print("   next char='\(chars[i])'") }
                }

                // Check specifically for ื + อ pattern
                if chars[i] == "อ" {
                    let hasUe = carried.unicodeScalars.contains { $0 == "\u{0E37}" } // ื
                    if hasUe {
                        // CONSUME อ as part of the vowel pattern
                        post.append("อ")
                        sawVowel = true
                        _ = ThaiSeg.advance(&i, limit: chars.count)
                        if showPrint {
                            print("🟢✅ PATTERN RECOGNIZED: ื(้)อ")
                            print("     Consumed อ → post='\(post)', i=\(i)")
                        }
                    }
                }
            }

            // Regular nucleus processing
            if onset == "ʔ" && i < chars.count && !post.contains("อ") {
                let g = chars[i]
                post.append("อ"); sawVowel = true
                for us in String(g).unicodeScalars {
                    let c = Character(us)
                    if vowels.contains(c)     { post.append(c) }
                    if toneMarks.contains(c)  { tone = c; post.append(c) }
                }
                _ = ThaiSeg.advance(&i, limit: chars.count)
                if showPrint { print("🟢 nucleus from carrier='\(g)' → post='\(post)' i=\(i)") }
            } else if i < chars.count && chars[i] == "อ" && !sawVowel && !post.contains("อ") {
                // Only take standalone อ if we don't have a vowel yet and haven't already consumed it
                post.append("อ"); sawVowel = true
                _ = ThaiSeg.advance(&i, limit: chars.count)
                if showPrint { print("🟢 nucleus standalone 'อ', i=\(i)") }
            }

            while i < chars.count, (vowels.contains(chars[i]) || toneMarks.contains(chars[i])) {
                let c = chars[i]
                if vowels.contains(c)     { sawVowel = true }
                if toneMarks.contains(c)  { tone = c }
                post.append(c)
                if !ThaiSeg.advance(&i, limit: chars.count) { break }
                if showPrint { print("🟢 nucleus post='\(post)' i=\(i)") }
            }
            
            // Handle Thai diphthongs that end in consonants (เ◌ีย, เ◌อ, อ◌ย etc.)
            while i < chars.count {
                let nextChar = chars[i]
                var consumed = false
                
                // Check for เ◌ีย pattern: preposed เ + ี in previous chars + ย
                if nextChar == "ย" {
                    let hasPreposedE = !pre.isEmpty && pre.contains("เ")
                    let hasCarriedSaraI = carried.contains("ี")
                    let hasSaraI = post.contains("ี") || hasCarriedSaraI
                    
                    // Also check for ี in compound characters we've already processed
                    var foundSaraIInProcessed = hasSaraI
                    if !foundSaraIInProcessed && i > 0 {
                        // Look back at recently processed characters for ี
                        for lookBack in 1...min(3, i) {
                            if chars[i - lookBack].unicodeScalars.contains(where: { Character($0) == "ี" }) {
                                foundSaraIInProcessed = true
                                break
                            }
                        }
                    }
                    
                    if hasPreposedE && foundSaraIInProcessed {
                        // This is เ◌ีย pattern - consume ย as part of nucleus
                        post.append(nextChar)
                        _ = ThaiSeg.advance(&i, limit: chars.count)
                        if showPrint { print("🟢 nucleus consumed ย for เ◌ีย diphthong, i=\(i)") }
                        consumed = true
                    }
                    // Check for อ◌ย pattern (for อยาก)
                    else if onset == "ʔ" && post.contains("อ") {
                        post.append(nextChar)  
                        _ = ThaiSeg.advance(&i, limit: chars.count)
                        if showPrint { print("🟢 nucleus consumed ย for อ◌ย diphthong, i=\(i)") }
                        consumed = true
                    }
                }
                
                // Check for other diphthong patterns like เ◌อ
                else if nextChar == "อ" && !pre.isEmpty && pre.contains("เ") {
                    // เ◌อ pattern - consume อ as part of nucleus  
                    post.append(nextChar)
                    _ = ThaiSeg.advance(&i, limit: chars.count)
                    if showPrint { print("🟢 nucleus consumed อ for เ◌อ diphthong, i=\(i)") }
                    consumed = true
                }
                
                // Continue consuming vowels that are part of extended diphthongs
                else if vowels.contains(nextChar) && onset == "ʔ" {
                    post.append(nextChar)
                    _ = ThaiSeg.advance(&i, limit: chars.count) 
                    sawVowel = true
                    if showPrint { print("🟢 nucleus extended อ◌ vowel: '\(nextChar)', i=\(i)") }
                    consumed = true
                }
                // เ◌อะ pattern - consume ะ after เ◌อ
                else if nextChar == "ะ" && !pre.isEmpty && pre.contains("เ") && post.contains("อ") {
                    post.append(nextChar)
                    _ = ThaiSeg.advance(&i, limit: chars.count)
                    if showPrint { print("🟢 nucleus consumed ะ for เ◌อะ pattern, i=\(i)") }
                    consumed = true
                }
                
                if !consumed {
                    break
                }
            }
            
            if !sawVowel {
                // Isolated ว mellom konsonanter er som regel skjult vokal (ua), ikke coda.
                // Eksempel: ส่วน → ส + ่ + ว + น
                if onset != "ว",
                   i < chars.count,
                   chars[i] == "ว",
                   let nextAfterW = ThaiSeg.peek(chars, i, 1),
                   ThaiSeg.isConsonant(nextAfterW) {
                    post.append("ัว")
                    sawVowel = true
                    _ = ThaiSeg.advance(&i, limit: chars.count)
                    if showPrint { print("🟡 Treated isolated ว as hidden vowel 'ua', i=\\(i)") }
                }

                // Check if next character is a consonant that could be coda
                // (kun hvis ว-som-skjult-vokal-sjekken over IKKE allerede satte en vokal)
                if !sawVowel, i < chars.count, ThaiSeg.isConsonant(chars[i]) {
                    // Use inherent SHORT vowel for consonant-consonant patterns like คน
                    // Must be distinct from explicit อ (which is always long ɔː)
                    post.append("อ̆")
                    if showPrint { print("🟡 Added implicit short อ̆ for CC pattern, sawVowel=false") }
                } else if !sawVowel {
                    // Use ะ for other cases
                    post.append("ะ")
                    if showPrint { print("🟡 Added implicit ะ, sawVowel=false") }
                }
            } else {
                if showPrint { print("🟡 NO implicit vowel, sawVowel=true") }
            }

            // Build nucleus WITHOUT tone marks (tone marks are stored separately in 'tone' variable)
            // IMPORTANT: Decompose to handle combined characters like 'ี้' which is ี + ้ as one Character
            let rawNucleus = pre + carried + post
            var nucleus = ""
            for char in rawNucleus {
                // Decompose each character to separate combining marks
                for scalar in String(char).unicodeScalars {
                    let c = Character(scalar)
                    // Only add if it's NOT a tone mark
                    if !toneMarks.contains(c) {
                        nucleus.append(c)
                    }
                }
            }
            
            // 3) CODA
            var coda: Character? = nil
            if i < chars.count, ThaiSeg.isConsonant(chars[i]) {
                let cand = chars[i]
                let n1 = ThaiSeg.peek(chars, i, 1)
                let n2 = ThaiSeg.peek(chars, i, 2)
                let n3 = ThaiSeg.peek(chars, i, 3)
                
                let n1HasVowelOnSelf: Bool = {
                    guard let n1 else { return false }
                    if let b = ThaiSeg.baseConsonant(n1), ThaiSeg.isConsonant(b) {
                        return ThaiSeg.charHasVowelOrTone(n1)
                    }
                    return false
                }()
                
                let silenced = (cand == silencer) || (n1 == silencer)
                
                let candFormsNextCluster: Bool = {
                    guard let n1,
                          let bCand = ThaiSeg.baseConsonant(cand),
                          let b1 = ThaiSeg.baseConsonant(n1),
                          ThaiSeg.isConsonant(bCand), ThaiSeg.isConsonant(b1) else { return false }
                    return ThaiSeg.isValidInitialCluster(bCand, b1)
                }()
                
                let startsAsV   = ThaiSeg.isVowelStarter(n1)
                let startsAsCV  = (n1 != nil && ThaiSeg.isConsonant(n1!) && ThaiSeg.isVowelStarter(n2))
                let startsAsCCV = (
                    n1 != nil && n2 != nil && n3 != nil &&
                    ThaiSeg.isConsonant(n1!) && ThaiSeg.isConsonant(n2!) &&
                    ThaiSeg.isValidInitialCluster(ThaiSeg.baseConsonant(n1!)!, ThaiSeg.baseConsonant(n2!)!) &&
                    ThaiSeg.isVowelStarter(n3)
                )
                
                let boundaryOrEnd: Bool = {
                    guard let ch = n1 else { return true }
                    let isThai = ("ก"..."ฮ").contains(ch) || preposedVowels.contains(ch) ||
                    vowels.contains(ch) || toneMarks.contains(ch) || ch == "อ"
                    return !isThai
                }()
                
                let nextStartsSyllable = startsAsV || startsAsCV || startsAsCCV || n1HasVowelOnSelf || boundaryOrEnd
                
                if showPrint {
                    print("🟢 [CODA?] i=\(i) cand=\(cand) n1=\(String(n1 ?? "∅")) n2=\(String(n2 ?? "∅")) n3=\(String(n3 ?? "∅")) " +
                          "nextStarts=\(nextStartsSyllable) candFormsNextCluster=\(candFormsNextCluster)")
                }
                
                let nextIsConsonant = (n1 != nil && ThaiSeg.isConsonant(n1!))
                let nextIsPreposedVowel = (n1 != nil && preposedVowels.contains(n1!))
                
                // 🍀 Spesial-case: ...ง + (konsonant)  → ta 'ง' som koda og start ny stavelse
                // Bruk samlet beslutningsfunksjon:
                let decision = Self.shouldTakeAsCoda(at: i, in: chars)
                if decision.take {
                    coda = cand
                    i = decision.advanceTo
                    if showPrint { print("🟢 [STEP] consumed CODA '\(cand)' i=\(i)") }
                } else if decision.advanceTo != i {
                    // shouldTakeAsCoda rejected coda but wants us to advance (e.g., skip over diphthong parts)
                    i = decision.advanceTo
                    if showPrint { print("🟢 [STEP] skipped diphthong part, advanced to i=\(i)") }
                }
                // ← behold ALT under her (din opprinnelige if med !candFormsNextCluster, nextStartsSyllable, osv.)
                else if !silenced,
                        (allowedCoda.contains(cand) || cand == "ะ"),
                        !candFormsNextCluster,
                        nextStartsSyllable,
                        !shouldSkipCoda(cand: cand, n1: n1, context: chars, i: i)  // Thai diphthong regler
                {
                    coda = cand
                    _ = ThaiSeg.advance(&i, limit: chars.count)
                    if showPrint { print("🟢 [STEP] consumed CODA '\(cand)' i=\(i)") }
                }
            }
            
            // END på stavelsen
            let syllEnd = i
            let originalSlice = String(chars[syllStart..<syllEnd])
            
            let s = ThaiSyllable(
                onset: onset,
                nucleus: nucleus,
                coda: coda.map(String.init),
                live: ThaiSeg.isLiveSyllable(nucleus: nucleus, coda: coda),
                ipa: "xxx",
                toneMark: tone,
                range: syllStart..<syllEnd,
                original: originalSlice,
                start: syllStart,
                end: syllEnd
            )
            out.append(s)
            
            if showPrint {
                print("🟢🟣 [SYLLABLE] '\(s.writtenForm)' onset='\(s.onset)' nucleus='\(s.nucleus)' coda='\(s.coda ?? "ø")'")
            }
        }
        
        return out
    }
    


        /// Slå sammen feil-splittede preposed-vokaler:
        ///  - เ◌ + อะ  → เ◌อะ   (kort ɤ)
        ///  - เ◌ + อ    → เ◌อ    (lang ɤː)
        ///  - ◌็ + อ    → ◌็อ    (kort ɔ)
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

                    // normaliser "visuelle" felt
                    let curNuc = stripTones(cur.nucleus)
                    let nxtNuc = stripTones(nxt.nucleus)
                    let nxtOrig = stripTones(nxt.original)

                    // preposed 'เ' i første del?
                    let looksPreposedE = curNuc.contains("เ")
                    // neste er "อ"-carrier på ulike måter
                    let nextIsCarrierO = (nxt.onset == "อ" || nxt.onset == "ʔ" || nxt.onset.isEmpty)

                    // ——— SAMLE alle måter 2. del kan se ut på:
                    // A) เ◌ + อะ → เ◌อะ
                    let shouldMergeShort =
                        looksPreposedE &&
                        nextIsCarrierO &&
                        (
                            nxtNuc == "ะ" || nxtOrig == "อะ"   // ← robust: match på original også
                        ) &&
                        (nxt.coda == nil || nxt.coda == "ø")

                    // B) เ◌ + อ → เ◌อ
                    let shouldMergeLong =
                        looksPreposedE &&
                        nextIsCarrierO &&
                        (
                            nxtNuc.isEmpty || nxtOrig == "อ"   // ← noen parser-varianter legger hele "อ" i original
                        ) &&
                        (nxt.coda == nil || nxt.coda == "ø")

                    // C) ◌็ + อ → ◌็อ  (kort ɔ)
                    let looksMaiTaikhu = curNuc.contains("็")
                    let shouldMergeShortAw =
                        looksMaiTaikhu &&
                        nextIsCarrierO &&
                        (
                            nxtNuc.isEmpty || nxtOrig == "อ"
                        ) &&
                        (nxt.coda == nil || nxt.coda == "ø")

                    // D) เ◌ื + อ → เอือ   (ɯa)
                    let containsSaraUe = curNuc.unicodeScalars.contains { Character($0) == "ื" }
                    let looksEPlusSaraUe = looksPreposedE && containsSaraUe
                    let shouldMergeEua =
                        looksEPlusSaraUe &&
                        nextIsCarrierO &&
                        (
                            nxtNuc.isEmpty || nxtOrig == "อ"
                        ) &&
                        (nxt.coda == nil || nxt.coda == "ø")

                    if shouldMergeShort || shouldMergeLong || shouldMergeShortAw || shouldMergeEua {
                        let mergedNucleus: String = {
                            if shouldMergeShort    { return cur.nucleus + "อะ" }  // เ◌ะ + อะ → เ◌อะ
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
                            coda:    cur.coda,                       // behold ev. koda
                            live:    cur.live,                       // kan evt. beregnes på nytt
                            ipa:     nil,                            // genereres senere
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

// Helper function for Thai diphthong rules  
private func shouldSkipCoda(cand: Character, n1: Character?, context: [Character], i: Int) -> Bool {
        // ษ + า → skip coda
        if cand == "ษ" && n1 == "า" { return true }
        
        // เ◌ีย + น/ม/ง → skip ย coda
        if cand == "ย", let next = n1, (next == "น" || next == "ม" || next == "ง") {
            if i >= 2 && context[i-2] == "ี" { return true }
        }
        
        // อ + ย + า → skip ย coda
        if cand == "ย" && n1 == "า" {
            if i > 0 && context[i-1] == "อ" { return true }
        }
        
        // เ◌ื่ + อ → skip อ coda
        if cand == "อ" && i >= 2 {
            if context[i-2] == "ื" && context[i-1] == "่" { return true }
        }
        
        // Any consonant + sara aa (า) → consonant is onset of next syllable (not a coda)
        // e.g., เวลา: ล+า → ล starts ลา; สาขา: ข+า → ข starts ขา
        // (the sara aa cannot follow a coda — it always follows its own onset)
        if n1 == "า" { return true }

        return false
    }
    
    /// Brukes i coda-proben. Returnerer om vi skal ta tegn som koda og hvor vi skal fortsette.
    
// MARK: - DB Lexicon + Shortest Split (Level-2 refinement per word)

/// Simple in-memory cache for DB lexicon lookups to avoid repeated fetches
private actor DBLexiconCache {
    static let shared = DBLexiconCache()
    private var cached: Set<String>? = nil

    func get() -> Set<String>? { cached }
    func set(_ set: Set<String>) { cached = set }
}

/// Build or reuse a Set of all ThaiWords.thaiWord from Core Data
/// If your dataset is very large, consider scoping to relevant prefixes or families.
func buildDBLexicon(context: NSManagedObjectContext) -> Set<String> {
    // Try cache first
    if let cached = awaitOrNil({ await DBLexiconCache.shared.get() }) {
        return cached
    }
    let req = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
    req.resultType = .dictionaryResultType
    req.propertiesToFetch = ["thaiWord"]

    var out = Set<String>()
    do {
        if let rows = try context.fetch(req) as? [[String: Any]] {
            for row in rows {
                if let w = row["thaiWord"] as? String, !w.isEmpty {
                    out.insert(w.precomposedStringWithCanonicalMapping)
                }
            }
        }
    } catch {
        // If fetch fails, return empty set (caller can still proceed)
    }
    Task { await DBLexiconCache.shared.set(out) }
    return out
}

/// Utility to await an async closure where awaiting from sync context is needed
private func awaitOrNil<T>(_ body: @escaping () async -> T?) -> T? {
    var result: T?
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        result = await body()
        semaphore.signal()
    }
    semaphore.wait()
    return result
}

/// Split a single word into the shortest (i.e., most pieces) sequence of DB words.
/// - Returns: An array of DB sub-words. If no split is possible, returns an empty array.
func dbShortestSplit(of word: String, context: NSManagedObjectContext, lexicon: Set<String>? = nil) -> [String] {
    let s = word.precomposedStringWithCanonicalMapping
    if s.isEmpty { return [] }

    let lex: Set<String>
    if let provided = lexicon {
        lex = provided
    } else {
        lex = buildDBLexicon(context: context)
    }
    if lex.isEmpty { return [] }

    let chars = Array(s)
    let n = chars.count
    // dp[i] = (count, nextIndex) for best segmentation from i
    var dp = Array(repeating: (-1, -1), count: n + 1) // count, next
    dp[n] = (0, -1) // base case: 0 words from end

    // Precompute substrings for speed
    func substring(_ i: Int, _ j: Int) -> String {
        String(chars[i..<j])
    }

    // Fill dp from end to start
    if n > 0 {
        for i in stride(from: n - 1, through: 0, by: -1) {
            var bestCount = -1
            var bestNext = -1
            // Try all j > i
            var j = i + 1
            while j <= n {
                let sub = substring(i, j)
                if lex.contains(sub) {
                    let (cntNext, _) = dp[j]
                    if cntNext >= 0 {
                        let candidate = 1 + cntNext
                        if candidate > bestCount {
                            bestCount = candidate
                            bestNext = j
                        }
                    }
                }
                j += 1
            }
            dp[i] = (bestCount, bestNext)
        }
    }

    // Reconstruct best segmentation
    var out: [String] = []
    var i = 0
    while i < n {
        let (cnt, next) = dp[i]
        if cnt <= 0 || next <= i { break } // no more DB pieces
        out.append(substring(i, next))
        i = next
    }

    // If no pieces, return empty → caller can keep original word as level-1
    return out
}
