import Foundation

// MARK: - Debug version of segmentThai with extensive logging
extension ThaiSeg {

    static func debugSegmentThai(_ raw: String) -> [ThaiSyllable] {
        let text  = raw.precomposedStringWithCanonicalMapping
        let chars = Array(text)
        var i = 0
        var out: [ThaiSyllable] = []

        print("\n🟢🟣 [DEBUG START] \(raw)")
        print("     Characters: \(chars.map { "'\($0)'" }.joined(separator: ", "))")
        print("     Indices:    \((0..<chars.count).map { String($0) }.joined(separator: "   "))")

        var syllableNum = 0

        while i < chars.count {
            syllableNum += 1
            print("\n" + String(repeating: "━", count: 60))
            print("📍 SYLLABLE #\(syllableNum) starting at index \(i)")
            print(String(repeating: "━", count: 60))

            // START på stavelsen
            let syllStart = i

            // 0) Preposed vokaler
            var pre = ""
            var onset = ""
            var carried = ""
            var tone: Character? = nil

            print("\n🔵 STEP 1: Check for preposed vowels at i=\(i)")
            while i < chars.count, preposedVowels.contains(chars[i]) {
                pre.append(chars[i])
                print("   Found preposed vowel: '\(chars[i])' → pre='\(pre)'")
                if !ThaiSeg.advance(&i, limit: chars.count) { break }
            }

            var sawVowel = !pre.isEmpty
            print("   Result: pre='\(pre)', sawVowel=\(sawVowel), i=\(i)")

            // 1) ONSET
            print("\n🔵 STEP 2: Process ONSET at i=\(i)")
            guard i < chars.count else {
                print("   ⚠️ End of string, breaking")
                break
            }

            let ch = chars[i]
            print("   Current char: '\(ch)'")

            // Analyze the character
            print("   Unicode scalars in '\(ch)':")
            for scalar in ch.unicodeScalars {
                let c = Character(scalar)
                print("      - '\(c)' (U+\(String(format: "%04X", scalar.value)))")
            }

            let base = ThaiSeg.baseConsonant(ch) ?? ch
            print("   Base consonant: '\(base)'")

            if base == "อ", ThaiSeg.charHasVowelOrTone(ch) {
                print("   → Null onset case (อ with vowel/tone)")
                onset = "ʔ"
                // i økes IKKE her – nucleus spiser grafemet ved i
            } else if ThaiSeg.isConsonant(base) {
                print("   → Regular consonant onset")
                onset.append(base)

                // flytt evt. vokaler/tonemerker fra SAMME grafem til 'carried'
                print("   Extracting vowels/tones from '\(ch)':")
                for us in String(ch).unicodeScalars {
                    let m = Character(us)
                    if vowels.contains(m) {
                        carried.append(m)
                        sawVowel = true
                        print("      vowel '\(m)' → carried='\(carried)', sawVowel=true")
                    }
                    if toneMarks.contains(m) {
                        carried.append(m)
                        tone = m
                        print("      tone '\(m)' → carried='\(carried)', tone='\(m)'")
                    }
                    if preposedVowels.contains(m) {
                        carried.append(m)
                        print("      preposed '\(m)' → carried='\(carried)'")
                    }
                }

                _ = ThaiSeg.advance(&i, limit: chars.count)
                print("   Advanced to i=\(i)")

                // Check for consonant cluster
                let extra = ThaiSeg.eatInitialCluster(in: chars, i: &i, onset: &onset)
                if !extra.isEmpty {
                    carried += extra
                    print("   Cluster found, extra carried: '\(extra)'")
                }

                print("   ONSET RESULT: onset='\(onset)', carried='\(carried)', sawVowel=\(sawVowel), i=\(i)")
            } else {
                print("   → Not a consonant, skipping")
                _ = ThaiSeg.advance(&i, limit: chars.count)
                continue
            }

            // 2) NUCLEUS
            print("\n🔵 STEP 3: Process NUCLEUS at i=\(i)")
            var post = ""

            // Check what's at current position
            if i < chars.count {
                print("   Current char at i=\(i): '\(chars[i])'")
            } else {
                print("   At end of string")
            }

            // Check for null onset case
            if onset == "ʔ", i < chars.count {
                print("   → Null onset case, processing อ carrier")
                let g = chars[i]
                post.append("อ")
                sawVowel = true
                for us in String(g).unicodeScalars {
                    let c = Character(us)
                    if vowels.contains(c)     { post.append(c) }
                    if toneMarks.contains(c)  { tone = c; post.append(c) }
                }
                _ = ThaiSeg.advance(&i, limit: chars.count)
                print("   nucleus from carrier='\(g)' → post='\(post)' i=\(i)")
            }

            // CRITICAL CHECK FOR ื + อ pattern
            print("\n   🔴 CRITICAL: Check for ื + อ pattern")
            print("      carried='\(carried)'")
            print("      carried.contains('ื')=\(carried.contains("ื"))")
            if i < chars.count {
                print("      chars[i]='\(chars[i])'")
                print("      chars[i]=='อ'=\(chars[i] == "อ")")
            }

            if carried.contains("ื") && i < chars.count && chars[i] == "อ" {
                print("   ✅ FOUND ื + อ pattern! Consuming อ as part of nucleus")
                post.append("อ")
                sawVowel = true
                _ = ThaiSeg.advance(&i, limit: chars.count)
                print("   Added 'อ' for ื+อ pattern, post='\(post)', i=\(i)")
            } else if i < chars.count && chars[i] == "อ" && !sawVowel {
                print("   → Standalone อ (no vowel yet)")
                post.append("อ")
                sawVowel = true
                _ = ThaiSeg.advance(&i, limit: chars.count)
                print("   nucleus standalone 'อ', i=\(i)")
            } else {
                print("   → No อ pattern found")
            }

            // Process remaining vowels/tones
            print("\n   Checking for additional vowels/tones at i=\(i)")
            while i < chars.count, (vowels.contains(chars[i]) || toneMarks.contains(chars[i])) {
                let c = chars[i]
                print("      Found: '\(c)'")
                if vowels.contains(c)     { sawVowel = true }
                if toneMarks.contains(c)  { tone = c }
                post.append(c)
                if !ThaiSeg.advance(&i, limit: chars.count) { break }
            }
            print("   Post-vowel processing: post='\(post)', i=\(i)")

            // Handle diphthongs
            print("\n   Checking for diphthong patterns at i=\(i)")
            while i < chars.count {
                let nextChar = chars[i]
                var consumed = false

                if nextChar == "ย" {
                    print("      Found ย, checking for diphthong...")
                    // [diphthong logic here - abbreviated for space]
                    // ... existing diphthong code ...
                }

                if !consumed { break }
            }

            // Check if we need implicit vowel
            if !sawVowel {
                print("\n   ⚠️ No vowel found, adding implicit vowel")
                if i < chars.count && ThaiSeg.isConsonant(chars[i]) {
                    post.append("อ̆")
                    print("      Added implicit อ̆ for CC pattern")
                } else {
                    post.append("ะ")
                    print("      Added implicit ะ")
                }
            } else {
                print("\n   ✓ Has vowel (sawVowel=true)")
            }

            // Build nucleus
            let rawNucleus = pre + carried + post
            print("\n   Building nucleus: pre='\(pre)' + carried='\(carried)' + post='\(post)'")
            print("   rawNucleus='\(rawNucleus)'")

            var nucleus = ""
            for char in rawNucleus {
                for scalar in String(char).unicodeScalars {
                    let c = Character(scalar)
                    if !toneMarks.contains(c) {
                        nucleus.append(c)
                    }
                }
            }
            print("   nucleus (without tones)='\(nucleus)'")

            // 3) CODA
            print("\n🔵 STEP 4: Check for CODA at i=\(i)")
            var coda: Character? = nil

            if i < chars.count {
                print("   Current position i=\(i), char='\(chars[i])'")

                if ThaiSeg.isConsonant(chars[i]) {
                    let cand = chars[i]
                    print("   Candidate coda: '\(cand)'")

                    let decision = Self.shouldTakeAsCoda(at: i, in: chars)
                    print("   shouldTakeAsCoda returned: take=\(decision.take), advanceTo=\(decision.advanceTo)")

                    if decision.take {
                        coda = cand
                        i = decision.advanceTo
                        print("   ✓ Took '\(cand)' as coda, advanced to i=\(i)")
                    } else {
                        print("   ✗ Did not take '\(cand)' as coda")
                    }
                }
            } else {
                print("   At end of string, no coda")
            }

            // Determine live/dead
            let live = ThaiSeg.isLiveSyllable(nucleus: nucleus, coda: coda)
            print("\n   Live/Dead: \(live ? "LIVE" : "DEAD")")

            // Create syllable
            let range = syllStart..<i
            let original = String(chars[syllStart..<i])

            let syl = ThaiSyllable(
                onset: onset,
                nucleus: nucleus,
                coda: coda.map(String.init),
                live: live,
                ipa: nil,
                toneMark: tone,
                range: range,
                original: original,
                start: syllStart,
                end: i
            )

            print("\n📦 SYLLABLE CREATED:")
            print("   original: '\(original)'")
            print("   onset: '\(onset)'")
            print("   nucleus: '\(nucleus)'")
            print("   coda: '\(coda ?? "∅")'")
            print("   range: \(syllStart)..<\(i)")

            out.append(syl)
        }

        print("\n" + String(repeating: "═", count: 60))
        print("🏁 SEGMENTATION COMPLETE")
        print("   Total syllables: \(out.count)")
        for (i, syl) in out.enumerated() {
            print("   [\(i+1)] '\(syl.original)' = \(syl.onset) + \(syl.nucleus) + \(syl.coda ?? "∅")")
        }
        print(String(repeating: "═", count: 60))

        return out
    }
}
