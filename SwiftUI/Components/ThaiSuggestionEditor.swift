//
//  ThaiSuggestionEditor.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/27/25.
//


import SwiftUI

/// Drop-in teksteditor med live forslag basert på markering/innsettingspunkt.
/// Brukes i DetailView: ThaiSuggestionEditor(text: $sentence)
struct ThaiSuggestionEditor: View {
    @Binding var text: String
    @Binding var minH: CGFloat
    @Binding var maxH: CGFloat
    let onSelectWord: (String) -> Void
    var onSuggestionChanged: ((String?) -> Void)? = nil
    @Environment(\.openURL) private var openURL



    @State private var selection: TextSelection? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $text, selection: $selection)
                .font(.system(size: 28))
                .frame(minHeight: minH, maxHeight: maxH)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                .textInputAutocapitalization(.never)
                .onChange(of: selection) { _, newSel in
                    let word = getSuggestions(text: text, selection: newSel).first.map(String.init)
                    onSuggestionChanged?(word?.precomposedStringWithCompatibilityMapping)
                }

            SuggestionsView(
                suggestions: getSuggestions(text: text, selection: selection).map(String.init),
                onSelectWord: onSelectWord
            )
        }
    }

    // MARK: - Suggestions

    private func getSuggestions(text: String, selection: TextSelection?) -> [Substring] {
        // Fjern isFocused-kravet for å alltid vise forslag når det er valgt tekst
        guard let selection else { return [] }

        switch selection.indices {
        case .selection(let r):
            if selection.isInsertion {
                return [] // ved innsettingspunkt foreslår vi ikke noe (kan utvides)
            } else {
                guard let rr = safeRange(r, in: text) else { return [] }
                return [text[rr]]
            }
        case .multiSelection(let set):
            return set.ranges.compactMap { safeRange($0, in: text) }.map { text[$0] }
        @unknown default:
            return []
        }
    }

    // MARK: - Safe indexing helpers

    private func safeRange(_ r: Range<String.Index>, in s: String) -> Range<String.Index>? {
        guard
            let lo = r.lowerBound.samePosition(in: s),
            let hi = r.upperBound.samePosition(in: s),
            lo <= hi
        else { return nil }
        return lo..<hi
    }
}

// Samme SuggestionsView som du allerede har:
struct SuggestionsView: View {
    @Environment(\.openURL) private var openURL
    let suggestions: [String]
    let onSelectWord: (String) -> Void

    @State private var englishTranslation: String = ""
    @State private var lastFetchedWord: String = ""

    var body: some View {
        if suggestions.isEmpty {
            Text("select text")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    HStack {
                        // Skjuler tekstfeltene for forslagene - viser bare knapp
                        // ForEach(Array(Set(suggestions)), id: \.self) { s in
                        //     Text(s)
                        //         .padding(.horizontal, 10)
                        //         .padding(.vertical, 6)
                        //         .background(Capsule().fill(Color(.secondarySystemBackground)))
                        //         .overlay(Capsule().stroke(.quaternary))
                        // }

                        let valgt = suggestions.first ?? ""

                        HStack {

                        }
                        Button(valgt) {
                            onSelectWord(valgt)
                        }
                        Text("-> \(englishTranslation)")
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: suggestions) { oldValue, newValue in
                if let valgt = newValue.first, !valgt.isEmpty {
                    lastFetchedWord = valgt
                    let thai = GlFunctions.shared.getWordCoreData(thaiWord: valgt)
                    englishTranslation = thai.first?.englishWord ?? "—"
                } else {
                    englishTranslation = ""
                    lastFetchedWord = ""
                }
            }
            .onAppear {
                // Initial fetch når viewet vises første gang
                if let valgt = suggestions.first, !valgt.isEmpty {
                    lastFetchedWord = valgt
                    let thai = GlFunctions.shared.getWordCoreData(thaiWord: valgt)
                    englishTranslation = thai.first?.englishWord ?? "—"
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var demo = "ลองเลือกข้อความ หรือวางเคอร์เซอร์ไว้ในคำภาษาไทยก็ได้"
    @Previewable @State var minH: CGFloat = 50
    @Previewable @State var maxH: CGFloat = 80
    ThaiSuggestionEditor(
        text: $demo,
        minH: $minH,
        maxH: $maxH,
        onSelectWord: { word in
            print("Selected word: \(word)")
        }
    )
    .padding()
}

