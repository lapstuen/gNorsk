import Foundation

// MARK: - Debug function for specific word
public func debugSegmentWord(_ word: String, verbose: Bool = true) -> [ThaiSyllable] {
    print("\n" + String(repeating: "=", count: 80))
    print("🔍 DEBUG SEGMENTATION FOR: '\(word)'")
    print(String(repeating: "=", count: 80))

    // Character analysis
    print("\n📊 CHARACTER ANALYSIS:")
    let chars = Array(word)
    print("Total characters: \(chars.count)")

    for (i, ch) in chars.enumerated() {
        print("\n  [\(i)] Character: '\(ch)'")
        print("      Unicode scalars:")
        for scalar in ch.unicodeScalars {
            let c = Character(scalar)
            let hex = String(format: "U+%04X", scalar.value)
            let name = getCharacterName(c)
            print("        - '\(c)' (\(hex)) = \(name)")

            // Check what sets this character belongs to
            if vowels.contains(c) { print("          ✓ Is in vowels set") }
            if toneMarks.contains(c) { print("          ✓ Is in toneMarks set") }
            if preposedVowels.contains(c) { print("          ✓ Is in preposedVowels set") }
            if allowedCoda.contains(c) { print("          ✓ Is in allowedCoda set") }
            if c == "อ" { print("          ⚠️ Is 'อ' (can be vowel carrier OR consonant)") }
        }
    }

    print("\n" + String(repeating: "-", count: 80))
    print("🚀 STARTING SEGMENTATION")
    print(String(repeating: "-", count: 80))

    // Call the actual segmentation with debug enabled
    let originalShowPrint = showPrint
    // Force enable debug printing temporarily
    // Note: we need to modify the actual segmentation to use this

    let syllables = ThaiSeg.segmentWordIntoSyllables(word)

    print("\n" + String(repeating: "-", count: 80))
    print("📝 SEGMENTATION RESULT")
    print(String(repeating: "-", count: 80))

    print("\nTotal syllables: \(syllables.count)")
    for (i, syl) in syllables.enumerated() {
        print("\n  Syllable \(i+1): '\(syl.original)'")
        print("    onset:   '\(syl.onset)' \(syl.onset == "ʔ" ? "(null onset)" : "")")
        print("    nucleus: '\(syl.nucleus)'")
        print("    coda:    '\(syl.coda ?? "∅")'")
        print("    live:    \(syl.live ? "✅ LIVE" : "❌ DEAD")")

        // Check IPA mapping for nucleus
        let nucleusIPA = ThaiIPA.ipaForVowel(nucleus: syl.nucleus, coda: syl.coda?.first)
        print("    nucleus IPA: '\(nucleusIPA)'")
    }

    // Compare with expected
    print("\n" + String(repeating: "-", count: 80))
    print("✅ EXPECTED vs ❌ ACTUAL")
    print(String(repeating: "-", count: 80))

    let expected = ["ซื้อ", "ของ"]
    let actual = syllables.map { $0.original }

    print("Expected: \(expected.joined(separator: " · "))")
    print("Actual:   \(actual.joined(separator: " · "))")

    if expected == actual {
        print("\n✅ SUCCESS! Segmentation is correct!")
    } else {
        print("\n❌ FAILED! Segmentation is incorrect!")
        print("\nDifferences:")
        for (i, (exp, act)) in zip(expected, actual).enumerated() {
            if exp != act {
                print("  Syllable \(i+1): expected '\(exp)', got '\(act)'")
            }
        }
        if expected.count != actual.count {
            print("  Count mismatch: expected \(expected.count) syllables, got \(actual.count)")
        }
    }

    print("\n" + String(repeating: "=", count: 80))
    print()

    return syllables
}

// Helper function to get character names
private func getCharacterName(_ c: Character) -> String {
    switch c {
    case "ซ": return "so sua (ซ)"
    case "ื": return "sara ue (ื)"
    case "้": return "mai tho (tone mark ้)"
    case "อ": return "o ang (อ)"
    case "ข": return "kho khai (ข)"
    case "ง": return "ngo ngu (ง)"
    default: return "character '\(c)'"
    }
}

// MARK: - Test function specifically for ซื้อของ
public func testซื้อของSegmentation() {
    print("\n🧪 TESTING: ซื้อของ")
    print("=" * 50)

    let result = debugSegmentWord("ซื้อของ")

    // Additional analysis for this specific word
    print("\n💡 ANALYSIS OF THE ISSUE:")
    print("-" * 50)

    print("""

    The word 'ซื้อของ' should be segmented as:
    1. ซื้อ (buy) - onset: ซ, nucleus: ื้อ, coda: ∅
    2. ของ (of/thing) - onset: ข, nucleus: อ, coda: ง

    Common issues:
    - The ื้ (sara ue + mai tho) might not be carrying the อ
    - The อ after ื้ might be starting a new syllable incorrectly
    - The vowel pattern ื้อ might not be recognized as a unit

    Current behavior:
    """)

    if result.count == 3 {
        print("  ⚠️ Getting 3 syllables instead of 2")
        print("  This suggests อ is being treated as a new syllable start")
        print("  Check if carried.contains('ื') check is working")
        print("  Check if the อ consumption logic at line ~98-107 is executing")
    }

    print("\n🔧 TO FIX THIS:")
    print("""
    1. Ensure ื is in 'carried' after processing ซื้
    2. Ensure the check for carried.contains("ื") is true
    3. Ensure อ is consumed as part of nucleus
    4. Verify that ือ or ื้อ is in the IPA vowel map
    """)
}

// Extension to make string multiplication work
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}