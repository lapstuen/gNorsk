import Foundation
import NaturalLanguage

enum NLTokenizerTest {
    static func testTokenization() {
        let testTexts = [
            "นอนไม่หลับ",
            "ฉันกำลังขับรถ", 
            "ไม่",
            "นอน หลับ"  // med mellomrom
        ]
        
        for text in testTexts {
            print("\n📝 Testing: '\(text)'")
            let tok = NLTokenizer(unit: .word)
            tok.setLanguage(.thai)
            tok.string = text
            
            var tokens: [String] = []
            tok.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                let token = String(text[range])
                tokens.append(token)
                print("  Token: '\(token)'")
                return true
            }
            print("  Total tokens: \(tokens)")
        }
    }
}