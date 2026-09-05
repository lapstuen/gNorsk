//
//  ThaiLexicon.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/24/25.
//


import Foundation

enum ThaiLexicon {
    @inlinable
    static func resolveEnglish(_ syllable: String) -> String {
        let rows = GlFunctions.shared.getWordCoreData(thaiWord: syllable)
        return rows.first?.englishWord ?? "—"
    }
}