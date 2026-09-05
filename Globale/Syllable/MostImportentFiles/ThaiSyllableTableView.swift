import SwiftUI
import CoreData
import NaturalLanguage

// MARK: - ThaiSyllableTableView
struct ThaiSyllableTableView: View {
    let text: String

    var body: some View {
        // 1. Først: Del teksten i ORD med NLTokenizer
        let words = tokenizeThaiWords(text)
        let _ = print("🔵 ThaiSyllableTableView - Input: '\(text)'")
        let _ = print("🔵 Tokenized words: \(words)")

        // 2. Deretter: Bruk bare stavelsesdata som allerede finnes i DB
        let syls = words.flatMap { word -> [ThaiSyllable] in
            let normalizedWord = word.precomposedStringWithCanonicalMapping
            let dbWord = GlFunctions.shared.getWordCoreData(thaiWord: normalizedWord).first
            let dbSyllables = dbWord?.syllables ?? []

            guard !dbSyllables.isEmpty else {
                print("🔴   Word '\(word)' mangler syllable-data i DB")
                return []
            }

            print("🔵   Word '\(word)' → DB syllables: \(dbSyllables)")

            return dbSyllables.map { piece in
                ThaiSyllable(
                    onset: "",
                    nucleus: "",
                    coda: nil,
                    live: true,
                    ipa: dbWord?.ipa,
                    toneMark: nil,
                    range: 0..<piece.count,
                    original: piece,
                    start: 0,
                    end: piece.count
                )
            }
        }

        VStack(alignment: .leading, spacing: 12) {

            // Header
            HStack {
                Text("SYLLABLE")
                Text("ONSET")
                Text("VOWEL")
                Text("CODA")
                Text("LIVE")
                Text("IPA")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Rader
            ForEach(Array(syls.enumerated()), id: \.offset) { _, s in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Text(s.original).font(.title2).bold()
                            .frame(width: 80, alignment: .leading)

                        Text("DB syllable")
                            .foregroundStyle(.secondary)

                        Spacer()

                        if let ipa = s.ipa, !ipa.isEmpty {
                            Text(ipa).monospaced()
                                .frame(minWidth: 40, alignment: .leading)
                        }
                    }

                    HStack(spacing: 16) {
                        Text("DB")
                        Text("syllable data only")
                        Text("No fallback")
                    }
                    .foregroundStyle(.blue)
                }
                .padding(.vertical, 4)

                Divider()
            }
        }
        .padding()
    }
}

#Preview {
    // Rask sanity-check – skal vise "mâj" for ไม่ og riktig splitting for ภาษา / เสือ
    ThaiSyllableTableView(text: "ไม่ ภาษา เสือ")
        .padding()
}
