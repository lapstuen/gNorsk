//
//  SyllableLexicon.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/23/25.
//


protocol SyllableLexicon {
    func meaning(forSyllable s: String) -> String?
}

struct MemorySyllableLexicon: SyllableLexicon {
    /// Nøkkel = stavelsen slik den skrives (samme som `ThaiSyllable.written`)
    /// Verdi   = kort betydning/gloss
    let entries: [String:String]

    // Valgfritt: fallback uten tonemerker for enklere match
    private let toneMarks: Set<Character> = ["่","้","๊","๋"]

    func meaning(forSyllable s: String) -> String? {
        if let hit = entries[s] { return hit }
        let base = String(s.filter { !toneMarks.contains($0) })
        return entries[base]
    }
}