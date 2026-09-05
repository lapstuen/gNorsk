//
//  ThaiSyllable+Debug.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/24/25.
//


import Foundation

@inline(__always)
func dbgOK(_ raw: String, _ i: Int) -> Bool {
    guard DBG_ON else { return false }
    if let f = DBG_ONLY_WORD, !raw.contains(f) { return false }
    return i >= DBG_MIN_I
}

@inline(__always) func probeBegin(_ stage: String, i: Int, raw: String, chars: [Character]) {
    if dbgOK(raw, i) { print("🟢 probeBegin [\(stage)] i=\(i) rem='\(rem(chars, i))'") }
}

@inline(__always)
func probeStep(_ i0: Int, _ i1: Int, why: String, raw: String) {
    if dbgOK(raw, min(i0, i1)) { print("🟢 [STEP] i: \(i0) → \(i1)  why=\(why)") }
}

@inline(__always)
func probeLook(_ label: String, i: Int, cand: Character,
               raw: String, chars: [Character], reason: String = "") {
    let (n1, n2, n3) = wnd(chars, i)
    if dbgOK(raw, i) {
        print("🟢 [\(label)] i=\(i) cand=\(cand) n1=\(ch(n1)) n2=\(ch(n2)) n3=\(ch(n3)) rem='\(rem(chars, i))' \(reason)")
    }
}

@inline(__always)
func probeEmit(_ s: ThaiSyllable, i: Int, raw: String) {
    if dbgOK(raw, i) {
        print("🟢 [EMIT] \(s.onset) | \(s.nucleus) | \(s.coda ?? "ø")  live=\(s.live)")
    }
}

// MARK: - Live/Dead (simplifisert)
func isLiveSyllable(nucleus: String, coda: Character?) -> Bool {
    // 1) Live hvis sonorant koda
    if let c = coda {
        return ["ม","น","ง","ว","ย","ร","ล"].contains(c)
    }
    // 2) Ellers: live hvis lang vokal i nucleus (inkl. preposed vokaler/bærer อ)
    let longVowels: Set<Character> = ["า","ี","ื","ู","ำ","ๅ","เ","แ","โ","ใ","ไ","อ","อ"]
    for us in nucleus.unicodeScalars {
        let c = Character(us)
        if longVowels.contains(c) { return true }
    }
    return false
}