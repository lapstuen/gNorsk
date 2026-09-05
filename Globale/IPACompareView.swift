//
//  IPACompareView.swift
//  gThai
//
//  Created by Geir Lapstuen on 9/5/25.
//
import SwiftUI

// Viser got IPA og expected IPA. Blir rødt hvis de ikke matcher.
private struct IPACompareView: View {
    let syls: [ThaiSyllable]
    let expectedIPA: String?   // fra TestCase.ipa
    
    var body: some View {
        // Beregn IPA ut fra stavelser (tilpass til din funksjon)
        let gotIPA = "xxxx" //ipaFromSyllables(syls)  // <- eksisterende funksjon hos deg
        let expected = expectedIPA ?? ""

        // Hvis vi har en fasit, marker mismatch i rødt. Hvis ikke, grå tekst.
        let mismatch = !expected.isEmpty && gotIPA != expected
        let color: Color = expected.isEmpty ? .secondary : (mismatch ? .red : .secondary)

        HStack(spacing: 8) {
            Text(gotIPA)     // Got IPA
                .foregroundColor(color)
            Text(expected.isEmpty ? "–" : expected)  // Expected IPA
                .foregroundColor(color)
        }
        .font(.callout)
    }
}
