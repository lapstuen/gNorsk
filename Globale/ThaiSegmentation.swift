//
//  ThaiSegmentationDemo 2.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/19/25.
//


import Foundation
import NaturalLanguage
import CoreData
import SwiftUI

// MARK: - Thai ortografi-ressurser (internal, ikke private)

let thaiLeadingVowels: Set<Character> = ["เ","แ","โ","ใ","ไ"]
let thaiToneMarks: Set<Character> = ["่","้","๊","๋"]
let thaiVowelMarks: Set<Character> = ["ะ","า","ิ","ี","ึ","ื","ุ","ู","ั","ำ","ๅ","ฺ"]
let thaiConsonants: Set<Character> = Set("กขฃคฆงจฉชซฌญฎฏฐฑฒณดตถทธนบปผพภฟมยรลวศษสหฬฮอ")
let thaiCodaLetters: Set<Character> = ["ก","ข","ค","ฆ","ด","ต","ฐ","ฑ","ฒ","ธ","บ","ป","ง","น","ณ","ม","ย","ว","ร","ล","ฬ"]
let allowedOnsetClusters: Set<String> = [
    "กร","กล","กว","ขร","ขล","ขว","คร","คล","คว",
    "ปร","ปล","พร","พล","ฟร","ฟล","ตร","ศร","สร","สล","สว",
    "หง","หญ","หน","หม","หย","หร","หล","หว"
]

// MARK: - 1) Apple NLTokenizer: ord-slices

func thaiWordSlices(in text: String) -> [Substring] {
    let tok = NLTokenizer(unit: .word)
    tok.string = text
    tok.setLanguage(.thai)
    var out: [Substring] = []
    tok.enumerateTokens(in: text.startIndex..<text.endIndex) { r, _ in
        out.append(text[r])
        return true
    }
    return out
}

// MARK: - 2) Heuristikk: plausibel thai-delstreng

func isPlausibleThaiChunk(_ s: Substring) -> Bool {
    guard !s.isEmpty else { return false }
    guard s.contains(where: { thaiConsonants.contains($0) }) else { return false }

    let cs = Array(s)

    // Start: ledende vokal eller konsonant
    guard thaiLeadingVowels.contains(cs[0]) || thaiConsonants.contains(cs[0]) else { return false }

    // Onset-klynge (to første konsonanter) — kun relevant når andre bokstav faktisk
    // er en ekte klynge-partner (ร/ล/ว), siden det er de eneste som brukes i
    // allowedOnsetClusters. "อ" regnes teknisk som konsonant i thaiConsonants (den
    // fungerer ofte som stum vokalbærer), men er ALDRI en ekte klynge-partner — uten
    // denne begrensningen ble gyldige ord som "ของ" (kʰɔ̌ɔŋ) feilaktig forkastet fordi
    // "ขอ" ikke står i allowedOnsetClusters.
    let onsetClusterPartners: Set<Character> = ["ร", "ล", "ว"]
    if cs.count >= 2, thaiConsonants.contains(cs[0]), onsetClusterPartners.contains(cs[1]) {
        let cl = String(cs[0...1])
        if !allowedOnsetClusters.contains(cl) { return false }
    }

    // Tone: maks 1, og ikke først
    let toneCount = cs.filter { thaiToneMarks.contains($0) }.count
    if toneCount > 1 { return false }
    if toneCount == 1, thaiToneMarks.contains(cs[0]) { return false }

    // Slutt: gyldig coda eller åpen (vokalmark til slutt ok)
    if let last = cs.last {
        let ok = thaiCodaLetters.contains(last) || thaiVowelMarks.contains(last)
        if !ok { return false }
    }
    return true
}

// MARK: - 3) Kandidater fra ord-slices (uten DB)

func thaiCandidates(in text: String) -> [String] {
    var result: Set<String> = []
    for word in thaiWordSlices(in: text) {
        let arr = Array(word)
        for i in arr.indices {
            for j in i..<arr.count {
                let sub = arr[i...j]
                if sub.count == 1, !thaiConsonants.contains(sub.first!) { continue }
                if isPlausibleThaiChunk(Substring(String(sub))) {
                    result.insert(String(sub))
                }
            }
        }
    }
    return result.sorted { $0.count > $1.count } // lengst først
}

// MARK: - 4) DB-oppslag (Core Data) for kandidater

func existingThaiWords(for candidates: [String],
                       context: NSManagedObjectContext) -> Set<String> {
    guard !candidates.isEmpty else { return [] }
    let chunkSize = 300
    var found: Set<String> = []
    var i = 0
    while i < candidates.count {
        let chunk = Array(candidates[i..<min(i+chunkSize, candidates.count)])
        let req = NSFetchRequest<NSDictionary>(entityName: "ThaiWords")
        req.resultType = .dictionaryResultType
        req.propertiesToFetch = ["thaiWord"]
        req.returnsDistinctResults = true
        req.predicate = NSPredicate(format: "thaiWord IN %@", chunk)
        if let rows = try? context.fetch(req) {
            for dict in rows {
                if let w = dict["thaiWord"] as? String { found.insert(w) }
            }
        }
        i += chunkSize
    }
    return found
}

// MARK: - Mini-demo uten DB (for å verifisere at symbolene resolver)

struct ThaiSegmentationDemo: View {
    let text: String
    var body: some View {
        let items = thaiCandidates(in: text)
        List(items, id: \.self) { Text($0) }
            .navigationTitle("Kandidater: \(items.count)")
    }
}

#Preview("ThaiSegmentationDemo") {
    NavigationStack {
        ThaiSegmentationDemo(text: "เมื่อคืนคุณนอนหลับสบายไหม")
    }
}