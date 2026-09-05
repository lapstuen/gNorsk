#!/usr/bin/env swift

import Foundation

// Test the word ซื้อของ with detailed debugging

let word = "ซื้อของ"
print("\n🧪 TESTING WORD: \(word)")
print("Expected segmentation: ซื้อ · ของ")
print("\n" + String(repeating: "=", count: 60))

// First, let's understand the character structure
print("\n📊 CHARACTER BREAKDOWN:")
let chars = Array(word)
print("Total characters: \(chars.count)")

for (i, ch) in chars.enumerated() {
    print("\n[\(i)] '\(ch)':")
    for scalar in ch.unicodeScalars {
        let hex = String(format: "U+%04X", scalar.value)
        print("    - Unicode: \(hex) = '\(Character(scalar))'")
    }
}

print("\n" + String(repeating: "=", count: 60))
print("\n📝 KEY OBSERVATIONS:")
print("""
- Character 0: 'ซื้' contains ซ + ื + ้ (consonant + vowel + tone)
- Character 1: 'อ' - should complete the vowel pattern ื้อ
- Character 2: 'ข' - start of second syllable
- Character 3: 'อ' - vowel for second syllable
- Character 4: 'ง' - coda for second syllable

PROBLEM: After processing char 0 (ซื้), the อ at char 1 should be
consumed as part of the nucleus to form the complete vowel ื้อ.

If อ starts a new syllable instead, we get the wrong segmentation:
ซื้ · อข · อง (WRONG) instead of ซื้อ · ของ (CORRECT)
""")

print("\n" + String(repeating: "=", count: 60))
print("\n🔧 THE FIX SHOULD:")
print("""
1. After processing 'ซื้', carried should contain 'ื้'
2. At index 1, check if carried contains 'ื'
3. If yes AND next char is 'อ', consume it as part of nucleus
4. Result: nucleus = 'ื้อ' (or 'ือ' after removing tone)
""")

print("\n" + String(repeating: "=", count: 60))