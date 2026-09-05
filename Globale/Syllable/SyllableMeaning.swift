//
//  SyllableMeaning.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/24/25.
//


import Foundation

/// Minimal modell for per‑stavelse‑betydning (thai → engelsk)
struct SyllableMeaning: Identifiable, Equatable, Sendable {
    let id = UUID()
    let thai: String
    let english: String
}

extension SyllableMeaning {
    /// Bygg fra en segmentert stavelse
    init(syllable s: ThaiSyllable) {
        let t = s.writtenForm
        self.thai = t
        self.english = ThaiLexicon.resolveEnglish(t)   // bruker din GlFunctions‑lookup
    }
}

// Fallback if not already present elsewhere
extension ThaiSyllable {
    /// Thai spelling with preposed vowels before the onset.
    var writtenForm: String {
        let pre  = String(nucleus.prefix { preposedVowels.contains($0) })
        let post = String(nucleus.drop  { preposedVowels.contains($0) })
        return pre + onset + post + (coda ?? "")
    }
    /// Compat alias (many call sites still use `.written`)
    var written: String { writtenForm }
}


