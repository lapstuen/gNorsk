/*
//  ThaiSyllable+Helpers.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/24/25.
//


import Foundation


// MARK: - Små helpers (internal så de kan brukes på tvers av filene)

@inline(__always)
func advance(_ i: inout Int, limit: Int) -> Bool {
    i += 1
    return i < limit
}

@inline(__always)
func peek(_ a: [Character], _ i: Int, _ k: Int) -> Character? {
    let j = i + k
    return (0..<a.count).contains(j) ? a[j] : nil
}

@inline(__always)
func isVowelStarter(_ c: Character?) -> Bool {
    guard let c = c else { return false }
    // preposed vowels, postposed vowels, tone marks, or 'อ' as vowel bearer
    return preposedVowels.contains(c) || vowels.contains(c) || toneMarks.contains(c) || c == "อ"
}

@inline(__always)
func isValidInitialCluster(_ c1: Character, _ c2: Character) -> Bool {
    initialClusterTable[c1]?.contains(c2) ?? false
}

@inline(__always) func ch(_ c: Character?) -> String { c.map(String.init) ?? "∅" }

@inline(__always)
func rem(_ chars: [Character], _ i: Int) -> String {
    (i < chars.count) ? String(chars[i...]) : "∅"
}

@inline(__always)
func wnd(_ chars: [Character], _ i: Int) -> (Character?, Character?, Character?) {
    (peek(chars, i, 1), peek(chars, i, 2), peek(chars, i, 3))
}

@inline(__always)
func charHasVowelOrTone(_ ch: Character?) -> Bool {
    guard let ch = ch else { return false }
    for s in ch.unicodeScalars {
        let c = Character(s)
        if preposedVowels.contains(c) || vowels.contains(c) || toneMarks.contains(c) || c == "อ" {
            return true
        }
    }
    return false
}

@inline(__always)
func hasVowelOrTone(_ ch: Character) -> Bool {
    for s in String(ch) {
        if vowels.contains(s) || toneMarks.contains(s) || preposedVowels.contains(s) { return true }
    }
    return false
}

@inline(__always)
func collectMarks(from ch: Character) -> String {
    var out = ""
    for us in String(ch).unicodeScalars {
        let c = Character(us)
        if vowels.contains(c) || toneMarks.contains(c) { out.append(c) }
    }
    return out
}

@inline(__always)
func baseConsonant(_ ch: Character?) -> Character? {
    guard let ch = ch else { return nil }
    for s in ch.unicodeScalars {
        let c = Character(s)
        if ("ก"..."ฮ").contains(c) { return c }
    }
    return nil
}

func isConsonant(_ c: Character) -> Bool {
    ("ก"..."ฮ").contains(c) && !vowels.contains(c) && !toneMarks.contains(c) && !preposedVowels.contains(c)
}

func isVowelOrTone(_ c: Character) -> Bool {
    vowels.contains(c) || toneMarks.contains(c) || preposedVowels.contains(c)
}

@inline(__always)
func leadingConsonant(in ch: Character) -> Character? {
    for us in String(ch).unicodeScalars {
        let c = Character(us)
        if isConsonant(c) { return c }
    }
    return nil
}

@inline(__always)
func containsVowelOrTone(_ ch: Character) -> Bool {
    for us in String(ch).unicodeScalars {
        let c = Character(us)
        if vowels.contains(c) || toneMarks.contains(c) || preposedVowels.contains(c) || c == "อ" {
            return true
        }
    }
    return false
}

@inline(__always)
func isBoundary(_ ch: Character?) -> Bool {
    guard let ch = ch else { return true }
    let isThaiLetter =
    ("ก"..."ฮ").contains(ch) || preposedVowels.contains(ch) ||
    vowels.contains(ch) || toneMarks.contains(ch) || ch == "อ"
    return !isThaiLetter
}

// MARK: - Kluster‑spising
@inline(__always)
func eatInitialCluster(in chars: [Character], i: inout Int, onset: inout String) -> String {
    var carried = ""

    if onset == "ห", i < chars.count, let baseChar = baseConsonant(chars[i]), hanamFollowers.contains(baseChar) {
        onset.append(chars[i])
        if !advance(&i, limit: chars.count) { return carried }
    }

    while i < chars.count {
        let g = chars[i]
        guard let base = baseConsonant(g), isConsonant(base) else { break }
        let c1 = onset.last!

        let ok = isValidInitialCluster(c1, base)
        if !ok { break }

        onset.append(base)

        for us in g.unicodeScalars {
            let sc = Character(us)
            if vowels.contains(sc) || toneMarks.contains(sc) || preposedVowels.contains(sc) || sc == "อ" {
                carried.append(sc)
            }
        }

        if !advance(&i, limit: chars.count) { break }
        if showPrint { print("🟢 eatCluster: added base='\(base)', carried='\(carried)' i=\(i)") }
    }

    return carried
}
*/
