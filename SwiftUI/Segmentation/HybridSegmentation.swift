import Foundation
import CoreData
import NaturalLanguage

enum HybridSegmentation {

    /// Smart segmentering med force breakdown for lange uttrykk
    static func segmentText(_ text: String, context: NSManagedObjectContext) -> [WordHit] {
        print("🚀 HybridSegmentation starter med tekst: '\(text)'")

        // FIRST: Check if entire text has Python NLP syllable data
        let nlpResult = ThaiNLPData.lookup(text, context: context)
        if nlpResult.isPreComputed && !nlpResult.syllables.isEmpty {
            print("✅ Bruker Python NLP stavelser: \(nlpResult.syllables)")

            // Post-process: Check if consecutive syllables form compound words
            let hits = findCompoundWords(syllables: nlpResult.syllables, context: context)

            print("✅ HybridSegmentation fullført med Python NLP: \(hits.count) hits")
            for (i, hit) in hits.enumerated() {
                print("  \(i + 1). '\(hit.thai)' → '\(hit.english ?? "nil")'")
            }

            return hits
        }

        print("⚠️ Ingen Python NLP data - bruker ThaiSeg stavelser som fallback")

        // FALLBACK: Use ThaiSeg syllables + compound word detection
        // (same approach as Python NLP path, but with ThaiSeg-generated syllables)
        let thaiSegSyllables = ThaiSeg.segmentWordIntoSyllables(text)
        let syllableStrings = thaiSegSyllables.map { $0.original }
        print("🔍 ThaiSeg fant \(syllableStrings.count) stavelser: \(syllableStrings)")

        let hits = findCompoundWords(syllables: syllableStrings, context: context)

        print("✅ HybridSegmentation fullført med ThaiSeg: \(hits.count) hits")
        for (i, hit) in hits.enumerated() {
            print("  \(i + 1). '\(hit.thai)' → '\(hit.english ?? "nil")'")
        }

        return hits
    }

    // MARK: - Compound Word Detection

    /// Find compound words from syllables and create hierarchical hits
    /// Example: ["วัน", "นี้"] → "วันนี้" (today) + syllables as children
    private static func findCompoundWords(syllables: [String], context: NSManagedObjectContext, maxLength: Int? = nil) -> [WordHit] {
        var hits: [WordHit] = []
        var i = 0

        while i < syllables.count {
            var foundCompound = false

            // Try combining 2, 3, 4+ syllables
            let effectiveMax = maxLength ?? min(5, syllables.count - i)
            for length in stride(from: min(effectiveMax, syllables.count - i), through: 2, by: -1) {
                let combined = syllables[i..<i+length].joined()
                let english = ThaiLexicon.resolveEnglish(combined)
                print("🔍 Prøver '\(combined)' (\(length) stavelser) → '\(english)'")

                if english != "—" {
                    print("✅ Fant sammensatt ord: '\(combined)' (\(length) stavelser) → '\(english)'")

                    // Create children — find sub-compounds if 3+ syllables
                    let childSyllables = Array(syllables[i..<i+length])
                    let children: [WordHit]
                    if childSyllables.count > 2 {
                        children = findCompoundWords(syllables: childSyllables, context: context, maxLength: 2)
                    } else {
                        children = childSyllables.map { syllable in
                            let eng = ThaiLexicon.resolveEnglish(syllable)
                            return WordHit(thai: syllable, english: eng == "—" ? nil : eng, children: nil)
                        }
                    }

                    // Add compound word with children
                    hits.append(WordHit(
                        thai: combined,
                        english: english,
                        children: children
                    ))

                    i += length
                    foundCompound = true
                    break
                }
            }

            // If no compound found, add single syllable
            if !foundCompound {
                let syllable = syllables[i]
                let english = ThaiLexicon.resolveEnglish(syllable)
                hits.append(WordHit(
                    thai: syllable,
                    english: english == "—" ? nil : english,
                    children: nil
                ))
                i += 1
            }
        }

        return hits
    }

    // MARK: - Prefix Scanner (samme som før)
    private static func prefixScanForComponents(_ word: String, context: NSManagedObjectContext) -> [WordHit] {
        var hits: [WordHit] = []
        var remaining = word

        while !remaining.isEmpty {
            var found = false

            // Søk korteste match først - FIX: inkluder hele remaining
            for length in 1...remaining.count {
                let prefix = String(remaining.prefix(length))
                let english = ThaiLexicon.resolveEnglish(prefix)

                if english != "—" {
                    print("🔍 Fant komponent: '\(prefix)' → '\(english)'")
                    hits.append(WordHit(thai: prefix, english: english))
                    remaining = String(remaining.dropFirst(length))
                    found = true
                    break
                }
            }

            // Hvis ingen match funnet: håndter enkelt tegn
            if !found {
                print("⚠️ Ingen match for: '\(remaining)' - tar første tegn")
                let firstChar = String(remaining.prefix(1))
                hits.append(WordHit(thai: firstChar, english: nil))
                remaining = String(remaining.dropFirst(1))
            }
        }

        return hits
    }

    // MARK: - Manual Segmentation for Long Text
    private static func manuallySegmentLongText(_ text: String, context: NSManagedObjectContext) -> [WordHit] {
        print("🔧 Manuell segmentering av lang tekst: '\(String(text.prefix(50)))...'")

        var hits: [WordHit] = []
        var remaining = text

        // Del opp basert på space/whitespace først
        let spaceSeparated = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        for chunk in spaceSeparated {
            // Hvis chunk fortsatt er lang, kjør prefix-scanning
            if chunk.count > 20 {
                let componentHits = prefixScanForComponents(chunk, context: context)
                hits.append(contentsOf: componentHits)
            } else {
                // Normal behandling for kortere chunks
                let english = ThaiLexicon.resolveEnglish(chunk)
                if english != "—" {
                    hits.append(WordHit(thai: chunk, english: english))
                } else {
                    // Kjør prefix-scan for ukjente ord
                    let componentHits = prefixScanForComponents(chunk, context: context)
                    hits.append(contentsOf: componentHits)
                }
            }
        }

        print("🔧 Manuell segmentering ga \(hits.count) hits")
        return hits
    }

    // MARK: - NL Tokenizer med bedre håndtering
    private static func tokenizeWithNL(_ text: String) -> [String] {
        print("🔤 Tokenizer starter med tekst lengde: \(text.count)")
        print("🔤 Første 50 tegn: '\(String(text.prefix(50)))'")

        let tok = NLTokenizer(unit: .word)
        tok.setLanguage(.thai)
        tok.string = text

        var words: [String] = []
        var currentIndex = text.startIndex

        tok.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range])
            print("🔤 Token funnet: '\(word)' (lengde: \(word.count))")

            // Håndter gap mellom tokens (emojis, whitespace, etc.)
            if currentIndex < range.lowerBound {
                let gap = String(text[currentIndex..<range.lowerBound])
                if !gap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("🔤 Gap funnet: '\(gap)'")
                    words.append(gap)
                }
            }

            words.append(word)
            currentIndex = range.upperBound
            return true
        }

        // Håndter eventuell rest på slutten
        if currentIndex < text.endIndex {
            let remaining = String(text[currentIndex..<text.endIndex])
            if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("🔤 Rest på slutten: '\(remaining)'")
                words.append(remaining)
            }
        }

        print("🔤 Tokenizer fullført: \(words.count) tokens")
        return words
    }
}

// MARK: - String Extensions
extension String {
    var containsEmoji: Bool {
        return unicodeScalars.contains { scalar in
            scalar.properties.isEmoji
        }
    }

    var containsThaiCharacters: Bool {
        return unicodeScalars.contains { scalar in
            (0x0E00...0x0E7F).contains(scalar.value)
        }
    }
}