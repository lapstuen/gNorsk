//
//  CreateWordView.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/18/25.
//
import SwiftUI
import CoreData
import AVFoundation

struct CreateWordView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @State private var thaiWord = ""
    @State private var englishWord = ""
    @State private var morsmaal = ""
    @State private var isTranslating = false
    @State private var wordExists = false
    @State private var existingWord: ThaiWords?
    @State private var showExistingWordDetails = false
    @State private var extractedTimestamp: String? = nil
    @State private var notes = ""
    @State private var lagredeOrd: [(thai: String, timestamp: String?, english: String)] = []
    @State private var skipNextTimestampCheck = false
    @State private var batchEntries: [(timestamp: String, thai: String)] = []
    @State private var transcriptPasteText: String = ""
    @State private var showTranscriptImport = false
    @FocusState private var focusedField: Field?
    @State private var speechManager = SpeechManager(locale: Locale(identifier: "en-US"))
    @AppStorage("speechInputMode") private var speechMode: SpeechMode = .english
    @AppStorage("morsmaalLanguage") private var morsmaalLanguage: MorsmaalLanguage = .norsk
    @State private var wordType: Int16 = 0
    @State private var speechSynth = AVSpeechSynthesizer()

    private let overrideGroupId: Int16?
    /// Når satt: dette vinduet lager ikke et frittstående nytt ord, men en setning som
    /// knyttes til et eksisterende ord (samme funksjon AddSentenceView tidligere hadde
    /// alene) — lagres i #xSentencesForWords-gruppen og tagges med linkedWord sitt ord.
    private let linkedWord: ThaiWords?

    enum Field {
        case morsmaal, thai, english
    }

    enum SpeechMode: String, CaseIterable {
        case english, norsk, thai

        // .norsk = morsmål-feltet (dynamisk, følger "Native language"-innstillingen — nå Thai).
        // .thai = hovedordfeltet (thaiWord), som i gNorsk alltid er norsk, uansett innstilling.
        func label(morsmaal: MorsmaalLanguage) -> String {
            switch self {
            case .english: return "English"
            case .norsk: return morsmaal.label
            case .thai: return "Norwegian"
            }
        }

        func locale(morsmaal: MorsmaalLanguage) -> Locale {
            switch self {
            case .english: return Locale(identifier: "en-US")
            case .norsk: return Locale(identifier: morsmaal.locale)
            case .thai: return Locale(identifier: "nb-NO")
            }
        }
    }

    init(initialThaiWord: String = "", overrideGroupId: Int16? = nil, linkedWord: ThaiWords? = nil) {
        _thaiWord = State(initialValue: initialThaiWord)
        self.overrideGroupId = linkedWord != nil ? kSentencesForWordsGroupID : overrideGroupId
        self.linkedWord = linkedWord
    }

    // Parses YouTube transcript format: "0:08 8 secondsกระทรวง..." → ("0:08", "กระทรวง...")
    private static func parseYouTubeInput(_ input: String) -> (timestamp: String?, thaiText: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find colon for timestamp
        guard let colonIdx = trimmed.firstIndex(of: ":"),
              colonIdx > trimmed.startIndex else {
            return (nil, trimmed)
        }

        // Digits before colon
        let beforeColon = trimmed[trimmed.startIndex..<colonIdx]
        guard !beforeColon.isEmpty, beforeColon.allSatisfy({ $0.isNumber }) else {
            return (nil, trimmed)
        }

        // Digits after colon (seconds)
        let afterColon = trimmed[trimmed.index(after: colonIdx)...]
        let secondsDigits = afterColon.prefix(while: { $0.isNumber })
        guard !secondsDigits.isEmpty else {
            return (nil, trimmed)
        }

        // Take exactly 2 digits for seconds (YouTube format repeats them: "0:3434 seconds")
        let secondsTrimmed = secondsDigits.prefix(2)
        let timestamp = "\(beforeColon):\(secondsTrimmed)"
        let afterTimestamp = String(trimmed[trimmed.index(colonIdx, offsetBy: 1 + secondsTrimmed.count)...])

        // Find first Thai character (Unicode block U+0E00–U+0E7F)
        guard let thaiIdx = afterTimestamp.firstIndex(where: { char in
            char.unicodeScalars.first.map { $0.value >= 0x0E00 && $0.value <= 0x0E7F } ?? false
        }) else {
            return (timestamp, "")
        }

        let thaiText = stripBracketedContent(String(afterTimestamp[thaiIdx...]))
        return (timestamp, thaiText)
    }

    // Fjerner "[...]"-markører (f.eks. "[เพลง]", "[เสียงหัวเราะ]") og innholdet i dem,
    // som YouTubes auto-tekstingsformat bruker for sang/lyd-markører, ikke faktisk tale.
    private static func stripBracketedContent(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        return stripped
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Same as stripBracketedContent, but for a sequence of segments where a "[...]" marker
    // can be split across two consecutive segments by a timestamp line landing in between
    // (segment N ends with a dangling "[", segment N+1 starts with the matching "]").
    // Tracks that carried-over open-bracket state across the whole sequence.
    private static func stripBracketsAcrossSegments(_ segments: [String]) -> [String] {
        var insideBracket = false
        var result: [String] = []
        for raw in segments {
            var text = raw
            if insideBracket {
                if let closeIdx = text.firstIndex(of: "]") {
                    text = String(text[text.index(after: closeIdx)...])
                    insideBracket = false
                } else {
                    // Whole segment is still inside the carried-over bracket.
                    result.append("")
                    continue
                }
            }
            text = text.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            if let openIdx = text.lastIndex(of: "["), !text[openIdx...].contains("]") {
                text = String(text[..<openIdx])
                insideBracket = true
            }
            result.append(
                text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result
    }

    // YouTube's copy-pasted transcript puts each timestamp at the START of a line — either
    // alone on its own line, or inline as "(MM:SS) caption text..." / "MM:SS caption
    // text...", with the caption continuing on that same line and/or following lines until
    // the next line that starts with a timestamp. Anchoring on line-start (rather than
    // scanning the whole blob) can't be fooled by "digit:digit digit" patterns that happen
    // to appear inside the spoken dialogue itself (e.g. a scene where characters read out
    // numbers), which the older inline scanner below would misfire on. Falls back to that
    // scanner only if no line starts with a timestamp at all (e.g. one concatenated block).
    private static func parseMultipleEntries(_ input: String) -> [(timestamp: String, thai: String)] {
        let lineBased = parseMultipleEntriesLineBased(input)
        if lineBased.count > 1 { return lineBased }
        return parseMultipleEntriesInline(input)
    }

    private static func parseMultipleEntriesLineBased(_ rawInput: String) -> [(timestamp: String, thai: String)] {
        // YouTube's transcript panel sometimes copies a trailing UI control along with the
        // text — strip it if present rather than let it get glued onto the last entry.
        let input = rawInput.replacingOccurrences(
            of: #"\s*Sync to video time\s*$"#, with: "", options: .regularExpression
        )
        // Timestamp ("M:SS"/"MM:SS"/"H:MM:SS"), anchored at the START of the line, in any of
        // the three shapes YouTube's "copy transcript" produces:
        //   "0:10"                      — bare, alone on its own line
        //   "(0:10) caption..."         — parenthesized, caption inline on the same line
        //   "0:1010 secondscaption..."  — plain, immediately followed (no separator) by a
        //                                 redundant screen-reader duration label ("10
        //                                 seconds" / "1 minute, 1 second" / "10 minutes, 8
        //                                 seconds"), then the caption — an artifact of
        //                                 copying the transcript panel's accessible text.
        // NOT requiring the whole line to be just the timestamp, since the caption text
        // frequently continues right after it on the same line.
        let durationLabel = #"\d+\s+(?:hour|minute|second)s?(?:,\s*\d+\s+(?:hour|minute|second)s?){0,2}"#
        let pattern = try! NSRegularExpression(pattern: #"^\(?(\d{1,2}(?::\d{2}){1,2})\)?(?:"# + durationLabel + #")?\s*"#)
        let lines = input.components(separatedBy: .newlines)

        var found: [(ts: String, lineIndex: Int, restOfLine: String)] = []
        for (idx, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let range = NSRange(line.startIndex..., in: line)
            if let match = pattern.firstMatch(in: line, range: range),
               let tsRange = Range(match.range(at: 1), in: line),
               let wholeRange = Range(match.range, in: line) {
                found.append((ts: String(line[tsRange]), lineIndex: idx, restOfLine: String(line[wholeRange.upperBound...])))
            }
        }
        guard found.count > 1 else { return [] }

        // Raw text between each pair of consecutive timestamps, still un-stripped — starts
        // with whatever followed the timestamp on its own line, then any following lines up
        // to (not including) the next timestamp line.
        let rawSegments: [String] = found.enumerated().map { n, entry in
            let endLine = n + 1 < found.count ? found[n + 1].lineIndex : lines.count
            var parts = [entry.restOfLine]
            if entry.lineIndex + 1 < endLine {
                parts.append(contentsOf: lines[(entry.lineIndex + 1)..<endLine])
            }
            return parts.joined(separator: " ")
        }
        // Strip "[...]" markers as one continuous pass across all segments in order — a
        // marker can get split by a timestamp line landing between its "[" and "]" (the
        // "[" ends one segment, "...] " starts the next), so stripping segment-by-segment
        // in isolation leaves the orphaned half behind.
        let strippedSegments = stripBracketsAcrossSegments(rawSegments)

        var results: [(timestamp: String, thai: String)] = []
        for (n, entry) in found.enumerated() {
            let segment = strippedSegments[n]
            guard let thaiIdx = segment.firstIndex(where: { c in
                c.unicodeScalars.first.map { $0.value >= 0x0E00 && $0.value <= 0x0E7F } ?? false
            }) else { continue }

            let thaiText = String(segment[thaiIdx...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !thaiText.isEmpty {
                results.append((timestamp: entry.ts, thai: thaiText))
            }
        }
        return results
    }

    // Scans inline for MM:SS timestamps — works whether entries are separated by
    // newlines or concatenated in one block (YouTube transcript copy-paste format).
    // Fallback only: can misfire on colon-digit patterns embedded in running dialogue text
    // (see parseMultipleEntries above), which is why the line-anchored parse is tried first.
    private static func parseMultipleEntriesInline(_ input: String) -> [(timestamp: String, thai: String)] {
        // Step 1: find all timestamp positions
        var found: [(ts: String, start: String.Index, end: String.Index)] = []
        var i = input.startIndex

        while i < input.endIndex {
            guard input[i].isNumber else { i = input.index(after: i); continue }

            // Collect 1–2 minute digits
            let minStart = i
            var minEnd = i
            var minCount = 0
            while minEnd < input.endIndex && input[minEnd].isNumber && minCount < 2 {
                minEnd = input.index(after: minEnd)
                minCount += 1
            }
            guard minCount >= 1, minEnd < input.endIndex, input[minEnd] == ":" else {
                i = input.index(after: i); continue
            }

            // Collect exactly 2 second digits
            let afterColon = input.index(after: minEnd)
            guard afterColon < input.endIndex && input[afterColon].isNumber else {
                i = input.index(after: i); continue
            }
            var secEnd = afterColon
            var secCount = 0
            while secEnd < input.endIndex && input[secEnd].isNumber && secCount < 2 {
                secEnd = input.index(after: secEnd)
                secCount += 1
            }
            guard secCount == 2 else { i = input.index(after: i); continue }

            var ts = "\(String(input[minStart..<minEnd])):\(String(input[afterColon..<secEnd]))"
            var end = secEnd

            // Optional third ":SS" group — "H:MM:SS" past the 1-hour mark. Without this,
            // "1:00:10" would be truncated to just "1:00", losing the seconds.
            if secEnd < input.endIndex, input[secEnd] == ":" {
                let afterColon2 = input.index(after: secEnd)
                if afterColon2 < input.endIndex, input[afterColon2].isNumber {
                    var secEnd2 = afterColon2
                    var secCount2 = 0
                    while secEnd2 < input.endIndex && input[secEnd2].isNumber && secCount2 < 2 {
                        secEnd2 = input.index(after: secEnd2)
                        secCount2 += 1
                    }
                    if secCount2 == 2 {
                        ts += ":\(String(input[afterColon2..<secEnd2]))"
                        end = secEnd2
                    }
                }
            }

            found.append((ts: ts, start: minStart, end: end))
            i = end
        }

        guard found.count > 1 else { return [] }

        // Step 2: extract Thai text between consecutive timestamps. Bracket-stripping runs
        // as one continuous pass across all segments (see parseMultipleEntriesLineBased) so
        // a "[...]" marker split across a timestamp boundary is still handled correctly.
        let rawSegments: [String] = found.enumerated().map { n, entry in
            let segEnd = n + 1 < found.count ? found[n + 1].start : input.endIndex
            return String(input[entry.end..<segEnd])
        }
        let strippedSegments = stripBracketsAcrossSegments(rawSegments)

        var results: [(timestamp: String, thai: String)] = []
        for (n, entry) in found.enumerated() {
            let segment = strippedSegments[n]
            guard let thaiIdx = segment.firstIndex(where: { c in
                c.unicodeScalars.first.map { $0.value >= 0x0E00 && $0.value <= 0x0E7F } ?? false
            }) else { continue }

            let thaiText = String(segment[thaiIdx...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !thaiText.isEmpty {
                results.append((timestamp: entry.ts, thai: thaiText))
            }
        }
        return results
    }

    private func checkIfWordExists() {
        let trimmed = thaiWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            wordExists = false
            existingWord = nil
            return
        }

        let fetch: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        fetch.predicate = NSPredicate(format: "thaiWord == %@", trimmed)
        fetch.fetchLimit = 1

        do {
            let results = try context.fetch(fetch)
            if let found = results.first {
                wordExists = true
                existingWord = found
                // Trigger automatisk søk (kommentert ut - blir i vinduet)
                // DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                //     appState.pendingSearchText = trimmed
                //     dismiss()
                // }
            } else {
                wordExists = false
                existingWord = nil
            }
        } catch {
            wordExists = false
            existingWord = nil
        }
    }

    func lagreNyttOrd() {
        let trimmedThai = thaiWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMorsmaal = morsmaal.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEnglish = englishWord.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedThai.isEmpty || !trimmedMorsmaal.isEmpty else {
            Notifier.shared.show(.warning, "Enter Norwegian or native text before saving.")
            return
        }

        // Ikke tillat lagring hvis ordet eksisterer
        guard !wordExists else {
            return
        }

        if trimmedThai.isEmpty, !trimmedMorsmaal.isEmpty {
            lookupThaiAndEnglishFromMorsmaal(sourceText: trimmedMorsmaal, saveAfterLookup: true)
            return
        }

        if trimmedEnglish.isEmpty {
            isTranslating = true
            translateText(text: trimmedThai, fromLanguage: "no", toLanguage: "en") { [self] translation in
                DispatchQueue.main.async {
                    self.isTranslating = false
                    guard let translation else {
                        Notifier.shared.show(.error, "Translation failed — fill in English manually and save again.")
                        return
                    }
                    self.englishWord = translation
                    self.saveWordToCoreData(
                        thaiWord: trimmedThai,
                        englishWord: translation,
                        morsmaal: trimmedMorsmaal.isEmpty ? nil : trimmedMorsmaal
                    )
                }
            }
        } else {
            saveWordToCoreData(
                thaiWord: trimmedThai,
                englishWord: trimmedEnglish,
                morsmaal: trimmedMorsmaal.isEmpty ? nil : trimmedMorsmaal
            )
        }
    }


    private func lookupThaiAndEnglishFromMorsmaal(sourceText: String, saveAfterLookup: Bool) {
        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }

        let sourceLanguage = morsmaalLanguage.translationCode
        let needsThai = thaiWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let needsEnglish = englishWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if !needsThai && !needsEnglish {
            if saveAfterLookup {
                saveWordToCoreData(
                    thaiWord: thaiWord,
                    englishWord: englishWord,
                    morsmaal: source
                )
            }
            return
        }

        isTranslating = true
        var resolvedThai = thaiWord.trimmingCharacters(in: .whitespacesAndNewlines)
        var resolvedEnglish = englishWord.trimmingCharacters(in: .whitespacesAndNewlines)
        var translationFailed = false
        let group = DispatchGroup()

        if needsThai {
            group.enter()
            translateText(text: source, fromLanguage: sourceLanguage, toLanguage: "no") { translation in
                DispatchQueue.main.async {
                    if let translation {
                        resolvedThai = translation
                        self.thaiWord = resolvedThai
                    } else {
                        translationFailed = true
                    }
                    group.leave()
                }
            }
        }

        if needsEnglish {
            group.enter()
            translateText(text: source, fromLanguage: sourceLanguage, toLanguage: "en") { translation in
                DispatchQueue.main.async {
                    if let translation {
                        resolvedEnglish = translation
                        self.englishWord = translation
                    } else {
                        translationFailed = true
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            self.isTranslating = false
            if translationFailed {
                Notifier.shared.show(.error, "Translation failed — fill in the missing field(s) manually and save again.")
                return
            }
            if saveAfterLookup {
                self.saveWordToCoreData(
                    thaiWord: resolvedThai,
                    englishWord: resolvedEnglish,
                    morsmaal: source
                )
            }
        }
    }

    private func saveWordToCoreData(thaiWord: String, englishWord: String, morsmaal: String? = nil) {
        // Lenket setning-modus: ikke opprett et duplikat hvis setningen/ordet allerede finnes —
        // legg i stedet til en tag som kobler det eksisterende ordet til linkedWord, samme som
        // AddSentenceView sin "already exists" → "Save link"-oppførsel gjorde.
        if let linkedWord, wordExists, let existing = existingWord {
            let linkTag = linkedWord.thaiWord ?? ""
            if existing.hasTag(linkTag) {
                Notifier.shared.show(.success, "Link already saved!")
            } else {
                existing.addTag(linkTag)
                do {
                    try context.save()
                    Notifier.shared.show(.success, "Link added!")
                } catch {
                    Notifier.shared.show(.error, "Could not save link: \(error.localizedDescription)")
                    return
                }
            }
            resetForm()
            return
        }

        do {
            let nyttOrd = ThaiWords(context: context)
            nyttOrd.id          = UUID()
            nyttOrd.modifiedDate = Date()
            nyttOrd.thaiWord    = thaiWord.precomposedStringWithCanonicalMapping
            nyttOrd.englishWord = englishWord
            nyttOrd.translation1 = morsmaal?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? morsmaal : nil
            // Type-velgeren (Word/Sentence) er skjult — nyopprettede ord skal alltid være Word.
            nyttOrd.wordType    = 0
            // Use overrideGroupId if set, otherwise use current group
            nyttOrd.groupId     = overrideGroupId ?? appState.sqlGruppeId
            if let linkedWord {
                nyttOrd.tags = ",\(linkedWord.thaiWord ?? ""),"
            }
            let notesTrimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notesTrimmed.isEmpty {
                nyttOrd.notes = notesTrimmed
            }

            try context.save()

            lagredeOrd.insert((thai: thaiWord, timestamp: extractedTimestamp, english: englishWord), at: 0)
            Notifier.shared.show(.success, "Saved: \(thaiWord)")
            resetForm()

        } catch {
            Notifier.shared.show(.error, "Failed to create word: \(error.localizedDescription)")
        }
    }

    private func saveBatchEntries() {
        let groupId = overrideGroupId ?? appState.sqlGruppeId
        let count = batchEntries.count
        var savedWords: [ThaiWords] = []

        for entry in batchEntries {
            let nyttOrd = ThaiWords(context: context)
            nyttOrd.id = UUID()
            nyttOrd.modifiedDate = Date()
            nyttOrd.thaiWord = entry.thai
            nyttOrd.englishWord = ""
            nyttOrd.groupId = groupId
            nyttOrd.wordType = 1  // YouTube transcript entries are sentences
            nyttOrd.notes = entry.timestamp
            lagredeOrd.insert((thai: entry.thai, timestamp: entry.timestamp, english: ""), at: 0)
            savedWords.append(nyttOrd)
        }
        do {
            try context.save()
            batchEntries = []
            transcriptPasteText = ""
            thaiWord = ""
            notes = ""
            extractedTimestamp = nil
            Notifier.shared.show(.success, "Saved \(count) entries – translating...")
            dismiss()
        } catch {
            Notifier.shared.show(.error, "Error: \(error.localizedDescription)")
            return
        }

        for word in savedWords {
            guard let thai = word.thaiWord, !thai.isEmpty else { continue }
            if (word.englishWord ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                translateText(text: thai, fromLanguage: "no", toLanguage: "en") { translation in
                    DispatchQueue.main.async {
                        guard let translation else {
                            Notifier.shared.show(.error, "Translation to English failed for \(thai).")
                            return
                        }
                        word.englishWord = translation
                        try? word.managedObjectContext?.save()
                    }
                }
            }
            if (word.translation1 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                translateText(text: thai, fromLanguage: "no", toLanguage: "th") { translation in
                    DispatchQueue.main.async {
                        guard let translation else {
                            Notifier.shared.show(.error, "Translation to Thai failed for \(thai).")
                            return
                        }
                        word.translation1 = translation
                        try? word.managedObjectContext?.save()
                    }
                }
            }
        }
    }

    /// Ved enhver feil kalles `completion(nil)` — kalleren skal vise en feilmelding og la feltet
    /// stå tomt, ikke late som kildeteksten var en gyldig oversettelse. Tidligere kalte denne
    /// funksjonen et uoffisielt Google-endepunkt direkte; bruker nå den delte
    /// AppleTranslationService (se SwiftGeneral/AppleTranslationService.swift).
    private func translateText(text: String, fromLanguage: String, toLanguage: String, completion: @escaping (String?) -> Void) {
        AppleTranslationService.shared.translate(text: text, fromLanguage: fromLanguage, toLanguage: toLanguage, completion: completion)
    }

    private static func lowercasedFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    /// Fyller ut de(t) av norsk/engelsk/morsmål som fortsatt er tomt, ut fra en kildetekst på et
    /// kjent språk — brukes både når det norske feltet mister fokus, og når mikrofon-diktering er
    /// ferdig (uansett hvilket av de tre språkene man dikterte på).
    private func translateMissingFields(sourceText: String, sourceLanguageCode: String) {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if sourceLanguageCode != "en", englishWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            translateText(text: trimmed, fromLanguage: sourceLanguageCode, toLanguage: "en") { translation in
                DispatchQueue.main.async {
                    guard englishWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    guard let translation else {
                        Notifier.shared.show(.error, "English translation failed — fill in manually.")
                        return
                    }
                    englishWord = translation
                }
            }
        }
        if sourceLanguageCode != "no", thaiWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            translateText(text: trimmed, fromLanguage: sourceLanguageCode, toLanguage: "no") { translation in
                DispatchQueue.main.async {
                    guard thaiWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    guard let translation else {
                        Notifier.shared.show(.error, "Norwegian translation failed — fill in manually.")
                        return
                    }
                    thaiWord = translation.prefix(1).lowercased() + translation.dropFirst()
                }
            }
        }
        if sourceLanguageCode != morsmaalLanguage.translationCode, morsmaal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            translateText(text: trimmed, fromLanguage: sourceLanguageCode, toLanguage: morsmaalLanguage.translationCode) { translation in
                DispatchQueue.main.async {
                    guard morsmaal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    guard let translation else {
                        Notifier.shared.show(.error, "\(morsmaalLanguage.label) translation failed — fill in manually.")
                        return
                    }
                    morsmaal = translation
                }
            }
        }
    }

    private func resetForm() {
        thaiWord = ""
        englishWord = ""
        morsmaal = ""
        notes = ""
        extractedTimestamp = nil
        wordExists = false
        wordType = 0
        skipNextTimestampCheck = false
        batchEntries = []
    }

    private func speak(_ text: String, language: String, voiceId: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceId) ?? AVSpeechSynthesisVoice(language: language)
        utterance.rate = 0.45
        utterance.volume = 1.0
        if speechSynth.isSpeaking { speechSynth.stopSpeaking(at: .immediate) }
        speechSynth.speak(utterance)
    }

    private func languageSectionHeader(_ title: String, speak: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: speak) {
                Image(systemName: "speaker.wave.2.fill")
            }
            .buttonStyle(.plain)
        }
    }

    var body: some View {
        
        Form {
            Section {
                HStack {
                    Button {
                        resetForm()
                    } label: {
                        Label("Clear form", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .imageScale(.large)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let groupId = overrideGroupId {
                    Text("Saving to group: #xAutoCreatedWords (ID: \(groupId))")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } else {
                    Text("Current group: \(appState.valgtGruppeNavn.isEmpty ? "Not set" : appState.valgtGruppeNavn) id: \(appState.sqlGruppeId)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if !lagredeOrd.isEmpty {
                Section(header: Text("Saved this session (\(lagredeOrd.count))")) {
                    ForEach(Array(lagredeOrd.enumerated()), id: \.offset) { _, ord in
                        HStack(spacing: 6) {
                            Text(ord.timestamp ?? "–")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(ord.timestamp != nil ? .green : .secondary)
                                .frame(width: 44, alignment: .leading)
                            Text(ord.thai)
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                            Text(ord.english.isEmpty ? "–" : ord.english)
                                .font(.caption)
                                .foregroundColor(ord.english.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                        }
                    }
                }
            }

            if showTranscriptImport {
                Section {
                    DisclosureGroup("Import full transcript", isExpanded: $showTranscriptImport) {
                        Button {
                            let entries = Self.parseMultipleEntries(transcriptPasteText)
                            if entries.isEmpty {
                                Notifier.shared.show(.error, "No timestamped entries found in the pasted text")
                            } else {
                                batchEntries = entries
                                Notifier.shared.show(.success, "Parsed \(entries.count) entries — review below, then Save all")
                            }
                        } label: {
                            Label("Parse", systemImage: "text.magnifyingglass")
                        }
                        .disabled(transcriptPasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Text("Paste the whole transcript below, then tap Parse above. This reads the text once, in full, when you tap the button — unlike the Thai field above, it doesn't try to detect batches as you type/paste, which is unreliable for very large pastes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $transcriptPasteText)
                            .frame(height: 220)
                            .font(.callout)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                    }
                }
            }

            if !batchEntries.isEmpty {
                Section(header: Text("Batch: \(batchEntries.count) entries")) {
                    ForEach(Array(batchEntries.enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 6) {
                            Text(entry.timestamp)
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.green)
                                .frame(width: 44, alignment: .leading)
                            Text(entry.thai)
                                .font(.caption)
                                .lineLimit(2)
                        }
                    }
                }
            }
            Section(header: languageSectionHeader("Norwegian") {
                speak(thaiWord, language: MorsmaalLanguage.norsk.locale, voiceId: MorsmaalLanguage.norsk.voiceId)
            }) {
                TextField("Norwegian word", text: $thaiWord)
                    .font(Font.largeTitle.bold())
                    .focused($focusedField, equals: .thai)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .onChange(of: focusedField) { oldValue, _ in
                        guard oldValue == .thai else { return }
                        // Systemets automatiske stor forbokstav (aktiveres ved fokus-tap, ikke
                        // ved tasting — .textInputAutocapitalization(.never) hindrer den ikke her,
                        // trolig Mac Catalyst sin egen "Capitalize words automatically"-innstilling)
                        // rettes tilbake til liten forbokstav idet feltet mister fokus.
                        if let first = thaiWord.first, first.isUppercase {
                            thaiWord = thaiWord.prefix(1).lowercased() + thaiWord.dropFirst()
                        }

                        // Start oversettelse til engelsk og morsmål (thai) med en gang feltet
                        // forlates, samme prinsipp som "Oversett"-menypunktet i detaljvisningen —
                        // ikke vent til brukeren evt. åpner detaljvisningen senere.
                        translateMissingFields(sourceText: thaiWord, sourceLanguageCode: "no")
                    }
                    .onChange(of: thaiWord) { _, newValue in
                        // Batch mode: multiple timestamp entries pasted
                        let entries = Self.parseMultipleEntries(newValue)
                        if entries.count > 1 {
                            batchEntries = entries
                            return
                        }
                        batchEntries = []

                        // Skip timestamp extraction when we programmatically changed thaiWord
                        if skipNextTimestampCheck {
                            skipNextTimestampCheck = false
                        } else {
                            let parsed = Self.parseYouTubeInput(newValue)
                            if let timestamp = parsed.timestamp {
                                extractedTimestamp = timestamp
                                notes = timestamp
                                if thaiWord != parsed.thaiText {
                                    skipNextTimestampCheck = true
                                    thaiWord = parsed.thaiText
                                    return
                                }
                            } else {
                                extractedTimestamp = nil
                            }
                        }

                        checkIfWordExists()
                        // Oversettelse skjer IKKE lenger her (tidligere: 0.8s etter tastepause,
                        // uavhengig av fokus) — det var nettopp det som gjorde at ordet ble oversatt
                        // mens feltet fortsatt hadde fokus. Oversettelse skjer nå kun ved fokus-tap,
                        // se .onChange(of: focusedField) over.
                    }

                if let timestamp = extractedTimestamp {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                        Text("Timestamp: \(timestamp) → saved in notes")
                    }
                    .font(.caption)
                    .foregroundColor(.green)
                }

                if wordExists {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("This word already exists in the database")
                            .foregroundColor(.red)
                            .font(.caption)
                        Spacer()
                        Button {
                            appState.pendingSearchText = thaiWord.trimmingCharacters(in: .whitespacesAndNewlines)
                            dismiss()
                        } label: {
                            Label("Vis", systemImage: "magnifyingglass")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                    }
                }
            }
            // Notat-feltet er skjult her — brukes sjelden ved opprettelse, og kan legges inn
            // senere via detaljvisningen. `notes` fylles fortsatt ut i bakgrunnen ved YouTube-
            // tidsstempel-gjenkjenning og lagres som før.

            Section(header: languageSectionHeader("English") {
                speak(englishWord, language: MorsmaalLanguage.engelsk.locale, voiceId: MorsmaalLanguage.engelsk.voiceId)
            }) {
                TextField("English", text: $englishWord)
                    .font(Font.largeTitle.bold())
                    .focused($focusedField, equals: .english)
                    .disabled(isTranslating)
                    .textInputAutocapitalization(.never)
                if isTranslating {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Translating...")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                } else if englishWord.isEmpty {
                    Text("Empty, use Google Translate")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            Section(header: languageSectionHeader(morsmaalLanguage.label) {
                speak(morsmaal, language: morsmaalLanguage.locale, voiceId: morsmaalLanguage.voiceId)
            }) {
                TextField(morsmaalLanguage.label, text: $morsmaal)
                    .font(Font.largeTitle.bold())
                    .focused($focusedField, equals: .morsmaal)
                    .disabled(isTranslating)
                if isTranslating {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Translating...")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                } else if morsmaal.isEmpty {
                    Text("Empty, use Google Translate")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            // Type-velgeren (Word/Sentence) er skjult for nå — trolig et levning fra gThai.
            // Nyopprettede ord settes alltid til Word (se saveWordToCoreData).

            Section(header: Text("Microphone")) {
                Picker("Language", selection: $speechMode) {
                    ForEach(SpeechMode.allCases, id: \.self) { mode in
                        Text(mode.label(morsmaal: morsmaalLanguage)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: speechMode) { _, newMode in
                    speechManager.stop()
                    speechManager.transcript = ""
                    speechManager.setLocale(newMode.locale(morsmaal: morsmaalLanguage))
                }
                HStack {
                    Text(speechManager.transcript.isEmpty ? "Tap mic and speak..." : speechManager.transcript)
                        .font(.title3)
                        .foregroundStyle(speechManager.transcript.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        if case .recording = speechManager.status {
                            speechManager.handleFinalTranscript()
                        } else {
                            speechManager.transcript = ""
                            speechManager.start()
                        }
                    } label: {
                        Image(systemName: speechManager.status == .recording ? "mic.fill" : "mic")
                            .font(.title2)
                            .foregroundStyle(speechManager.status == .recording ? .red : .accentColor)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(speechManager.status == .recording ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                if batchEntries.isEmpty {
                    Button(action: lagreNyttOrd) {
                        HStack {
                            if isTranslating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .imageScale(.large)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .background(
                        thaiWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTranslating || wordExists
                            ? Color.accentColor.opacity(0.25) : Color.accentColor
                    )
                    .foregroundStyle(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(thaiWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTranslating || wordExists)
                } else {
                    Button(action: saveBatchEntries) {
                        HStack {
                            Image(systemName: "square.and.arrow.down.fill")
                                .imageScale(.large)
                            Text("Save all (\(batchEntries.count))")
                                .font(.title3.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .background(Color.green)
                    .foregroundStyle(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)

        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(linkedWord != nil ? "Add sentence for \"\(linkedWord?.thaiWord ?? "")\"" : "Add New Word")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showTranscriptImport = true
                    } label: {
                        Label("Import full transcript", systemImage: "text.append")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            // Ingen felt skal ha fokus ved åpning — tastaturet skal forbli nede.
            // Speech-to-text callback med modus-avhengig flyt
            speechManager.onTranscriptComplete = { (rawText: String) in
                // SFSpeechRecognizer skriver stor forbokstav på diktering, som på en tastatur-
                // diktering ("Test") — ønskelig i en melding, men ikke i en ordbok for enkeltord,
                // der oversatte felt uansett kommer tilbake med liten forbokstav. Gjør rådikteringen
                // konsistent med det ved å gjøre kun første bokstav liten.
                let text = Self.lowercasedFirstLetter(rawText)
                let currentMode = SpeechMode(rawValue: UserDefaults.standard.string(forKey: "speechInputMode") ?? "english") ?? .english
                switch currentMode {
                case .english:
                    englishWord = text
                    translateMissingFields(sourceText: text, sourceLanguageCode: "en")

                case .norsk:
                    morsmaal = text
                    lookupThaiAndEnglishFromMorsmaal(sourceText: text, saveAfterLookup: false)

                case .thai:
                    thaiWord = text
                    // Mikrofonen har ingen "fokus-tap" å vente på (i motsetning til tasting) —
                    // oversett med en gang dikteringen er ferdig, samme som når feltet forlates.
                    translateMissingFields(sourceText: text, sourceLanguageCode: "no")
                }
            }
            speechManager.setLocale(speechMode.locale(morsmaal: morsmaalLanguage))
            speechManager.requestAuth()

            // Check if initial word exists
            if !thaiWord.isEmpty {
                checkIfWordExists()
                // Focus on English field if Thai word is prefilled
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    focusedField = .english
                }
            }
        }
        .onDisappear {
            speechManager.stop()
            Notifier.shared.hide()
        }
    }
}

#Preview {
    // In-memory Core Data for preview
    let previewController = PersistenceController.preview
    let context = previewController.container.viewContext

    // AppState med noen eksempelverdier
    let state = AppState()
    state.valgtGruppeNavn = "Demo group"
    state.sqlGruppeId = 1
    state.valgtGruppeId = 1

    return NavigationStack {
        CreateWordView()
            .environment(state)
            .environment(\.managedObjectContext, context)
    }
}
