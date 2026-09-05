//
//  ThaiIPADebugPanel.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/10/25.
//
import SwiftUI




struct ThaiIPADebugPanel: View {
    var thai: String

    var body: some View {
        // Bygger rapporten med dagens funksjoner
        let s = thai.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping

        let initInfo = ThaiPhonetics.firstInitial(in: s) ?? (.mid, "ʔ")
        let tMark    = ThaiPhonetics.toneMark(in: s)
        let vowel    = ThaiPhonetics.vowelIPA(in: s, coda: s.unicodeScalars.last.map { Character($0) })?.ipa ?? "∅"
        let codaChar = s.unicodeScalars.last.map { Character($0) }
        let codaIPA  = codaChar.flatMap { ThaiPhonetics.codaMap[$0]?.ipa } ?? "∅"
        let live     = ThaiPhonetics.isLiveSyllable(coda: codaChar)
        let t        = ThaiPhonetics.tone(class: initInfo.0, toneMark: tMark, live: live)
        let outIPA   = ThaiPhonetics.ipa(for: s)

        let report = """
        Thai: \(s)
        initial=\(initInfo.1) class=\(String(describing: initInfo.0))
        vowel=\(vowel)  coda=\(codaIPA)
        toneMark=\(tMark) live=\(live) → \(t)
        IPA=\(outIPA)
        """

        ScrollView {
            Text(report)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ThaiIPADebugPanel(thai: "ดิกชันนารี่")
}
