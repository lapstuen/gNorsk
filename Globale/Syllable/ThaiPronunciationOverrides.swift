//
//  ThaiPronunciationOverrides.swift
//  gThai
//
//  Samling av ord som må ha eksplisitt uttaleoverstyring før de vanlige
//  segmenterings- og tone-reglene kan gi riktig resultat.
//

import Foundation

enum ThaiPronunciationOverrides {
    struct ToneOverride {
        let tone: ThaiTone
        let note: String
    }

    private static let pronunciationOverrides: [String: (onset: String, nucleus: String, coda: String?, live: Bool, toneMark: Character?)] = [
        "โทร": (onset: "ท", nucleus: "โอ", coda: nil, live: true, toneMark: nil),
        // Del av DB-ordet "ส่วน" som uttales med den lange diftongen /ua/ og ender i n.
        "ส่วน": (onset: "ส", nucleus: "ัว", coda: "น", live: true, toneMark: "่"),
        // "น้ำ" (vann) er et kjent unntak: สระอำ uttales normalt kort (ทำ→tʰam),
        // men nettopp dette ordet uttales med lang vokal: náːm.
        "น้ำ": (onset: "น", nucleus: "า", coda: "ม", live: true, toneMark: "้"),
        // "จริง" er et kjent unntak: ร etter จ er stum (uttales ikke som klynge
        // og danner heller ikke egen stavelse). Riktig uttale: tɕiŋ (jing).
        "จริง": (onset: "จ", nucleus: "ิ", coda: "ง", live: true, toneMark: nil)
    ]

    private static let toneOverrides: [String: [String: ToneOverride]] = [
        // Word-level exception: the syllable "นาด" inside "ขนาด" is treated as low tone.
        "ขนาด": [
            "นาด": ToneOverride(tone: .low, note: "Dictionary exception for the word 'ขนาด'")
        ],
        // Historisk unntak (khmer-opphav): den vanlige regelen (lav klasse + død +
        // lang vokal) skulle gitt fallende tone, men ตำรวจ uttales med lav tone:
        // tam.rùat (Wiktionary /tam˧.rua̯t̚˨˩/, Paiboon dtam-rùuat).
        "ตำรวจ": [
            "รวจ": ToneOverride(tone: .low, note: "Historical exception (Khmer origin): tam.rùat, not the falling tone the regular rule would predict")
        ],
        // Vanlig regel (lav klasse พ + skrevet ่-merke) skulle gitt fallende tone,
        // men "พรุ่ง" uttales med høy tone: pʰrúŋ.
        "พรุ่งนี้": [
            "พรุ่ง": ToneOverride(tone: .high, note: "Dictionary exception: pʰrúŋ, not the falling tone the regular rule would predict")
        ]
    ]

    static func syllables(for raw: String) -> [ThaiSyllable]? {
        let text = raw.precomposedStringWithCanonicalMapping
        guard let override = pronunciationOverrides[text] else { return nil }
        let length = text.count

        return [ThaiSyllable(
            onset: override.onset,
            nucleus: override.nucleus,
            coda: override.coda,
            live: override.live,
            ipa: nil,
            toneMark: override.toneMark,
            range: 0..<length,
            original: text,
            start: 0,
            end: length
        )]
    }

    static func toneOverride(word: String?, syllable: String) -> ToneOverride? {
        guard let word else { return nil }
        let normalizedWord = word.precomposedStringWithCanonicalMapping
        let normalizedSyllable = syllable.precomposedStringWithCanonicalMapping
        return toneOverrides[normalizedWord]?[normalizedSyllable]
    }
}
