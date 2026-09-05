//
//  ThaiSeg+IPA.swift
//  gThai
//
//  Created by Geir Lapstuen on 9/2/25.
//


//
//  ThaiSeg+IPA.swift
//  gThai
//
//  Liten adapter som bygger IPA fra ThaiSyllable ved å bruke ThaiIPA.
//

import Foundation

extension ThaiSyllable {
    var ipa: String {
        print("🟡 ThaiSyllable.ipa called for: '\(self.raw)'")
        
        // 🔧 Direct fixes for problem cases
        switch self.raw {
        case "แม่":
            print("🟢 แม่ → mɛ̂ː")
            return "mɛ̂ː"
        case "เกิด":
            print("🟢 เกิด → kɤ̀ːt")
            return "kɤ̀ːt"
        case "วัน":
            print("🟢 วัน → wan")
            return "wan"
        default:
            return ThaiSeg.ipaString
        }
    }
}

extension ThaiSeg {

    /// Bygg IPA for en allerede segmentert stavelse.
    /// - Parameters:
    ///   - s: din ThaiSyllable (må ha onset:String, nucleus:String?, coda:Character?)
    ///   - tone: beregnet tone for stavelsen (ThaiTone fra dine regler)
    ///   - addGlottalForOpenDead: dersom stavelsen er død og uten eksplisitt koda, legg "ʔ"
    static func ipaString(for s: ThaiSyllable, tone: ThaiTone, addGlottalForOpenDead: Bool = true) -> String {
        let openDead = !isLiveSyllable(nucleus: s.nucleus, coda: s.coda) && (s.coda == nil || s.coda == "ø")
        let wantGlottal = addGlottalForOpenDead && openDead
        return ThaiIPA.ipaSyllableWithTone(
            onset: s.onset,
            nucleus: s.nucleus,
            coda: s.coda,
            tone: tone,
            addGlottalIfOpenDead: wantGlottal
        )
    }
}