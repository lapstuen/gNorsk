//
//  DictEntry.swift
//  gThai
//
//  Created by Geir Lapstuen on 9/6/25.
//


import Foundation
import NaturalLanguage

// MARK: - Ditt ordbok-lag (bytt ut med Core Data-spørringer)
struct DictEntry {
    let headword: String
    let meaning: String
    let freqScore: Int // valgfritt: frekvens for scoring
}

protocol DictionaryLookup {
    func entry(for word: String) -> DictEntry?
    func contains(_ word: String) -> Bool
}

// Eksempel-implementasjon med in-memory Set/Map.
// Bytt lett til Core Data: fetch request på headword == word.
final class InMemoryDict: DictionaryLookup {
    private let map: [String: DictEntry]
    init(_ entries: [DictEntry]) { self.map = Dictionary(uniqueKeysWithValues: entries.map { ($0.headword, $0) }) }
    func entry(for word: String) -> DictEntry? { map[word] }
    func contains(_ word: String) -> Bool { map[word] != nil }
}

// MARK: - Resultatmodell for UI
struct TokenAnalysis {
    let token: String
    let entry: DictEntry?                   // full-ordets betydning (hvis finnes)
    let parts: [DictEntry]                  // del-ord som gir mening (tom hvis ingen)
}

// MARK: - 1) Apple-orddeling (NLTokenizer)
func tokenizeThaiWords(_ text: String) -> [String] {
    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.setLanguage(.thai)
    tokenizer.string = text
    var result: [String] = []
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
        result.append(String(text[range]))
        return true
    }
    return result
}

// MARK: - 2) Subdeling av et ord i kjente del-ord
// Greedy + scoring (velger den delingen med høyest sum av freqScore, fallback til lengst mulig)
func decomposeIntoKnownSubwords(_ word: String, dict: DictionaryLookup,
                                minLen: Int = 1, maxParts: Int = 4) -> [DictEntry] {

    // Dynamic programming over Unicode-grenser
    let scalars = Array(word)
    let n = scalars.count
    struct State { let score: Int; let parts: [DictEntry] }
    var dp: [Int: State] = [0: State(score: 0, parts: [])]

    for i in 0..<n {
        guard let state = dp[i] else { continue }
        // Prøv alle endepunkter j > i
        var j = i + 1
        while j <= n {
            let piece = String(scalars[i..<j])
            if piece.count >= minLen, let e = dict.entry(for: piece) {
                // score: frekvens + liten bonus for lengre biter (hindrer for mye oppdeling)
                let score = state.score + e.freqScore + piece.count
                let newParts = state.parts + [e]
                // Begrens antall deler om ønskelig
                if newParts.count <= maxParts {
                    let better = (dp[j]?.score ?? Int.min) < score
                    if better { dp[j] = State(score: score, parts: newParts) }
                }
            }
            j += 1
        }
        // Tillat også “hoppe over” (ingen delord mellom i og i+1) -> ingen oppdatering
    }

    // Godta bare deling som dekker HELE ordet (dp[n])
    return dp[n]?.parts ?? []
}

// MARK: - 3) Full pipeline: segmentér → slå opp → prøv subdeler
func analyzeThaiText(_ text: String, dict: DictionaryLookup) -> [TokenAnalysis] {
    let tokens = tokenizeThaiWords(text).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    return tokens.map { tok in
        let entry = dict.entry(for: tok)
        let parts = decomposeIntoKnownSubwords(tok, dict: dict)
        return TokenAnalysis(token: tok, entry: entry, parts: parts)
    }
}