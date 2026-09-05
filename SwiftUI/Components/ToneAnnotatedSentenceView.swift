//
//  ToneAnnotatedSentenceView.swift
//  gThai
//
//  Created by Claude on 12/3/25.
//
import CoreData
import SwiftUI

internal func analyzeThaiSyllableText(_ syllableText: String, source: String) -> ThaiSyllable? {
    let analyzed = ThaiSeg.segmentWordIntoSyllables(syllableText)

    if analyzed.isEmpty {
        Logger.warning("[ToneDBG] \(source): ingen stavelse analysert for '\(syllableText)'")
        return nil
    }

    if analyzed.count == 1 {
        let syllable = analyzed[0]
        Logger.debug("[ToneDBG] \(source): '\(syllableText)' -> onset=\(syllable.onset) nucleus=\(syllable.nucleus) coda=\(syllable.coda ?? "nil") live=\(syllable.live) ipa=\(syllable.ipa ?? "nil")")
        return syllable
    }

    Logger.warning("[ToneDBG] \(source): '\(syllableText)' ga \(analyzed.count) interne deler, men behandles som én stavelse")
    return mergeThaiSyllables(analyzed, originalText: syllableText)
}

internal func mergeThaiSyllables(_ syllables: [ThaiSyllable], originalText: String) -> ThaiSyllable {
    let last = syllables[syllables.count - 1]
    let first = syllables[0]

    return ThaiSyllable(
        onset: last.onset,
        nucleus: last.nucleus,
        coda: last.coda,
        live: last.live,
        ipa: last.ipa,
        toneMark: last.toneMark,
        range: first.range.lowerBound..<last.range.upperBound,
        original: originalText,
        start: first.start,
        end: last.end
    )
}

internal func parseBracketedSyllables(_ text: String) -> [ThaiSyllable] {
    if text.hasPrefix("[\"") && text.hasSuffix("\"]") {
        return parseArrayFormat(text)
    }

    let pattern = "\\[([^\\]]+)\\]"
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return []
    }

    let nsText = text as NSString
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
    var syllables: [ThaiSyllable] = []

    for match in matches where match.numberOfRanges >= 2 {
        let syllableText = nsText.substring(with: match.range(at: 1))
        if let parsed = analyzeThaiSyllableText(syllableText, source: "Bracketed") {
            syllables.append(parsed)
        }
    }

    return syllables
}

internal func parseArrayFormat(_ text: String) -> [ThaiSyllable] {
    var cleaned = text
    if cleaned.hasPrefix("[") { cleaned.removeFirst() }
    if cleaned.hasSuffix("]") { cleaned.removeLast() }

    let parts = cleaned.components(separatedBy: ",")
    var syllables: [ThaiSyllable] = []

    for part in parts {
        let syllableText = part.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        if syllableText.isEmpty { continue }

        if let parsed = analyzeThaiSyllableText(syllableText, source: "ArrayFormat") {
            syllables.append(parsed)
        }
    }

    return syllables
}

internal func analyzeToneSentence(_ text: String, word: ThaiWords? = nil, treatTextAsSingleSyllable: Bool = false) -> [SyllableToneInfo] {
    if treatTextAsSingleSyllable {
        guard let syllable = analyzeThaiSyllableText(text, source: "Explicit") else {
            return []
        }
        return buildToneInfos(from: [syllable], source: "Explicit", word: word)
    }

    if let dbSyllables = word?.syllables, !dbSyllables.isEmpty {
        let wordLabel = word?.thaiWord ?? text
        Logger.success("[ToneDBG] Bruker DB-syllabler for '\(wordLabel)': \(dbSyllables.joined(separator: " | "))")
        let syllables = dbSyllables.compactMap { analyzeThaiSyllableText($0, source: "DB") }
        return buildToneInfos(from: syllables, source: "DB", word: word)
    }

    if text.contains("[") && text.contains("]") {
        Logger.debug("[ToneDBG] Bruker eksplisitt stavelsesformat fra tekst for '\(word?.thaiWord ?? text)'")
        let syllables = parseBracketedSyllables(text)
        if !syllables.isEmpty {
            return buildToneInfos(from: syllables, source: "Text", word: word)
        }
    }

    if word != nil {
        Logger.warning("[ToneDBG] Ord finnes men mangler DB-syllabler for '\(word?.thaiWord ?? text)'. Bruker tekst-fallback.")
    } else {
        Logger.debug("[ToneDBG] Ingen `word` satt. Bruker ThaiSeg.segmentThai for '\(text)'")
    }

    let syllables = ThaiSeg.segmentThai(text)
    return buildToneInfos(from: syllables, source: "Fallback", word: word)
}

internal func toneIPA(for info: SyllableToneInfo) -> String {
    guard !info.isSilent else { return "" }

    let syllable = info.syllable
    let onset = syllable.onset
    let nucleus = syllable.nucleus
    let coda = effectiveCodaChar(syllable.coda)

    return ThaiIPA.ipaSyllableWithTone(
        onset: onset,
        nucleus: nucleus,
        coda: coda,
        tone: info.tone,
        addGlottalIfOpenDead: !info.isLive && coda == nil && !info.isReducedLeader
    )
}

internal func buildToneInfos(from syllables: [ThaiSyllable], source: String, word: ThaiWords? = nil) -> [SyllableToneInfo] {
    syllables.enumerated().map { index, syllable in
        if isSilentClusterSyllable(syllable.original) {
            Logger.debug("[ToneDBG] \(source)[\(index)]: '\(syllable.original)' er en kjent stum klynge")
            return SyllableToneInfo(
                syllable: syllable,
                consonantClass: "",
                isLive: false,
                isLongVowel: false,
                hasToneMark: false,
                toneMarkChar: "",
                tone: .mid,
                toneMark: "",
                isSilent: true
            )
        }

        // อักษรนำ (1): en redusert leder-stavelse (f.eks. "ต" i "ตลาด", "ท" i
        // "ทหาร", eller "ประ" i "ประเทศ" — enten bar konsonant uten vokal, eller
        // konsonant(klynge) + eksplisitt kort ะ, alltid uten koda) følger den
        // vanlige tonereglen som en helt normal død, kort stavelse (klasse-basert
        // regel), men uttales uten hørbart glottalstopp — uansett hva slags
        // konsonant neste stavelse starter med. Se `isReducedLeader`, som brukes
        // til å undertrykke glottalstoppet i `toneIPA`.
        let isReducedLeader = index + 1 < syllables.count
            && syllable.coda == nil
            && (syllable.nucleus == "ะ" || isReducedLeadingConsonantSyllable(syllable.original))

        // อักษรนำ (2): forrige stavelse var en redusert leder-konsonant, og DENNE
        // stavelsen starter med en lav-klasse sonorant → arv leder-klassen i
        // toneberegningen i stedet for stavelsens egen (lave) klasse.
        let inheritedClass: String? = {
            guard index > 0, isReducedLeadingConsonantSyllable(syllables[index - 1].original) else { return nil }
            guard let firstHere = firstConsonant(in: syllable.original), lowClassSonorants.contains(firstHere) else { return nil }
            return consonantClassString(for: firstConsonant(in: syllables[index - 1].original))
        }()

        let firstCons = firstConsonant(in: syllable.original)
        let consClass = inheritedClass ?? consonantClassString(for: firstCons)
        let codaChar = effectiveCodaChar(syllable.coda)
        let isLive = isLiveByIPA(nucleus: syllable.nucleus, coda: codaChar)
        let toneMarkStr = syllable.toneMark.map(String.init) ?? ""
        let vlenIPA = ThaiIPA.ipaForVowel(nucleus: syllable.nucleus, coda: codaChar)
        let toneOverride = ThaiPronunciationOverrides.toneOverride(
            word: word?.thaiWord,
            syllable: syllable.original
        )
        let isLongVowel = vlenIPA.contains("ː") ||
            ["aj","aw","ia","ɯa","ua","ej","oj","ɛj","ɔj","ɤj"].contains(vlenIPA)

        if codaChar == nil, let last = syllable.original.last {
            let thaiConsonants = Set("กขฃคฅฆงจฉชซฌญฎฏฐฑฒณดตถทธนบปผฝพฟภมยรฤลฦวศษสหฬอฮ")
            if thaiConsonants.contains(last) {
                Logger.warning("[ToneDBG] \(source)[\(index)]: '\(syllable.original)' slutter på konsonant men har ingen coda. onset=\(syllable.onset) nucleus=\(syllable.nucleus) ipa=\(syllable.ipa ?? "nil")")
            }
        }

        Logger.debug("[ToneDBG] \(source)[\(index)]: '\(syllable.original)' onset=\(syllable.onset) nucleus=\(syllable.nucleus) coda=\(codaChar.map(String.init) ?? "nil") live=\(isLive) long=\(isLongVowel) vlenIPA=\(vlenIPA)")

        let toneStr = finnThaiTone(
            consonantClass: consClass,
            liveSyllable: isLive,
            ToneMark: toneMarkStr,
            lognVowel: isLongVowel
        )

        let tone = toneOverride?.tone ?? toneEnum(from: toneStr)
        let toneMark = ThaiPhonetics.toneDiacritic(tone)

        return SyllableToneInfo(
            syllable: syllable,
            consonantClass: consClass,
            isLive: isLive,
            isLongVowel: isLongVowel,
            hasToneMark: !toneMarkStr.isEmpty,
            toneMarkChar: toneMarkStr,
            tone: tone,
            toneMark: toneMark,
            isOverride: toneOverride != nil,
            overrideNote: toneOverride?.note,
            isReducedLeader: isReducedLeader
        )
    }
}

/// Skrivebeskyttet, samlet IPA for hele ordet — bygget ved å slå sammen hver
/// stavelses egen beregnede IPA (samme kilde som pillene i ToneAnnotatedSentenceView).
/// Stumme stavelser (f.eks. "ร์") bidrar ikke til resultatet.
struct CombinedWordIPAView: View {
    let sentence: String
    var word: ThaiWords? = nil
    var fontSize: CGFloat = 24

    var body: some View {
        let combined = analyzeToneSentence(sentence, word: word)
            .map { toneIPA(for: $0) }
            .filter { !$0.isEmpty }
            .joined(separator: ".")

        if !combined.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("IPA (whole word)")
                    .font(.caption.bold())
                Text(combined)
                    .font(.system(size: fontSize))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.top, 4)
        }
    }
}

/// Viser thai-tekst med stavelsesanalyse:
/// - Hakeparenteser rundt hver stavelse med fargekodede konsonanter
/// - Tonesymbol etter hver stavelse (⌃ ⌄ ↘ ↗ ─)
/// - Info-knapp (i) som forklarer toneberegningen
struct ToneAnnotatedSentenceView: View {
    let text: String
    var fontSize: CGFloat = 26
    var showInfoButtons: Bool = true
    var word: ThaiWords? = nil  // Optional word for navigation to detail view
    var treatTextAsSingleSyllable: Bool = false

    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        let syllableInfos = analyzeToneSentence(text, word: word, treatTextAsSingleSyllable: treatTextAsSingleSyllable)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(syllableInfos.enumerated()), id: \.element.id) { _, info in
                    SyllableRow(
                        info: info,
                        fontSize: fontSize,
                        showInfoButtons: showInfoButtons,
                        word: word,
                        appState: appState,
                        context: context,
                        syllableView: { AnyView(self.syllableView($0)) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .onAppear {
            Logger.debug("[ToneDBG] render ToneAnnotatedSentenceView text='\(text)' word='\(word?.thaiWord ?? "nil")' syllables=\(syllableInfos.count)")
        }
    }

    @ViewBuilder
    private func syllableView(_ info: SyllableToneInfo) -> some View {
        HStack(alignment: .center, spacing: 1) {
            // Live/Dead indikator (grønn=live, rød=dead, grå=stum)
            Circle()
                .fill(info.isSilent ? Color.gray : (info.isLive ? Color.green : Color.red))
                .frame(width: fontSize * 0.28, height: fontSize * 0.28)

            // Åpne hakeparentes
            Text("[")
                .font(.system(size: fontSize))
                .foregroundColor(.secondary)

            // Stavelse med fargekodede konsonanter (dempet hvis stum)
            coloredSyllableText(info.syllable.original)
                .strikethrough(info.isSilent, color: .secondary)
                .opacity(info.isSilent ? 0.4 : 1.0)

            // Lukke hakeparentes
            Text("]")
                .font(.system(size: fontSize))
                .foregroundColor(.secondary)

            // Tonesymbol (ingen tone for stumme stavelser)
            Text(info.isSilent ? "–" : toneSymbol(info.tone))
                .font(.system(size: fontSize * 0.9, weight: .medium))
                .foregroundColor(info.isSilent ? .secondary : .primary)
        }
    }

    @ViewBuilder
    private func coloredSyllableText(_ text: String) -> Text {
        var result = Text("")
        var foundFirstConsonant = false

        for char in text {
            let color: Color
            if !foundFirstConsonant, let consColor = consonantClassColor(char) {
                color = consColor
                foundFirstConsonant = true
            } else {
                color = .primary
            }
            result = result + Text(String(char))
                .foregroundColor(color)
                .font(.system(size: fontSize))
        }

        return result
    }

    /// Returnerer farge kun for konsonanter (nil for andre tegn)
    private func consonantClassColor(_ char: Character) -> Color? {
        let highConsonants = Set("ขฃฉฐถผฝศษสห")
        let midConsonants = Set("กจฎฏดตบปอ")

        for scalar in char.unicodeScalars {
            let baseChar = Character(scalar)
            if highConsonants.contains(baseChar) {
                return .red          // Høy klasse
            } else if midConsonants.contains(baseChar) {
                return .blue         // Mellom klasse
            }
            // Thai konsonant-range (0E01-0E2E) = Lav klasse
            if scalar.value >= 0x0E01 && scalar.value <= 0x0E2E {
                return .green        // Lav klasse
            }
        }
        return nil  // Ikke en konsonant
    }

    /// IPA tone letters
    private func toneSymbol(_ tone: ThaiTone) -> String {
        switch tone {
        case .high:    return "˥"      // Høy
        case .mid:     return "˧"      // Midt
        case .low:     return "˩"      // Lav
        case .falling: return "˥˩"     // Fallende
        case .rising:  return "˩˥"     // Stigende
        }
    }

    private func parseSyllableText(_ syllableText: String, source: String) -> ThaiSyllable? {
        analyzeThaiSyllableText(syllableText, source: source)
    }

    private func buildToneInfos(from syllables: [ThaiSyllable], source: String) -> [SyllableToneInfo] {
        syllables.enumerated().map { index, syllable in
            let firstCons = firstConsonant(in: syllable.original)
            let consClass = consonantClassString(for: firstCons)
            let codaChar = syllable.coda?.first
            let isLive = isLiveByIPA(nucleus: syllable.nucleus, coda: codaChar)
            let toneMarkStr = syllable.toneMark.map(String.init) ?? ""
            let vlenIPA = ThaiIPA.ipaForVowel(nucleus: syllable.nucleus, coda: codaChar)
            let toneOverride = ThaiPronunciationOverrides.toneOverride(
                word: word?.thaiWord,
                syllable: syllable.original
            )
            let isLongVowel = vlenIPA.contains("ː") ||
                ["aj","aw","ia","ɯa","ua","ej","oj","ɛj","ɔj","ɤj"].contains(vlenIPA)

            if codaChar == nil, let last = syllable.original.last {
                let thaiConsonants = Set("กขฃคฅฆงจฉชซฌญฎฏฐฑฒณดตถทธนบปผฝพฟภมยรฤลฦวศษสหฬอฮ")
                if thaiConsonants.contains(last) {
                    Logger.warning("[ToneDBG] \(source)[\(index)]: '\(syllable.original)' slutter på konsonant men har ingen coda. onset=\(syllable.onset) nucleus=\(syllable.nucleus) ipa=\(syllable.ipa ?? "nil")")
                }
            }

            Logger.debug("[ToneDBG] \(source)[\(index)]: '\(syllable.original)' onset=\(syllable.onset) nucleus=\(syllable.nucleus) coda=\(codaChar.map(String.init) ?? "nil") live=\(isLive) long=\(isLongVowel) vlenIPA=\(vlenIPA)")

            let toneStr = finnThaiTone(
                consonantClass: consClass,
                liveSyllable: isLive,
                ToneMark: toneMarkStr,
                lognVowel: isLongVowel
            )

            let tone = toneOverride?.tone ?? toneEnum(from: toneStr)
            let toneMark = ThaiPhonetics.toneDiacritic(tone)

            return SyllableToneInfo(
                syllable: syllable,
                consonantClass: consClass,
                isLive: isLive,
                isLongVowel: isLongVowel,
                hasToneMark: !toneMarkStr.isEmpty,
                toneMarkChar: toneMarkStr,
                tone: tone,
                toneMark: toneMark,
                isOverride: toneOverride != nil,
                overrideNote: toneOverride?.note
            )
        }
    }

    // MARK: - Parse hakeparentes-format

    private func parseBracketedSyllables(_ text: String) -> [ThaiSyllable] {
        // Sjekk først om det er array-format: ["word1","word2"]
        if text.hasPrefix("[\"") && text.hasSuffix("\"]") {
            return parseArrayFormat(text)
        }

        // Ellers bruk tradisjonelt hakeparentes-format: [word1][word2]
        // Ekstraher alt mellom [ og ]
        let pattern = "\\[([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var syllables: [ThaiSyllable] = []
        for match in matches {
            if match.numberOfRanges >= 2 {
                let syllableText = nsText.substring(with: match.range(at: 1))
                if let parsed = parseSyllableText(syllableText, source: "Bracketed") {
                    syllables.append(parsed)
                }
            }
        }

        return syllables
    }

    private func parseArrayFormat(_ text: String) -> [ThaiSyllable] {
        // Parse format: ["word1","word2","word3"]
        // Fjern [ og ] fra start/slutt
        var cleaned = text
        if cleaned.hasPrefix("[") { cleaned.removeFirst() }
        if cleaned.hasSuffix("]") { cleaned.removeLast() }

        // Split på ","
        let parts = cleaned.components(separatedBy: ",")
        var syllables: [ThaiSyllable] = []

        for part in parts {
            // Fjern anførselstegn og whitespace
            let syllableText = part.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))

            if syllableText.isEmpty { continue }

            if let parsed = parseSyllableText(syllableText, source: "ArrayFormat") {
                syllables.append(parsed)
            }
        }

        return syllables
    }

    // MARK: - Analyse

    private func analyzeSyllables(_ text: String) -> [SyllableToneInfo] {
        analyzeToneSentence(text, word: word, treatTextAsSingleSyllable: treatTextAsSingleSyllable)
    }
}

private struct SyllableRow: View {
    let info: SyllableToneInfo
    let fontSize: CGFloat
    let showInfoButtons: Bool
    let word: ThaiWords?
    let appState: AppState
    let context: NSManagedObjectContext
    let syllableView: (SyllableToneInfo) -> AnyView

    @State private var selectedInfo: SyllableToneInfo? = nil

    var body: some View {
        HStack(spacing: 6) {
            syllableView(info)
            if showInfoButtons {
                Button {
                    selectedInfo = info
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: fontSize * 0.9))
                        .foregroundColor(.blue.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $selectedInfo) { i in
            ToneExplanationView(info: i, word: word)
                .environment(appState)
                .environment(\.managedObjectContext, context)
                #if os(macOS) || targetEnvironment(macCatalyst)
                .frame(minWidth: 800, minHeight: 1200)
                #endif
        }
    }
}

// MARK: - Tone Explanation View

struct ToneExplanationView: View {
    let info: SyllableToneInfo
    var word: ThaiWords? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context

    @State private var showPronounceChecker = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Stavelsen
                    HStack {
                        Text(info.syllable.original)
                            .font(.system(size: 50, weight: .bold))
                            .strikethrough(info.isSilent, color: .secondary)
                            .opacity(info.isSilent ? 0.4 : 1.0)
                        Spacer()
                        if info.isSilent {
                            Text("Silent")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        } else {
                            VStack {
                                Text(toneSymbol(info.tone))
                                    .font(.system(size: 40, weight: .bold))
                                Text(toneNorsk(info.tone))
                                    .font(.headline)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                    Divider()

                    if info.isSilent {
                        silentExplanation()
                    } else {
                        explanationStep(
                            number: 1,
                            title: "Consonant class",
                            content: consonantClassExplanation(),
                            highlight: info.consonantClass
                        )

                        explanationStep(
                            number: 2,
                            title: "Syllable type",
                            content: liveDeadExplanation(),
                            highlight: info.isLive ? "LIVE" : "DEAD"
                        )

                        explanationStep(
                            number: 3,
                            title: "Vowel length",
                            content: vowelLengthExplanation(),
                            highlight: info.isLongVowel ? "LONG" : "SHORT"
                        )

                        if info.hasToneMark {
                            explanationStep(
                                number: 4,
                                title: "Tone mark",
                                content: toneMarkExplanation(),
                                highlight: info.toneMarkChar
                            )
                        }

                        Divider()

                        // IPA-generering
                        ipaSection()
                    }

                    if info.isOverride {
                        exceptionBanner()
                    }

                    if !info.isSilent {
                        Divider()

                        // Konklusjon
                        conclusionSection()
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Tone explanation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // TTS-knapp
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        CloudTTSTest.speakNorsk(info.syllable.original)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.blue)
                    }
                }

                // Uttale-knapp
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showPronounceChecker = true
                    } label: {
                        Image(systemName: "mic.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.blue)
                    }
                }

                // Kopier-knapp: kopierer nettopp DENNE stavelsen (info.syllable.original) til
                // utklippstavlen, i stedet for å åpne hele setningen/ordet vi kom fra (word) —
                // det var forvirrende å alltid åpne hele det opprinnelige ordet uansett hvilken
                // stavelse man faktisk sto på. Et automatisk søk-hopp virket klønete (måtte lukke
                // detaljvisningen underveis), så ren kopiering + kort bekreftelse er enklere.
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        UIPasteboard.general.string = info.syllable.original
                        Notifier.shared.show(.success, "Copied '\(info.syllable.original)'")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.blue)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.red)
                    }
                }
            }
            .sheet(isPresented: $showPronounceChecker) {
                if let thaiWord = word?.thaiWord {
                    ThaiPronounceCheckView(target: thaiWord)
                }
            }
        }
        .onAppear {
            Logger.debug("[ToneDBG] render ToneExplanationView original='\(info.syllable.original)' onset='\(info.syllable.onset)' nucleus='\(info.syllable.nucleus)' coda='\(info.syllable.coda ?? "nil")' live=\(info.isLive) tone=\(toneNorsk(info.tone)) word='\(word?.thaiWord ?? "nil")'")
        }
    }

    // MARK: - Explanation Components

    @ViewBuilder
    private func explanationStep(number: Int, title: String, content: String, highlight: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(number)")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.blue))
                Text(title)
                    .font(.headline)
                Spacer()
                Text(highlight)
                    .font(.headline)
                    .foregroundColor(highlightColor(for: highlight))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(highlightColor(for: highlight).opacity(0.2))
                    .cornerRadius(6)
            }
            Text(content)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
    }

    private func highlightColor(for text: String) -> Color {
        switch text {
        case "HIGH": return .red
        case "MID": return .blue
        case "LOW": return .primary
        case "LIVE": return .green
        case "DEAD": return .purple
        case "LONG": return .orange
        case "SHORT": return .cyan
        case "่", "้", "๊", "๋": return .indigo
        default: return .primary
        }
    }

    private func consonantClassExplanation() -> String {
        switch info.consonantClass {
        case "HIGH":
            return "ข ฃ ฉ ฐ ถ ผ ฝ ศ ษ ส ห"
        case "MID":
            return "ก จ ฎ ฏ ด ต บ ป อ"
        case "LOW":
            return "ค ง ช ซ ญ ณ ท ธ น พ ฟ ภ ม ย ร ล ว ฮ ..."
        default:
            return ""
        }
    }

    private func liveDeadExplanation() -> String {
        if info.isLive {
            Logger.debug("[ToneDBG] liveDeadExplanation -> LIVE for '\(info.syllable.original)' (coda=\(info.syllable.coda ?? "nil"))")
            return "Open or sonorant coda (ม น ง ว ย ร ล)"
        } else {
            Logger.debug("[ToneDBG] liveDeadExplanation -> DEAD for '\(info.syllable.original)' (coda=\(info.syllable.coda ?? "nil"))")
            return "Stop coda (ก ด บ) or short vowel"
        }
    }

    private func toneMarkExplanation() -> String {
        switch info.toneMarkChar {
        case "่":
            return "Mai ek → High/Mid=Low, Low=Falling"
        case "้":
            return "Mai tho → High/Mid=Falling, Low=High"
        case "๊":
            return "Mai tri → High"
        case "๋":
            return "Mai chattawa → Rising"
        default:
            return ""
        }
    }

    private func vowelLengthExplanation() -> String {
        let nucleus = info.syllable.nucleus ?? ""
        let longVowelExamples = "า, แ, โ, เา, เอ, เอา, ใ, ไ, อ, เอีย, เออ, ัว, and diphthongs (อย, อว ...)"
        let shortVowelExamples = "อ็, อิ, อี, อุ, เ-ะ, แ-ะ, โ-ะ, เ-าะ, -ะ"

        if info.isLongVowel {
            return "Long vowel (nucleus: \(nucleus)) like \(longVowelExamples)"
        } else {
            return "Short vowel (nucleus: \(nucleus)) like \(shortVowelExamples)"
        }
    }

    @ViewBuilder
    private func silentExplanation() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("1")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.gray))
                Text("Silent cluster")
                    .font(.headline)
                Spacer()
                Text("SILENT")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(6)
            }
            Text("'\(info.syllable.original)' is a known silent consonant cluster (garan/thanthakhat over the whole group, common in Sanskrit/Pali loanwords). It is written as its own syllable but is not pronounced at all.")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func exceptionBanner() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Exception")
                .font(.caption.bold())
                .foregroundColor(.orange)

            Text(info.overrideNote ?? "Dictionary override for this word")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.12))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func ipaSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("IPA transcription")
                .font(.headline)

            let ipa = generateIPA()

            VStack(spacing: 12) {
                // IPA med tone
                HStack {
                    Text("IPA:")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(ipa)
                        .font(.custom("Charis-Regular", size: 32))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)

                // Forklaring av komponenter
                VStack(alignment: .leading, spacing: 6) {
                    ipaComponentRow("Onset:", ipaOnset())
                    ipaComponentRow("Vowel:", ipaVowel())
                    ipaComponentRow("Coda:", ipaCoda())
                    ipaComponentRow("Tone:", toneSymbol(info.tone))
                }
                .font(.body)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func ipaComponentRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value.isEmpty ? "–" : value)
                .font(.custom("Charis-Regular", size: 20))
                .foregroundColor(value.isEmpty ? .secondary : .primary)
        }
    }

    private func generateIPA() -> String {
        toneIPA(for: info)
    }

    private func ipaOnset() -> String {
        let onset = info.syllable.onset
        guard !onset.isEmpty, let firstChar = onset.first else {
            Logger.debug("[ToneDBG] ipaOnset -> empty for '\(info.syllable.original)'")
            return ""
        }
        let result = ThaiIPA.ipaForOnsetChar(firstChar)
        Logger.debug("[ToneDBG] ipaOnset '\(info.syllable.original)' onset='\(onset)' -> '\(result)'")
        return result
    }

    private func ipaVowel() -> String {
        let result = ThaiIPA.ipaForVowel(nucleus: info.syllable.nucleus, coda: effectiveCodaChar(info.syllable.coda))
        Logger.debug("[ToneDBG] ipaVowel '\(info.syllable.original)' nucleus='\(info.syllable.nucleus)' coda='\(info.syllable.coda ?? "nil")' -> '\(result)'")
        return result
    }

    private func ipaCoda() -> String {
        guard let coda = effectiveCodaChar(info.syllable.coda) else {
            let fallback = (!info.isLive && !info.isReducedLeader) ? "ʔ" : ""
            Logger.debug("[ToneDBG] ipaCoda '\(info.syllable.original)' has no DB coda; live=\(info.isLive) -> fallback='\(fallback)'")
            return fallback
        }
        let result = ThaiIPA.ipaForCoda(coda)
        Logger.debug("[ToneDBG] ipaCoda '\(info.syllable.original)' coda='\(coda)' -> '\(result)'")
        return result
    }

    @ViewBuilder
    private func conclusionSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conclusion")
                .font(.headline)

            HStack(spacing: 20) {
                VStack {
                    Text(toneSymbol(info.tone))
                        .font(.system(size: 60, weight: .bold))
                    Text(toneNorsk(info.tone))
                        .font(.title2.bold())
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 4) {
                    ruleText()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func ruleText() -> some View {
        let cls = info.consonantClass
        let live = info.isLive
        let mark = info.toneMarkChar
        let long = info.isLongVowel

        VStack(alignment: .leading, spacing: 4) {
            if info.isOverride {
                Text("Source:")
                    .font(.caption.bold())
                Text(info.overrideNote ?? "Dictionary override")
                    .font(.body)
            } else if !mark.isEmpty {
                Text("Rule:")
                    .font(.caption.bold())
                Text("\(classEnglish(cls)) + \(mark)")
                    .font(.body)
            } else if live {
                Text("Rule:")
                    .font(.caption.bold())
                Text("\(classEnglish(cls)) + Live")
                    .font(.body)
            } else {
                Text("Rule:")
                    .font(.caption.bold())
                if cls == "LOW" {
                    Text("\(classEnglish(cls)) + Dead + \(long ? "Long" : "Short")")
                        .font(.body)
                } else {
                    Text("\(classEnglish(cls)) + Dead")
                        .font(.body)
                }
            }
        }
    }

    private func classEnglish(_ cls: String) -> String {
        switch cls {
        case "HIGH": return "High"
        case "MID": return "Mid"
        case "LOW": return "Low"
        default: return cls
        }
    }

    private func toneSymbol(_ tone: ThaiTone) -> String {
        switch tone {
        case .high:    return "˥"
        case .mid:     return "˧"
        case .low:     return "˩"
        case .falling: return "˥˩"
        case .rising:  return "˩˥"
        }
    }

    private func toneNorsk(_ tone: ThaiTone) -> String {
        switch tone {
        case .mid:     return "Mid"
        case .low:     return "Low"
        case .high:    return "High"
        case .falling: return "Falling"
        case .rising:  return "Rising"
        }
    }
}

// MARK: - Data Model

struct SyllableToneInfo: Identifiable {
    let id: UUID
    let syllable: ThaiSyllable
    let consonantClass: String      // "HIGH", "MID", "LOW"
    let isLive: Bool                // Live (sonorant coda) or Dead (stop coda)
    let isLongVowel: Bool           // Long or short vowel
    let hasToneMark: Bool           // Has explicit tone mark
    let toneMarkChar: String        // The tone mark character if present
    let tone: ThaiTone              // Calculated tone
    let toneMark: String            // IPA tone diacritic
    let isOverride: Bool
    let overrideNote: String?
    let isSilent: Bool               // Whole syllable is a known silent cluster (e.g. "ทร์")
    let isReducedLeader: Bool        // อักษรนำ: redusert leder-konsonant (f.eks. "ต" i "ตลาด") — vanlig tone, men uten glottalstopp

    init(
        syllable: ThaiSyllable,
        consonantClass: String,
        isLive: Bool,
        isLongVowel: Bool,
        hasToneMark: Bool,
        toneMarkChar: String,
        tone: ThaiTone,
        toneMark: String,
        isOverride: Bool = false,
        overrideNote: String? = nil,
        isSilent: Bool = false,
        isReducedLeader: Bool = false
    ) {
        self.id = UUID()
        self.syllable = syllable
        self.consonantClass = consonantClass
        self.isLive = isLive
        self.isLongVowel = isLongVowel
        self.hasToneMark = hasToneMark
        self.toneMarkChar = toneMarkChar
        self.tone = tone
        self.toneMark = toneMark
        self.isOverride = isOverride
        self.overrideNote = overrideNote
        self.isSilent = isSilent
        self.isReducedLeader = isReducedLeader
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        Text("Tone-analyse:").font(.headline)

        ToneAnnotatedSentenceView(text: "สวัสดี", fontSize: 30)
        ToneAnnotatedSentenceView(text: "ขอบคุณ", fontSize: 30)
        ToneAnnotatedSentenceView(text: "ผมชอบกินข้าว", fontSize: 26)

        Divider()

        Text("IPA Tone Letters:").font(.subheadline)
        HStack(spacing: 16) {
            HStack { Text("˥").bold(); Text("High") }
            HStack { Text("˧").bold(); Text("Mid") }
            HStack { Text("˩").bold(); Text("Low") }
            HStack { Text("˥˩").bold(); Text("Falling") }
            HStack { Text("˩˥").bold(); Text("Rising") }
        }
        .font(.caption)
    }
    .padding()
    .environment(AppState())
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
