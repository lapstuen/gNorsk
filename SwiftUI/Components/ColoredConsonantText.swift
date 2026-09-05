//
//  ColoredConsonantText.swift
//  gThai
//
//  Created by Claude on 12/3/25.
//

import SwiftUI

/// Viser thai-tekst med fargekodede konsonanter basert på konsonantklasse:
/// - Rød: Høye konsonanter (ข ฃ ฉ ฐ ถ ผ ฝ ศ ษ ส ห)
/// - Blå: Mellom-konsonanter (ก จ ฎ ฏ ด ต บ ป อ)
/// - Standard: Lave konsonanter og andre tegn
struct ColoredConsonantText: View {
    let text: String
    var fontSize: CGFloat = 30

    // Konsonantklasser fra ThaiToneLogic.swift
    private static let highConsonants = Set("ขฃฉฐถผฝศษสห")
    private static let midConsonants = Set("กจฎฏดตบปอ")

    var body: some View {
        textWithColors()
            .textSelection(.enabled)
    }

    @ViewBuilder
    private func textWithColors() -> Text {
        var result = Text("")

        for char in text {
            let color = colorForCharacter(char)
            result = result + Text(String(char))
                .foregroundColor(color)
                .font(.system(size: fontSize))
        }

        return result
    }

    private func colorForCharacter(_ char: Character) -> Color {
        // Sjekk base-tegnet (uten diakritiske merker)
        let baseChar = getBaseConsonant(char)

        if Self.highConsonants.contains(baseChar) {
            return .red          // Høy klasse
        } else if Self.midConsonants.contains(baseChar) {
            return .blue         // Mellom klasse
        } else if isThaiConsonant(baseChar) {
            return .green        // Lav klasse
        } else {
            return .primary      // Andre tegn (vokaler, tall, etc.)
        }
    }

    private func isThaiConsonant(_ char: Character) -> Bool {
        for scalar in char.unicodeScalars {
            if scalar.value >= 0x0E01 && scalar.value <= 0x0E2E {
                return true
            }
        }
        return false
    }

    /// Henter base-konsonanten fra et tegn (håndterer kombinerte tegn)
    private func getBaseConsonant(_ char: Character) -> Character {
        // For thai-tegn med diakritiske merker, hent base-tegnet
        for scalar in char.unicodeScalars {
            let baseChar = Character(scalar)
            if Self.highConsonants.contains(baseChar) || Self.midConsonants.contains(baseChar) {
                return baseChar
            }
            // Sjekk om det er en thai-konsonant (0E01-0E2E)
            if scalar.value >= 0x0E01 && scalar.value <= 0x0E2E {
                return baseChar
            }
        }
        return char
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        ColoredConsonantText(text: "สวัสดี", fontSize: 40)
        ColoredConsonantText(text: "[สวัส][ดี]", fontSize: 30)
        ColoredConsonantText(text: "ข้าว กิน ดี", fontSize: 30)

        Text("Legend:")
            .font(.headline)
        HStack {
            Circle().fill(.red).frame(width: 12, height: 12)
            Text("High consonant")
        }
        HStack {
            Circle().fill(.blue).frame(width: 12, height: 12)
            Text("Mid consonant")
        }
        HStack {
            Circle().fill(.primary).frame(width: 12, height: 12)
            Text("Low consonant / other")
        }
    }
    .padding()
}
