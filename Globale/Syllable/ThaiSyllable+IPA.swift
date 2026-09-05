//
//  ThaiSyllable+IPA.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/24/25.
//


import Foundation

// MARK: - Onset‑IPA (minimal)
let onsetIPA: [Character: String] = [
    "ด": "d","ต": "t","บ": "b","ป": "p","ก": "k","ค": "kʰ",
    "ช": "t͡ɕʰ","จ": "t͡ɕ","น": "n","ม": "m","ร": "r","ล": "l",
    "ย": "j","ว": "w","ส": "s","ห": "h",
]

// MARK: - Vokal‑IPA (minimal)
func nucleusIPA(_ nucleus: String) -> String {
    if nucleus.contains("ิ") { return "i" }
    if nucleus.contains("ี") { return "iː" }
    if nucleus.contains("ุ") { return "u" }
    if nucleus.contains("ู") { return "uː" }
    if nucleus.contains("า") { return "aː" }
    return "a"
}

extension ThaiSyllable {
    func ipa() -> String {
        let o = onset.first.flatMap { onsetIPA[$0] } ?? ""
        let v = nucleusIPA(nucleus)
        let c = (coda != nil) ? "k" : ""  // minimal
        return o + v + c
    }
    
    // 🔧 Compat: behold gamle navnet
    var written: String { writtenForm }

    /// Stavelsen slik den skrives i thai (preposed vokaler foran onset)
    var writtenForm: String {
        let pre  = String(nucleus.prefix { preposedVowels.contains($0) })
        let post = String(nucleus.drop  { preposedVowels.contains($0) })
        return pre + onset + post + (coda ?? "")
    }
}
