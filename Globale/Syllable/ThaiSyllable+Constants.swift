import Foundation

// === DINE GLOBALER (samme navn/tilgang som før) ===
public let showPrint = false
public let showPrintOverValue = 0

public var DBG_ON = false                // skru all debug av/på
public var DBG_ONLY_WORD: String? = nil  // Debug alle ord
public var DBG_MIN_I = 0                 // logg bare når i >= denne

// === Sett / tabeller ===
let vowels: Set<Character> = ["ะ","า","ิ","ี","ึ","ื","ุ","ู","ั","ำ","ๅ","็"]
let toneMarks: Set<Character> = ["่","้","๊","๋"]
let preposedVowels: Set<Character> = ["เ","แ","โ","ใ","ไ"]

let hanamFollowers: Set<Character> = ["ง","ญ","ณ","น","ม","ย","ร","ล","ว"]

// NB: holdt i sync med ipaCodaMap (ThaiIPA.swift) — enhver konsonant som har en
// coda-IPA-mapping der må også kunne GJENKJENNES som en gyldig coda her, ellers
// blir den feilaktig stående igjen som starten på en ny stavelse (f.eks. "ธ" i
// "พุธ" ble tidligere sin egen stavelse i stedet for coda på "พุ").
let allowedCoda: Set<Character> = [
    "ก","ข","ค","ฆ",
    "ด","ต","ถ","ท","ธ","ฎ","ฏ","ฐ","ฑ","ฒ",
    "จ","ฉ","ช","ฌ","ซ","ศ","ษ","ส",
    "บ","ป","พ","ฟ","ภ",
    "ง","น","ณ","ญ","ม","ย","ว","ร","ล","ฬ"
]

let silencer: Character = "์"
let maiHanakat: Character = "ั"

let initialClusterTable: [Character: Set<Character>] = [
    "ก": ["ร","ล","ว"],
    "ข": ["ร","ล"],
    "ค": ["ร","ล","ว"],   // คร, คล, คว
    "ต": ["ร"],
    "ท": ["ร"],           // ทร → uttales s (ทรง, ทราบ, ทราย)
    "ป": ["ร","ล"],
    "พ": ["ร","ล"],
    "ฟ": ["ร"],
    "ผ": ["ร"],
    "ศ": ["ร"],
    "ษ": ["ร"],
    "ส": ["ร"],
]
