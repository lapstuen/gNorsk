import Foundation

// MARK: - Thai Vowel Pattern Recognition
// This file handles complex Thai vowel patterns that span multiple characters

public struct ThaiVowelPattern {
    let pattern: String
    let components: [String]
    let ipa: String
    let isLong: Bool

    // Checks if this pattern exists starting at the given position
    func matches(in chars: [Character], at index: Int, carried: String) -> Bool {
        // Check if we have the carried part (like ื้) and next char matches
        if pattern == "ื้อ" {
            // Check if carried contains ื and ้, and next char is อ
            let hasUe = carried.unicodeScalars.contains { $0 == "\u{0E37}" } // ื
            let hasTone = carried.unicodeScalars.contains { $0 == "\u{0E49}" } // ้
            let nextIsO = index < chars.count && chars[index] == "อ"
            return hasUe && hasTone && nextIsO
        }

        if pattern == "ือ" {
            // Check if carried contains ื (without tone), and next char is อ
            let hasUe = carried.unicodeScalars.contains { $0 == "\u{0E37}" } // ื
            let hasTone = carried.unicodeScalars.contains { scalar in toneMarks.contains(Character(scalar)) }
            let nextIsO = index < chars.count && chars[index] == "อ"
            return hasUe && !hasTone && nextIsO
        }

        return false
    }
}

// MARK: - Vowel patterns that need special handling
public let complexVowelPatterns: [ThaiVowelPattern] = [
    // ื + อ patterns
    ThaiVowelPattern(pattern: "ื้อ", components: ["ื", "้", "อ"], ipa: "ɯː", isLong: true),
    ThaiVowelPattern(pattern: "ือ", components: ["ื", "อ"], ipa: "ɯː", isLong: true),

    // Other complex patterns can be added here
    ThaiVowelPattern(pattern: "เือ", components: ["เ", "ื", "อ"], ipa: "ɯːa", isLong: true),
]

// MARK: - Helper to detect and consume complex vowel patterns
extension ThaiSeg {

    /// Check if we should consume อ as part of a vowel pattern
    /// This is called BEFORE regular nucleus processing
    static func shouldConsumeAsVowelPattern(chars: [Character], at index: Int, carried: String) -> Bool {
        // Critical check for ื + อ pattern
        if index < chars.count && chars[index] == "อ" {
            // Check if carried contains sara ue (ื) at Unicode level
            let hasUe = carried.unicodeScalars.contains { $0 == "\u{0E37}" }

            if hasUe {
                if showPrint {
                    print("🟢 PATTERN MATCH: Found ื in carried '\(carried)', next is อ → will form ือ/ื้อ pattern")
                }
                return true
            }
        }

        return false
    }

    /// Process complex vowel patterns during segmentation
    static func processComplexVowelPattern(
        chars: [Character],
        index: inout Int,
        carried: String,
        post: inout String,
        sawVowel: inout Bool
    ) -> Bool {
        // Check for ื + อ pattern
        if shouldConsumeAsVowelPattern(chars: chars, at: index, carried: carried) {
            post.append("อ")
            sawVowel = true
            _ = advance(&index, limit: chars.count)

            if showPrint {
                print("🟢✅ CONSUMED อ for vowel pattern ื(้)อ")
                print("     carried='\(carried)', post now='\(post)', index now=\(index)")
            }
            return true
        }

        return false
    }
}