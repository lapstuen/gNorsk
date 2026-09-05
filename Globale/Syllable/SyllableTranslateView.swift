//
//  SyllableTranslateView.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/24/25.
//


import SwiftUI

struct SyllableTranslateView: View {
    @Binding var thaiWord: String

    @State private var wholeEN: String? = nil   // valgfritt: oversett hele ordet
    @State private var rows: [SyllableMeaning] = []
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(thaiWord).font(.title2).bold()

            if let wholeEN {
                Text(wholeEN).font(.callout).foregroundStyle(.secondary)
            }

            // Enkel tabell over stavelser
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        Text("x").foregroundColor(.secondary)
                        Text(row.thai).font(.headline)
                        Text("y").foregroundColor(.secondary)
                        Text("→ \(row.english)").font(.callout).foregroundStyle(.secondary)
                    }
                }
                if rows.isEmpty, !thaiWord.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Ingen stavelser").foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .task(id: thaiWord) { await compute() }
    }

    @MainActor
    private func compute() async {
        loading = true
        defer { loading = false }

       // let syllables = ThaiSeg.segmentThai(thaiWord)        // bruker din frie funksjon
        
        let syllables = ThaiSeg.repairPreposedVowelNucleus(ThaiSeg.segmentThai(thaiWord))
        rows = syllables.map { SyllableMeaning(syllable: $0) }

        // Valgfritt: hel‑ord‑oversettelse (kan byttes til egen lookup hvis du ønsker)
        wholeEN = ThaiLexicon.resolveEnglish(thaiWord)
    }
}

// MARK: - Preview (Mac Catalyst OK)
private struct _SyllableTranslatePreview: View {
    @State var word = "ขออันนี้ครับ"
    var body: some View {
        SyllableTranslateView(thaiWord: $word)
            .frame(width: 520, height: 360)
            .padding()
    }
}

#Preview {
    _SyllableTranslatePreview()
}
