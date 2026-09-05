//
//  func.swift
//  gThai
//
//  Created by Geir Lapstuen on 9/4/25.
//


//
//  ThaiToneLogic.swift
//  gThai
//

import Foundation

// Første ekte konsonant i et ord – brukes for toneklasse
public func firstConsonant(in word: String) -> Character? {
    let consonantSet = Set("กขฃคฅฆงจฉชซฌญฎฏฐฑฒณดตถทธนบปผฝพฟภมยรฤลฦวศษสหฬอฮ")
    for ch in word {
        for us in ch.unicodeScalars {
            let base = Character(us)
            if consonantSet.contains(base) { return base }
        }
    }
    return nil
}

// Toneklasse fra første konsonant
public func consonantClassString(for c: Character?) -> String {
    guard let c else { return "MID" }
    let midSet  = Set("กจฎฏดตบปอ")
    let highSet = Set("ขฃฉฐถผฝศษสห")
    return midSet.contains(c) ? "MID" : (highSet.contains(c) ? "HIGH" : "LOW")
}

// MARK: - Stumme konsonantklynger (garan/thanthakhat over hele klyngen)
// Noen ord (ofte lånt fra sanskrit/pali) har en hel konsonantklynge + ์ som er
// fullstendig stum, f.eks. "จันทร์" = จัน + ทร์ (hele "ทร์" uttales ikke).
// Denne lista er ment å bygges ut etter hvert som flere ord oppdages i gullfila.
public let silentClusterEndings: Set<String> = [
    "ทร์", "ตร์", "ทน์", "ษณ์", "ฑร์", "ษย์", "ณฑ์"
]

/// Sjekker om en HEL lagret stavelse (f.eks. "ทร์" eller "ร์") er stum.
///
/// To tilfeller:
/// 1) Kjent flerkonsonant-gruppe fra lista over (f.eks. "ทร์").
/// 2) Generelt: stavelsen består KUN av konsonant(er) + ์ og har ingen vokal
///    i det hele tatt. En thai-stavelse trenger alltid en vokal for å kunne
///    uttales, så en slik "stavelse" (f.eks. "ร์" alene, som DB noen ganger
///    lagrer separat fra stavelsen foran) er per definisjon 100% stum.
public func isSilentClusterSyllable(_ original: String) -> Bool {
    let normalized = original.precomposedStringWithCanonicalMapping
    if silentClusterEndings.contains(normalized) { return true }

    // NB: itererer på unicodeScalars, ikke Character — en konsonant + ์ er
    // ÉN sammensatt grafemklynge (Character) i Swift, så et Character-basert
    // allSatisfy ville aldri matche verken konsonant- eller ์-sjekken.
    let scalars = normalized.unicodeScalars
    let thanthakhat: UnicodeScalar = "\u{0E4C}"
    guard scalars.contains(thanthakhat) else { return false }
    let consonantRange: ClosedRange<UInt32> = 0x0E01...0x0E2E // ก...ฮ
    return scalars.allSatisfy { $0 == thanthakhat || consonantRange.contains($0.value) }
}

// MARK: - อักษรนำ (leder-konsonant / redusert stavelse)
// Lav-klasse sonorant-konsonanter som kan "arve" toneklasse fra en
// foranstående redusert leder-stavelse (samme mekanisme som "ห นำ", f.eks.
// หมา — bare med annen leder-klasse enn ห).
public let lowClassSonorants = Set("มนงวยรลฬ")

/// En "redusert leder-konsonant"-stavelse er nøyaktig én bar konsonant, uten
/// egen vokal eller coda (f.eks. "ต" i "ตลาด"). Den uttales kort og nøytralt
/// (ingen egen tone), og "låner ut" sin konsonantklasse til neste stavelse
/// hvis den starter med en lav-klasse sonorant uten vokal mellom dem.
public func isReducedLeadingConsonantSyllable(_ original: String) -> Bool {
    let normalized = original.precomposedStringWithCanonicalMapping
    guard normalized.unicodeScalars.count == 1, let scalar = normalized.unicodeScalars.first else {
        return false
    }
    let consonantRange: ClosedRange<UInt32> = 0x0E01...0x0E2E // ก...ฮ
    return consonantRange.contains(scalar.value)
}

/// Henter den fonetisk gjeldende coda-konsonanten fra `ThaiSyllable.coda`.
///
/// Swift slår sammen en konsonant + garan/thanthakhat (์) til ÉN "Character"
/// (f.eks. "ร" + "์" → grafemklyngen "ร์"). En slik sammensatt Character er
/// IKKE lik den rene konsonanten i oppslagstabeller som `sonorants`/`ipaCodaMap`,
/// så et enkelt `.first` gir feil resultat (koda blir tolket som stopp-konsonant
/// og teksten "ร์" printes bokstavelig i IPA-en). En coda med ์ er i realiteten
/// helt stum, altså ingen reell coda.
public func effectiveCodaChar(_ coda: String?) -> Character? {
    guard let coda, !coda.isEmpty else { return nil }
    if coda.unicodeScalars.contains(where: { Character($0) == "์" }) {
        return nil
    }
    return coda.first
}



// Live/dead kun fra IPA-oppfatning (robust mot gamle regler)
public func isLiveByIPA(nucleus: String, coda: Character?) -> Bool {
    let sonorants = Set("มนงวยรลฬณญ")

    // Hvis det er en coda:
    if let c = coda {
        // Sonorant coda → LIVE
        if sonorants.contains(c) { return true }
        // Stopp-coda (alt annet) → DEAD
        return false
    }

    // Ingen coda - sjekk vokal/implicit onset
    // Spesialtilfelle: สระ อำ (sara am) har implisitt ม-coda → alltid LIVE
    // ำ = U+0E33, eller dekomponert som ◌ํ + า (U+0E4D + U+0E32)
    if nucleus.contains("ำ") || nucleus.contains("\u{0E4D}") {
        return true
    }
    
    // สระ ะ (kort vokal, uten koda) er alltid død — selv om "า" forekommer
    // som en DEL av stavemåten (f.eks. "เาะ" i เกาะ, som er kort ɔ, ikke lang า).
    // Denne sjekken må komme FØR "า"-sjekken under.
    if nucleus.contains("ะ") {
        return false
    }

    // åpen stavelse med า er live
    if nucleus.contains("า") {
        return true
    }

    // Ingen coda - sjekk vokallengde
    let ipa = ThaiIPA.ipaForVowel(nucleus: nucleus, coda: nil)
    if ipa.contains("ː") { return true }

    let longDiphthongs: Set<String> = ["aj","aw","ia","ɯa","ua","ej","oj","ɛj","ɔj","ɤj"]
    if longDiphthongs.contains(ipa) { return true }

    return false
}

// Bygg IPA for én ThaiSyllable (returnerer String)
public func ipaForSyllable(_ s: ThaiSyllable) -> String {
    // If syllable already has a real IPA value (from database lookup), use it directly.
    // Ignore placeholder values produced by segmentation.
    if let precomputedIPA = s.ipa, !precomputedIPA.isEmpty, precomputedIPA != "xxx" {
        return precomputedIPA
    }

    // Otherwise, generate IPA from syllable components
    // 1) live/dead
    let live = isLiveByIPA(nucleus: s.nucleus, coda: effectiveCodaChar(s.coda))

    // 2) toneklasse
    let cls = consonantClassString(for: firstConsonant(in: s.original))

    // 3) tone fra din eksisterende funksjon (norsk tekst) → ThaiTone
    let toneMarkStr = s.toneMark.map(String.init) ?? ""
    let vlenIPA = ThaiIPA.ipaForVowel(nucleus: s.nucleus, coda: effectiveCodaChar(s.coda))
    let isLong = vlenIPA.contains("ː") || ["aj","aw","ia","ɯa","ua","ej","oj","ɛj","ɔj","ɤj"].contains(vlenIPA)

    let toneStr = finnThaiTone(
        consonantClass: cls,
        liveSyllable: live,
        ToneMark: toneMarkStr,
        lognVowel: isLong
    )
    let tone = toneEnum(from: toneStr)

    // 4) IPA med tone – ʔ kun hvis dead
    return ThaiIPA.ipaSyllableWithTone(
        onset: s.onset,
        nucleus: s.nucleus,
        coda: effectiveCodaChar(s.coda),
        tone: tone,
        addGlottalIfOpenDead: !live
    )
}
