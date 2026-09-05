//
//  SyllableEnglishLookup.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/24/25.
//


import Foundation

@inlinable
func resolveEnglish(_ syllable: String) -> String {
    let rows = GlFunctions.shared.getWordCoreData(thaiWord: syllable)
    return rows.first?.englishWord ?? "—"
}
