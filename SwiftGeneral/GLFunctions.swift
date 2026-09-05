//
//  GLFunctions.swift
//  gThai
//
//  Created by Mac on 11/01/2021.
//
import UIKit
import MapKit
import AVFoundation
import os
import UserNotifications
import CoreData

import CoreData

let g = GlFunctions()

extension GlFunctions {
    /// Slett ett ThaiWords-objekt. Prøver i rekkefølge: objectID, uuid, thaiWord.
    /// Returnerer `true` hvis noe ble slettet.
    func deleteThaiWord(
        in context: NSManagedObjectContext,
        objectID: NSManagedObjectID? = nil,
        uuid: UUID? = nil,
        thaiWord: String? = nil
    ) throws -> Bool {

        // 1) via objectID
        if let oid = objectID,
           let obj = try? context.existingObject(with: oid) as? ThaiWords {
            context.delete(obj)
            try context.save()
            return true
        }

        // 2) via UUID-feltet "id"
        if let uuid {
            let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
            req.predicate   = NSPredicate(format: "id == %@", uuid as CVarArg)
            req.fetchLimit  = 1
            if let obj = try context.fetch(req).first {
                context.delete(obj)
                try context.save()
                return true
            }
        }

        // 3) via thaiWord
        if let key = thaiWord?.trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
            req.predicate  = NSPredicate(format: "thaiWord ==[c] %@", key)
            req.fetchLimit = 1
            if let obj = try context.fetch(req).first {
                context.delete(obj)
                try context.save()
                return true
            }
        }

        return false
    }
}


final class GlFunctions
{
    
    var jsonWordsDict: [String: ThaiWordJSON] = [:]
    static let shared = GlFunctions()
    public var talk = AVSpeechSynthesizer()
    
    // Holder JSON-ord som dictionary for rask lookup
    
    
    private(set) var jsonList: [ThaiWordJSON] = []
    private(set) var jsonWords: Set<String> = []
    
    
    // JSON-modell
    struct JsonWord: Codable {
        let word: String
        let ipa: String
        let english: String
        let rank: Int
        let frequency: Double
        let dpRank: Double
        let example: String
    }

    // Hjelpere
    @inline(__always)
    func isRankTag(_ token: Substring) -> Bool {
        token.count == 5 && token.first == "#" && token.dropFirst().allSatisfy(\.isNumber)
    }

    @inline(__always)
    func isIpaTag(_ token: Substring) -> Bool {
        token.hasPrefix("#ipa=")
    }

    @inline(__always)
    func isNoJson(_ token: Substring) -> Bool {
        token == "*NoJson"
    }

    func dedupePreservingOrder(_ tokens: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        out.reserveCapacity(tokens.count)
        for t in tokens where !t.isEmpty {
            if !seen.contains(t) {
                seen.insert(t)
                out.append(t)
            }
        }
        return out
    }

    func stripRankIpaNoJson(from sentence: String) -> [String] {
        sentence
            .split(whereSeparator: { $0.isWhitespace })
            .filter { tok in
                !isRankTag(tok) && !isIpaTag(tok) && !isNoJson(tok)
            }
            .map(String.init)
    }

    // Ikke i JSON → *NoJson først, dedupe alle tagger
    func normalizeWhenMissingJSON(sentence: String) -> String {
        var rest = stripRankIpaNoJson(from: sentence)          // fjerner gamle #dddd/#ipa=/*NoJson
        rest = dedupePreservingOrder(rest)                     // dedupe øvrige tagger/ord
        return rest.isEmpty ? "*NoJson" : "*NoJson " + rest.joined(separator: " ")
    }

    // I JSON → fjern *NoJson + gamle #dddd/#ipa=, prefiks med ny #rank og #ipa=
    func normalizeWhenInJSON(sentence: String, rank: Int, ipa: String) -> String {
        let rankTag = String(format: "#%04d", rank)
        let ipaTag  = "#ipa=\(ipa)"
        var rest = stripRankIpaNoJson(from: sentence)          // fjerner gamle #dddd/#ipa=/*NoJson
        rest = dedupePreservingOrder(rest)
        // legg til 3 mellomrom etter rankTag og linjeskift etter ipaTag
        let prefix = "\(rankTag)   \(ipaTag)\n"
        
        return rest.isEmpty ? prefix.trimmingCharacters(in: .whitespacesAndNewlines)
                            : prefix + rest.joined(separator: " ")
    }
    
    func pinpointJSONFeil() {
        guard let url = Bundle.main.url(forResource: "thai_top_4000", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let arr  = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            print("Fant ikke/kunne ikke lese JSON som array")
            return
        }

        let dec = JSONDecoder()
        for (idx, el) in arr.enumerated() {
            do {
                let d = try JSONSerialization.data(withJSONObject: el)
                _ = try dec.decode(ThaiWordJSON.self, from: d)
            } catch {
                print("❌ Feil i post nr. \(idx + 1): \(error)")
                if let d = try? JSONSerialization.data(withJSONObject: el),
                   let snippet = String(data: d, encoding: .utf8) {
                    print("Rad som feiler:\n\(snippet)")
                }
                return
            }
        }
        print("✅ Alle \(arr.count) poster ser fine ut.")
    }
   
    
    
    /// Merk alle ThaiWords som ikke finnes i JSON:
     ///  - alltid legg til " *NoJson"
     ///  - hvis thaiWord.count > 15 OG ikke i JSON -> legg også til " *delete"
     func sjekkOrdMotJSON_ogMerkNoJson() {
         // 1) Les + rens JSON
         guard let url = Bundle.main.url(forResource: "thai_top_4000", withExtension: "json"),
               let raw = try? String(contentsOf: url, encoding: .utf8) else {
             print("❌ Fant ikke thai_top_4000.json")
             return
             // nå er json lest inn i strengen raw
             
         }
         let cleaned = cleanedJSONString(raw)
         guard let data = cleaned.data(using: .utf8) else {
             print("❌ Klarte ikke å konvertere renset JSON til Data.")
             return
         }
         // nå er strengen renset for karakterer som ikke bør være i strengen PARAGRAPH SEPARATOR etc
         
        
         
         let jsonList: [ThaiWordJSON] // tom variabelsom skal fylles ume ThaiWordJSON objekter
         do {
             jsonList = try JSONDecoder().decode([ThaiWordJSON].self, from: data)
         } catch {
             print("❌ Kunne ikke parse JSON etter rensing: \(error)")
             return
         }
         
         let jsonDict = Dictionary(uniqueKeysWithValues: jsonList.map { ($0.word, $0) })
        // let jsonWords = Set(jsonList.map { $0.word })
         
         
         print("✅ JSON innlest: \(jsonList.count) ord.")

         // 2) Hent alle rader fra Core Data og merk
         let context = PersistenceController.shared.container.viewContext

         let req = NSFetchRequest<NSManagedObject>(entityName: "ThaiWords")
         req.returnsObjectsAsFaults = false

         context.perform {
             do {
                 let rows = try context.fetch(req)
                 var missing = 0
                 var updated = 0

                 let jsonDict = Dictionary(uniqueKeysWithValues: jsonList.map { ($0.word, $0) })

                 for obj in rows {
                     let thai = (obj.value(forKey: "thaiWord") as? String) ?? ""
                     guard !thai.isEmpty else { continue }

                     let current = (obj.value(forKey: "sentence") as? String) ?? ""
                     let newSentence: String

                     if let jsonEntry = jsonDict[thai] {
                         // Har JSON → legg på #rank + #ipa=, ingen *NoJson
                         newSentence = self.normalizeWhenInJSON(sentence: current, rank: jsonEntry.rank, ipa: jsonEntry.ipa)
                     } else {
                         // Mangler i JSON → *NoJson først
                         newSentence = self.normalizeWhenMissingJSON(sentence: current)
                     }

                     if newSentence != current {
                         obj.setValue(newSentence, forKey: "sentence")
                         updated += 1
                     }
                 }

                 if context.hasChanges { try context.save() }
                 print("🔎 Sjekket \(rows.count) rader. Mangler i JSON: \(missing). Oppdatert: \(updated).")
             } catch {
                 print("❌ Feil ved Core Data-søk/lagring: \(error)")
             }
         }
     }
    
   
        /// Teller hvor mange ord som vil bli flyttet/påvirket av moveWordsByRank
        /// Returnerer (totaltAntall, antallSomVilFlyttes, gruppeStatistikk)
        func countWordsForRankMove(fromRank: Int,
                                   toRank: Int,
                                   targetGroupId: Int16,
                                   context: NSManagedObjectContext) -> (total: Int, willMove: Int, byGroup: [Int16: Int]) {
            guard fromRank > 0, toRank > 0, fromRank <= toRank else {
                return (0, 0, [:])
            }

            let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
            // Only consider items that are NOT *NoJson and have a frequencyRank in range
            req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
              
                NSPredicate(format: "frequencyRank >= %d AND frequencyRank <= %d", fromRank, toRank)
            ])

            var total = 0
            var willMove = 0
            var byGroup: [Int16: Int] = [:]

            context.performAndWait {
                do {
                    let rows = try context.fetch(req)
                    print("🔢 countWordsForRankMove fetched \(rows.count) rows in [\(fromRank)–\(toRank)]")
                    for sample in rows.prefix(10) {
                        print("   • count-sample: thai='\(sample.thaiWord ?? "")' freq=\(sample.frequencyRank) group=\(sample.groupId)")
                    }
                    for obj in rows {
                        total += 1
                        if obj.groupId != targetGroupId {
                            willMove += 1
                            byGroup[obj.groupId, default: 0] += 1
                        }
                    }
                } catch {
                    print("❌ countWordsForRankMove error:", error.localizedDescription)
                }
            }
            return (total, willMove, byGroup)
        }

        /// Flytt ord hvis og bare hvis sentence starter med nøyaktig #NNNN (4 siffer).
        /// Setninger som inneholder "*NoJson" blir alltid hoppet over.
        @discardableResult
        func moveWordsByRank(fromRank: Int,
                             toRank: Int,
                             targetGroupId: Int16,
                             context: NSManagedObjectContext) -> Int
        {
            precondition(fromRank > 0 && toRank > 0 && fromRank <= toRank)

            let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
            req.predicate = NSPredicate(format: "frequencyRank >= %d AND frequencyRank <= %d", fromRank, toRank)
            req.includesPropertyValues = true
            req.fetchBatchSize = 300

            var updated = 0

            print("🚚 moveWordsByRank START fromRank=\(fromRank) toRank=\(toRank) → targetGroupId=\(targetGroupId)")

            context.performAndWait {
                do {
                    let rows = try context.fetch(req)
                    print("🔎 Fetch result count in range [\(fromRank)–\(toRank)]: \(rows.count)")
                    if rows.isEmpty {
                        print("⚠️ No rows matched frequencyRank range. Consider backfilling frequencyRank.")
                    }

                    // Log a small sample for diagnostics
                    for sample in rows.prefix(10) {
                        print("   • match: thai='\(sample.thaiWord ?? "")' freq=\(sample.frequencyRank) currentGroup=\(sample.groupId)")
                    }

                    for obj in rows {
                        let currentGroup = obj.groupId
                        let freq = obj.frequencyRank
                        if currentGroup == targetGroupId {
                            // Already in the right group
                            // print("   ↪︎ skip: thai='\(obj.thaiWord ?? "")' freq=\(freq) already in group \(currentGroup)")
                            continue
                        }

                        obj.groupId = targetGroupId
                        updated += 1
                        print("   ✅ move: thai='\(obj.thaiWord ?? "")' freq=\(freq) \(currentGroup) → \(targetGroupId)")
                    }

                    if context.hasChanges {
                        do {
                            try context.save()
                            print("💾 Saved context. Moved=\(updated)")
                        } catch {
                            print("❌ Save failed after moving: \(error.localizedDescription)")
                        }
                    } else {
                        print("ℹ️ No changes to save. Moved=\(updated)")
                    }
                } catch {
                    print("❌ moveWordsByRank fetch error:", error.localizedDescription)
                }
            }
            return updated
        }
    
    /// Backfill `frequencyRank` from existing `sentence` tags.
    /// Parses a leading token like `#0123` and writes 123 to `frequencyRank`.
    /// Skips rows that contain `*NoJson`.
    func backfillFrequencyRankFromSentence(context: NSManagedObjectContext) {
        let req: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        req.includesPropertyValues = true
        req.returnsObjectsAsFaults = false

        context.perform {
            do {
                let rows = try context.fetch(req)
                var updated = 0
                var examined = 0

                for obj in rows {
                    examined += 1
                    guard var s = obj.sentence, !s.isEmpty else { continue }
                    if s.contains("*NoJson") { continue }

                    s = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let first = s.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first else { continue }
                    // Expect exactly #NNNN
                    if first.count == 5, first.first == "#" {
                        let digits = first.dropFirst()
                        if digits.allSatisfy({ $0.isNumber }), let rank = Int(digits) {
                            if obj.frequencyRank != Int32(rank) {
                                obj.frequencyRank = Int32(rank)
                                updated += 1
                            }
                        }
                    }
                }

                if context.hasChanges {
                    do { try context.save() } catch { print("❌ Save after backfill failed:", error.localizedDescription) }
                }
                print("🧭 Backfill frequencyRank: examined=\(examined), updated=\(updated)")
            } catch {
                print("❌ Backfill fetch failed:", error.localizedDescription)
            }
        }
    }
    
    
    
    
   

        // 1) Les + rens + normaliser + lagre renset JSON til Documents
        @discardableResult
        func rensOgLagreThaiJSON() -> URL? {
            // Les rå tekst fra bundle
            guard let url = Bundle.main.url(forResource: "thai_top_4000", withExtension: "json"),
                  let raw = try? String(contentsOf: url, encoding: .utf8)
            else {
                print("❌ Fant ikke thai_top_4000.json i bundle.")
                return nil
            }

            // Rens
            let cleaned = cleanedJSONString(raw)
            guard let data = cleaned.data(using: .utf8) else {
                print("❌ Kunne ikke konvertere renset JSON til Data.")
                return nil
            }

            // Decode
            let decoded: [ThaiWordJSON]
            do {
                decoded = try JSONDecoder().decode([ThaiWordJSON].self, from: data)
            } catch {
                print("❌ Parse-feil etter rensing: \(error)")
                return nil
            }

            // Normaliser felt (trim og NFC)
            func normalize(_ s: String) -> String {
                s.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
            }

            var uniqueByWord: [String: ThaiWordJSON] = [:]
            for item in decoded {
                let normWord = normalize(item.word)
                let normItem = ThaiWordJSON(
                    word: normWord,
                    ipa: normalize(item.ipa),
                    english: normalize(item.english),
                    rank: item.rank,
                    frequency: item.frequency,
                    dpRank: item.dpRank,
                    example: normalize(item.example)
                )

                // Behold første med lavest rank om duplikater
                if let existing = uniqueByWord[normWord] {
                    if normItem.rank < existing.rank {
                        uniqueByWord[normWord] = normItem
                    }
                } else {
                    uniqueByWord[normWord] = normItem
                }
            }

            // Sortér (valgfritt): etter rank
            let cleanedArray = uniqueByWord.values.sorted(by: { $0.rank < $1.rank })

            // Re-encode, pretty print
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let outData = try? encoder.encode(cleanedArray) else {
                print("❌ Kunne ikke serialisere renset JSON.")
                return nil
            }

            // Skriv til Documents
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let outURL = docs.appendingPathComponent("thai_top_4000.cleaned.json")
            do {
                try outData.write(to: outURL, options: .atomic)
                print("✅ Renset/normalisert JSON skrevet til: \(outURL.path)")
                print("   Inndata: \(decoded.count)  →  Unike/normaliserte: \(cleanedArray.count)")
                return outURL
            } catch {
                print("❌ Klarte ikke å skrive cleaned JSON: \(error)")
                return nil
            }
        }

        // 2) Hent ordsett fra renset JSON (bruker cleaned-fil om den fins, ellers renser den først)
        func loadCleanThaiJSONWords() -> Set<String> {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let outURL = docs.appendingPathComponent("thai_top_4000.cleaned.json")

            let data: Data
            if FileManager.default.fileExists(atPath: outURL.path) {
                // Les fra eksisterende cleaned-fil
                guard let d = try? Data(contentsOf: outURL) else {
                    print("⚠️ Kunne ikke lese cleaned-fil, renser på nytt …")
                    _ = rensOgLagreThaiJSON()
                    return loadCleanThaiJSONWords()
                }
                data = d
            } else {
                // Ingen cleaned-fil: lag den
                _ = rensOgLagreThaiJSON()
                return loadCleanThaiJSONWords()
            }

            do {
                let arr = try JSONDecoder().decode([ThaiWordJSON].self, from: data)
                return Set(arr.map { $0.word })
            } catch {
                print("❌ Kunne ikke parse cleaned-fil: \(error)")
                return []
            }
        }
    
    
    
    
    
    // MARK: - Modell (samme som du allerede bruker)
    struct ThaiWordJSON: Codable, Identifiable {
        var id: String { word }
        let word: String
        let ipa: String
        let english: String
        let rank: Int
        let frequency: Double
        let dpRank: Double
        let example: String
    }
    
    
   

        // ⬇️ cache for ordene fra JSON
      

        /// Slå opp engelsk betydning for et thai-ord
        func finnJSONEnglish(for thaiWord: String) -> String? {
            return jsonList.first(where: { $0.word == thaiWord })?.english
        }

 
    

    // MARK: - Rensing av rå JSON-tekst
    fileprivate func cleanedJSONString(_ raw: String) -> String {
        var s = raw
        // Normaliser linjeskift
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
             .replacingOccurrences(of: "\r",    with: "\n")

        // Fjern BOM/Zero Width/LINE/Paragraph separators
        let badScalars: [UnicodeScalar] = [
            UnicodeScalar(0xFEFF)!, // BOM
            UnicodeScalar(0x2028)!, // LINE SEPARATOR
            UnicodeScalar(0x2029)!, // PARAGRAPH SEPARATOR
            UnicodeScalar(0x200B)!  // ZERO WIDTH SPACE
        ]
        s.unicodeScalars.removeAll { badScalars.contains($0) }

        // Fjern kontrollertegn \u0000 – \u001F (behold \n og \t)
        let controlChars = CharacterSet(charactersIn: "\u{0000}"..."\u{001F}").subtracting(.newlines).subtracting(.controlCharacters.subtracting(.whitespacesAndNewlines))
        s.unicodeScalars.removeAll { controlChars.contains($0) && $0 != "\n" && $0 != "\t" }

        // Trim overflødige blanklinjer
        while s.hasSuffix("\n\n\n") { s.removeLast() }
        return s
    }

    /// Sjekker alle Core Data-ord mot thai_top_4000.json i bundle og logger de som mangler.
    func sjekkOrdMotJSON() {
        // 1) Les JSON fra bundle (som String, slik at vi kan rense)
        guard let url = Bundle.main.url(forResource: "thai_top_4000", withExtension: "json"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            print("❌ Fant ikke thai_top_4000.json i bundle, eller kunne ikke lese den som UTF‑8.")
            return
        }

        // 2) Rens og dekod
        let cleaned = cleanedJSONString(raw)
        guard let data = cleaned.data(using: .utf8) else {
            print("❌ Klarte ikke å konvertere renset JSON til Data.")
            return
        }

        let jsonList: [ThaiWordJSON]
        do {
            jsonList = try JSONDecoder().decode([ThaiWordJSON].self, from: data)
        } catch {
            print("❌ Kunne ikke parse JSON etter rensing: \(error)")
            return
        }

        let jsonWords = Set(jsonList.map { $0.word })
        print("✅ JSON innlest: \(jsonList.count) ord (etter rensing).")

        // 3) Hent alle ThaiWords fra Core Data
        let context = PersistenceController.shared.container.viewContext

        let req = NSFetchRequest<NSManagedObject>(entityName: "ThaiWords")
        req.returnsObjectsAsFaults = false

        do {
            let rows = try context.fetch(req)
            var missing: [String] = []

            for obj in rows {
                let thaiWord = self.safeTextValue(data: obj, forKey: "thaiWord", defaultValue: "")
                if !thaiWord.isEmpty, !jsonWords.contains(thaiWord) {
                    missing.append(thaiWord)
                }
            }

            print("🔎 Sjekket \(rows.count) rader mot JSON. Mangler i JSON: \(missing.count).")
            if !missing.isEmpty {
                // Print første 50 for ikke å spamme loggen
                let preview = missing.prefix(50).joined(separator: ", ")
                print("❌ Eksempler (første \(min(50, missing.count))): \(preview)")
            }
        } catch {
            print("❌ Feil ved Core Data-søk: \(error)")
        }
    }
    
    
    
    func isThai(text: String) -> Bool {
        // Unicode range for Thai: U+0E00–U+0E7F
        for scalar in text.unicodeScalars {
            if scalar.value >= 0x0E00 && scalar.value <= 0x0E7F {
                return true
            }
        }
        return false
    }
    @objc func talkTh(talkText: String, rate: Float, language: String) {
        let utter = AVSpeechUtterance(string: talkText)
        utter.rate = rate
        // `language` ble tidligere ignorert her — funksjonen spilte alltid av med norsk
        // Nora-stemme uansett hva kallerne ba om (bl.a. "th-TH" fra HybridSegmentationView).
        if language.hasPrefix("nb") || language.hasPrefix("no") {
            var identifierVoice = "com.apple.voice.enhanced.nb-NO.Nora"
#if targetEnvironment(macCatalyst)
            identifierVoice = "com.apple.voice.compact.nb-NO.Nora"
#endif
            utter.voice = AVSpeechSynthesisVoice(identifier: identifierVoice) ?? AVSpeechSynthesisVoice(language: "nb-NO")
        } else {
            utter.voice = AVSpeechSynthesisVoice(language: language)
        }
        let storedRate = UserDefaults.standard.double(forKey: "speechRateThai")
        utter.rate = storedRate > 0 ? Float(storedRate) : 0.5
        utter.volume = 0.8    // litt lavere volum
        print("1 Tekst som snakkes er: \(talkText) LANGUAGE: \(language)")
        print("2 Brukt stemme: \(utter.voice?.identifier ?? "ingen")")
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            // try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            // try AVAudioSession.sharedInstance().setCategory(.playback, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioSession-feil: \(error)")
        }
        if talk.isSpeaking {
            talk.stopSpeaking(at: .immediate)
        }
        talk.speak(utter)
    }
    
    func exportAllImagesToFolder(forGroup groupId: Int16? = nil) {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        
        if let id = groupId {
                request.predicate = NSPredicate(format: "groupId == %d", id)  // MERK: "==" og %d
            }

        do {
            let words = try context.fetch(request)
            let fileManager = FileManager.default

            // Lag mappe for bilder i temp-katalogen
            let imagesFolder = fileManager.temporaryDirectory.appendingPathComponent("ThaiImages")
            try? fileManager.createDirectory(at: imagesFolder, withIntermediateDirectories: true)

            print("📂 Lagrer bilder til: \(imagesFolder.path)")

            for word in words {
                guard let data = word.image,
                      let name = word.thaiWord,
                      !name.isEmpty else {
                    print("⚠️ Mangler bilde eller navn – hopper over én post")
                    continue
                }

                // Trygg filnavn (fjern / og mellomrom)
                var safeName = name
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: " ", with: "_")

                // Trunker hvis for langt (maks 50 tegn)
                if safeName.count > 50 {
                    print("⚠️ Skipper '\(name)' – filnavn er for langt")
                    continue
                }

                let fileURL = imagesFolder.appendingPathComponent("\(safeName).jpg")

                do {
                    try data.write(to: fileURL)
                    print("✅ Lagret: \(safeName).jpg")
                } catch {
                    print("❌ Feil ved lagring av '\(safeName).jpg': \(error)")
                }
            }
            print("🏁 Ferdig med bilde-eksport!")

        } catch {
            print("❌ Feil ved henting fra Core Data: \(error)")
        }
    }
    
    func exportAllWords() {
        let context = PersistenceController.shared.container.viewContext

        let request = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        
        do {
            let words = try context.fetch(request)
            let export: [[String: Any]] = words.map { word in
                var item: [String: Any] = [:]
                item["thai"] = word.thaiWord ?? ""
                item["english"] = word.englishWord ?? ""
                item["sentence"] = word.sentence ?? ""
                item["groupId"] = word.groupId
                item["id"] = word.id?.uuidString ?? ""
                item["insertDate"] = word.insertDate?.description ?? ""
                item["dateOne"] = word.dateOne?.description ?? ""
                item["dateTwo"] = word.dateTwo?.description ?? ""
                item["star"] = word.star
                return item
            }

            let jsonData = try JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted])
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("thaiWordsBackup.json")
            try jsonData.write(to: url)
            print("✅ Backup lagret til: \(url.path)")

        } catch {
            print("❌ Feil ved eksport: \(error)")
        }
    }
    
    
    func replaceSpesialCharacterInString(txt: String) -> String {
        var t1 = txt
        var t2 = txt
        var t3 = txt
        if langForeign == "th" {
            t1 = txt.replacingOccurrences(of: " " , with: "")
            t2 = t1.replacingOccurrences(of: "\n" , with: "")
            t3 = t2.replacingOccurrences(of: "\"" , with: "")
        }
        // sentenceThai.text = t3
        return t3
    }
    func baseGroupId(group: Int16) -> Int16{
        var groupMain = group
        if groupMain % 3 == 0 {
            print("Group main was ok")
        } else {
            if groupMain % 3 == 1 {
                groupMain = groupMain - 1
                print("Group main was -1")
            } else {
                if groupMain % 3 == 2 {
                    groupMain = groupMain - 2
                    // print("Group main was -2")
                }
            }
        }
        return groupMain
    }
    // COREDATA
    func findWordCoreDataMotherThong(thaiWord: String, language: String) -> [ThaiWords] {
        // language er ikke brukt her – behold i signaturen hvis du trenger den senere
        let context = PersistenceController.shared.container.viewContext

        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(format: "englishWord == %@", thaiWord)
        request.fetchLimit = 1

        do {
            return try context.fetch(request)   // Ferdige NSManagedObject-instanser
        } catch {
            print("❌ findWordCoreDataMotherThong feil: \(error.localizedDescription)")
            return []
        }
    }
    func selectWordRequest(thaiWord: String, number: Int) -> NSFetchRequest<NSFetchRequestResult>  {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        let search = thaiWord
        let selectString = "groupId = %@"
        request.predicate = NSPredicate(format: selectString, search)
        request.fetchLimit = number
        return request
    }
    func selectStarRequest(thaiWord: String, number: Int) -> NSFetchRequest<NSFetchRequestResult>  {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        let search = "thaiWord"
        let selectString = "star = true"
        request.predicate = NSPredicate(format: selectString, search)
        request.fetchLimit = number
        return request
    }
    
    func selectStatementAllGroup(group: String, number: Int, sort: String, ascending: Bool) -> NSFetchRequest<NSFetchRequestResult>  {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Group")
        let sortDescriptor1 = NSSortDescriptor(key: sort, ascending: ascending)
        let sortDescriptors = [sortDescriptor1]
        request.sortDescriptors = sortDescriptors
        request.fetchLimit = number
        return request
    }
    func selectStatementGroup(group: String, number: Int, sort: String, ascending: Bool, startWith: String) -> NSFetchRequest<NSFetchRequestResult>  {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Group")
        if startWith != "%" {
            let beginPredicate = NSPredicate(format: "groupName BEGINSWITH %@", startWith)
            request.predicate = beginPredicate
        } else {
            //groupName BEGINSWITH 'A' AND
            let dollar = "$"
            let alfa = "@"
            let number = "#"
            // let d$ = "$"
            let beginPredicate = NSPredicate(format: "!groupName BEGINSWITH %@ AND !groupName BEGINSWITH %@ AND !groupName BEGINSWITH %@ ", dollar, alfa, number)
            request.predicate = beginPredicate
        }
        let sortDescriptor1 = NSSortDescriptor(key: sort, ascending: ascending)
        let sortDescriptors = [sortDescriptor1]
        request.sortDescriptors = sortDescriptors
        request.fetchLimit = number
        return request
    }
    func getCurrentGroupID() -> Int16   {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "CurrentGroup")
        request.returnsObjectsAsFaults = false
        request.fetchLimit = 1
        do {
            let result = try context.fetch(request)
            if let data = (result as! [NSManagedObject]).first {
                let groupInt = Int16(safeInt16Value(data: data, forKey: "groupId", defaultValue: 0))
                if showPrint { print("📍 getCurrentGroupID: \(groupInt)") }
                return groupInt
            }
        } catch {
            print("getCurrentGroupID failed: \(error)")
        }
        return 0
    }
    func getCurrentGroupName(groupId: Int16) -> String  {
        let search = String(groupId)
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Group")
        request.predicate = NSPredicate(format: "groupId = %@", search)
        request.returnsObjectsAsFaults = false
        var group = "Ikke satt"
        do {
            let result = try context.fetch(request)
            var i = 0
            for data in result as! [NSManagedObject] {
                i = i + 1
                group = String(safeTextValue(data: data, forKey: "groupName", defaultValue: "tja?"))
                // print("group loaded \(group)")
            }
        } catch {
            // print("Failed")
        }
        // return request
        return group
    }
    func fetchWordSort(group: String, sort1: String, ascending1: Bool, sort2: String, ascending2: Bool) -> NSFetchRequest<NSFetchRequestResult> {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        let selectString = "groupId = %@"
        request.predicate = NSPredicate(format: selectString, group)
        let sortDescriptor1 = NSSortDescriptor(key: sort1, ascending: ascending1)
        let sortDescriptor2 = NSSortDescriptor(key: sort2, ascending: ascending2)
        request.sortDescriptors = [sortDescriptor1, sortDescriptor2]
        return request
    }
    func fetchStatementWord(group: String, number: Int) -> NSFetchRequest<NSFetchRequestResult>  {
        let word = group
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        var selectString = "groupId = %@"
        if word == "*" {
            request.predicate = nil
            let sortDescriptor0 = NSSortDescriptor(key: "star", ascending: false)
            let sortDescriptor2 = NSSortDescriptor(key: "insertDate", ascending: false)
            let sortDescriptors = [sortDescriptor0, sortDescriptor2]
            request.sortDescriptors = sortDescriptors
            request.fetchLimit = number
        } else {
            if word == "⭐️" {
                selectString = "star = %@"
                request.predicate = NSPredicate(format: selectString, NSNumber(value: true))
                let sortDescriptor0 = NSSortDescriptor(key: "star", ascending: false)
                let sortDescriptor2 = NSSortDescriptor(key: "insertDate", ascending: false)
                let sortDescriptors = [sortDescriptor0, sortDescriptor2]
                request.sortDescriptors = sortDescriptors
                request.fetchLimit = number
            } else {
                request.predicate = NSPredicate(format: selectString, group)
                let sortDescriptor0 = NSSortDescriptor(key: "star", ascending: false)
                let sortDescriptor2 = NSSortDescriptor(key: "insertDate", ascending: false)
                let sortDescriptors = [sortDescriptor0, sortDescriptor2]
                request.sortDescriptors = sortDescriptors
                request.fetchLimit = number
            }
        }
        // print(selectString, group)
        return request
    }
    func selectStatementWordLastUpdated(group: String, number: Int) -> NSFetchRequest<NSFetchRequestResult>  {
        let word = group
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        var selectString = "groupId = %@"
        if word == "*" {
            request.predicate = nil
            let sortDescriptor1 = NSSortDescriptor(key: "insertDate", ascending: false)
            let sortDescriptors = [sortDescriptor1]
            request.sortDescriptors = sortDescriptors
            request.fetchLimit = number
        } else {
            if word == "⭐️" {
                selectString = "star = %@"
                request.predicate = NSPredicate(format: selectString, NSNumber(value: true))
                let sortDescriptor1 = NSSortDescriptor(key: "dateTwo", ascending: true)
                let sortDescriptors = [sortDescriptor1]
                request.sortDescriptors = sortDescriptors
                request.fetchLimit = number
            } else {
                request.predicate = NSPredicate(format: selectString, word)
                let sortDescriptor1 = NSSortDescriptor(key: "dateTwo", ascending: false)
                let sortDescriptors = [sortDescriptor1]
                request.sortDescriptors = sortDescriptors
                request.fetchLimit = number
            }
        }
        return request
    }
    func getNumberOfWords(id :String) -> Int {
        let search = id
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        request.predicate = NSPredicate(format: "id = %@", search)
        request.returnsObjectsAsFaults = false
        var number = 0
        do {
            let result = try context.fetch(request)
            number = result.count
        }
        catch {
            // print("Failed")
            return number
        }
        return number
    }
    
    func getWordCoreData(thaiWord: String) -> [ThaiWords] {
        let context = PersistenceController.shared.container.viewContext

        
        print("🔍 Ny print for heng!!!)")
        print("🔍 context = \(context)")
        print("🔍 coordinator nil? \(context.persistentStoreCoordinator == nil)")
        print("🔍 store count = \(context.persistentStoreCoordinator?.persistentStores.count ?? -1)")
        print("🔍 entities = \(context.persistentStoreCoordinator?.managedObjectModel.entities.map(\.name) ?? [])")

        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(format: "thaiWord == %@", thaiWord)
        request.fetchLimit = 1

        do {
            return try context.fetch(request)
        } catch {
            print("❌ getWordCoreData feil: \(error.localizedDescription)")
            return []
        }
    }
    
    func getNorwegian(thaiWord: String) -> String {
            let context = PersistenceController.shared.container.viewContext

            // Fetch a ThaiWords object and return its english/norwegian text
            let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
            request.predicate = NSPredicate(format: "thaiWord == %@", thaiWord)
            request.fetchLimit = 1

            do {
                if let word = try context.fetch(request).first {
                    return word.translation1 ?? ""
                }
            } catch {
                print("❌ getNorwegian fetch error: \(error.localizedDescription)")
            }
            return ""
        }
    
    
 //   func getWordCoreDataId(_ id: UUID) -> ThaiWords? {
 //       let context = PersistenceController.shared.container.viewContext
 //       let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
 //       request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
 //       request.fetchLimit = 1
//
 //       do {
 //           return try context.fetch(request).first
 //       } catch {
 //           print("❌ getWordCoreDataId feil:", error.localizedDescription)
 //           return nil
 //       }
 //   }
    
    
//    func getWordCoreData(thaiWord: String) -> [ThaiWords] {
//        let context = PersistenceController.shared.container.viewContext
//
//        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
//        request.predicate = NSPredicate(format: "thaiWord == %@", thaiWord)
//        request.fetchLimit = 99999
//
//        do {
//            return try context.fetch(request)
//        } catch {
//            print("❌ getWordCoreData feil: \(error.localizedDescription)")
//            return []
//        }
//    }
    
    func getLanguageForGroup(groupId: Int16) -> String {
        var language = "xx"
        let search = String(groupId)
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Group")
        let selectString = "groupId == %@"
        let predicate = NSPredicate(format: selectString, search)
        request.predicate = predicate
        request.fetchLimit = 1
        do {
            let result = try context.fetch(request)
            var i = 0
            for data in result as! [NSManagedObject] {
                i = i + 1
                language = safeTextValue(data: data, forKey: "language", defaultValue: "xx")
            }
        } catch {
            // print("Failed")
        }
        return language
    }
    func createNewGroupId() -> Int16  {
        var groupInt = getMaxGroupId()
        groupInt = groupInt + 1
        //let group = Int16(groupIdTF.text!)
        let tekst = "group name"
        let typex = Int16(-1) // vanlig aktiv gruppe
        // always insert 3 groups
        insertGroupIntoCoreData(groupId: groupInt, groupName: tekst, groupType: typex)
        let group2 = groupInt + 1
        g.insertGroupIntoCoreData(groupId: group2, groupName: "$" + String(group2), groupType: typex)
        let group3 = groupInt + 2
        insertGroupIntoCoreData(groupId: group3, groupName:  "$" + String(group3), groupType: typex)
        
        return groupInt
    }
    func getMaxGroupId() -> Int16 {
        //let search = id.description
        var maxInt :Int16 = 0
        let context = PersistenceController.shared.container.viewContext
        //let context = (UIApplication.sharedApplication().delegate as! AppDelegate).managedObjectContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Group")
        fetchRequest.fetchLimit = 1
        let sortDescriptor = NSSortDescriptor(key: "groupId", ascending: false)
        fetchRequest.sortDescriptors = [sortDescriptor]
        do {
            let maxTest = try context.fetch(fetchRequest) as! [Group]
            let max = maxTest.first
            if max == nil {
                // xprint ("Init av database")
            }
            else {
                maxInt = (max?.value(forKey: "groupId") as! Int16)
            }
        } catch _ {
        }
        return maxInt
    }
    func getCountWords(request: NSFetchRequest<NSFetchRequestResult>) -> Int {
        var antall = 0
        let context = PersistenceController.shared.container.viewContext
        do {
            let result = try context.fetch(request)
            antall = result.count
        }
        catch {
            // print("Failed")
            return antall
        }
        return antall
    }
   
    
    
    func getGroups(startWith: String) -> [Group] {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Group> = Group.fetchRequest()
        
        if startWith == "%" {
            request.predicate = NSPredicate(format: "!groupName BEGINSWITH %@ AND !groupName BEGINSWITH %@ AND !groupName BEGINSWITH %@", "@", "$", "#")
        } else {
            request.predicate = NSPredicate(format: "groupName BEGINSWITH %@", startWith)
        }
       
        request.sortDescriptors = [NSSortDescriptor(key: "groupName", ascending: true)]
        do {
            return try context.fetch(request)
        } catch {
            print("❌ Failed to fetch groups starting with \(startWith): \(error)")
            return []
        }
    }
    func getAllGroups() -> [Group] {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Group> = Group.fetchRequest()
        request.sortDescriptors = [] // legg gjerne til sortering
        do {
            return try context.fetch(request)
        } catch {
            print("⚠️ Failed to fetch Core Data groups: \(error)")
            return []
        }
    }
    func getGroups() -> [Group] {
        let context = PersistenceController.shared.container.viewContext
        var groups = [Group]()
        let requestx = g.selectStatementGroup(
            group: "2",
            number: 10000,
            sort: "groupName",
            ascending: true,
            startWith: "%"
        )
        do {
            let result = try context.fetch(requestx)
            groups = result as? [Group] ?? []
        } catch {
            print("❌ Failed to fetch groups: \(error)")
        }
        return groups
    }
    func groupRequest(startWith: String) -> NSFetchRequest<Group> {
        let request: NSFetchRequest<Group> = Group.fetchRequest()
        request.predicate = NSPredicate(format: "groupName BEGINSWITH %@", startWith)
        request.sortDescriptors = [NSSortDescriptor(key: "groupName", ascending: true)]
        return request
    }
   
    func getAllWordsFromGroup(groupIdSelect: Int16, moveToGroup: Int16) -> [ThaiWords] {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        let datex = Date().addingTimeInterval(-86400 * 30)
        let imageTemp = UIImage(systemName: "star")!
        let selectString = "groupId = %@"
        // request.predicate = predicate
        request.predicate = NSPredicate(format: selectString, String(groupIdSelect))
        let sortDescriptor = NSSortDescriptor(key: "thaiWord", ascending: true)
        let sortDescriptors = [sortDescriptor]
        request.sortDescriptors = sortDescriptors
        do {
            return try context.fetch(request)
        } catch {
            print("❌ getWordCoreDataId feil:", error.localizedDescription)
            return []
        }
    }
    func getCount(request: NSFetchRequest<NSFetchRequestResult>) -> Int {
        var antall = 0
        let context = PersistenceController.shared.container.viewContext
        do {
            let result = try context.fetch(request)
            antall = result.count
        }
        catch {
            // print("Failed")
            return antall
        }
        return antall
    }
    func getGroupId(group: String) -> Int  {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Group")
        request.predicate = NSPredicate(format: "groupName = %@", group)
        request.returnsObjectsAsFaults = false
        var group = 0
        do {
            let result = try context.fetch(request)
            var i = 0
            for data in result as! [NSManagedObject] {
                i = i + 1
                group = Int(safeInt16Value(data: data, forKey: "groupId", defaultValue: 0))
            }
        } catch {
            // print("Failed")
        }
        // return request
        return group
    }
    func getGroupname(groupId: Int16) -> String  {
        let groupIdString = String(groupId)
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Group")
        request.predicate = NSPredicate(format: "groupId = %@", groupIdString)
        request.returnsObjectsAsFaults = false
        var groupName = ""
        do {
            let result = try context.fetch(request)
            var i = 0
            for data in result as! [NSManagedObject] {
                i = i + 1
                groupName = safeTextValue(data: data, forKey: "groupName", defaultValue: "none")
            }
        } catch {
            // print("Failed")
        }
        // return request
        return groupName
    }
    func getAntGroup(groupId: Int16) -> Int  {
        let groupIdString = String(groupId)
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        request.predicate = NSPredicate(format: "groupId = %@", groupIdString)
        request.returnsObjectsAsFaults = false
        var ant = 0
        do {
            let result = try context.fetch(request)
            ant = result.count
        } catch {
            // print("Failed")
        }
        // return request
        return ant
    }
    func insertCoreDataGroupId(id :Int16, thaiWord :String, groupId :Int16 ) {
        let search = thaiWord
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Group")
        request.predicate = NSPredicate(format: "gr = %@", search)
        request.returnsObjectsAsFaults = false
        do {
            let result = try context.fetch(request)
            for data in result as! [NSManagedObject] {
                data.setValue(groupId, forKey: "groupId")
                do {
                    try context.save()
                    // print("data uodated with groupId \(groupId)")
                } catch {
                    // print("Error updating")
                }
            }
        } catch {
            // print("Failed")
        }
    }
    func insertWordIntoCoreData(id:UUID,thaiword :String,englishword: String, sentence: String, groupId: Int16, image: UIImage) -> Bool {
        let context = PersistenceController.shared.container.viewContext

        // SJEKK FOR DUPLIKAT - ALDRI tillat duplikater basert på thaiWord
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ThaiWords")
        fetchRequest.predicate = NSPredicate(format: "thaiWord == %@", thaiword)
        fetchRequest.fetchLimit = 1

        do {
            let existingWords = try context.fetch(fetchRequest)
            if !existingWords.isEmpty {
                print("❌ DUPLIKAT BLOKKERT: '\(thaiword)' finnes allerede i databasen")
                return false
            }
        } catch {
            print("❌ Feil ved duplikatsjekk: \(error)")
            return false
        }

        let entity = NSEntityDescription.entity(forEntityName: "ThaiWords", in: context)
        let newWord = NSManagedObject(entity: entity!, insertInto: context)
        var ok = false

        var groupIdFix:Int16 = 129


        let dataMyImage:NSData = image.jpegData(compressionQuality: 1.0)! as NSData
        newWord.setValue(id, forKey: "id")
        newWord.setValue(thaiword, forKey: "thaiWord")
        newWord.setValue(englishword, forKey: "englishWord")
        newWord.setValue(sentence, forKey: "sentence")
        newWord.setValue(Date(), forKey: "insertDate")
        newWord.setValue(Date(), forKey: "modifiedDate")
        newWord.setValue(true, forKey: "star")
        newWord.setValue(groupIdFix, forKey: "groupId")
        newWord.setValue(dataMyImage, forKey: "image")
        print("word saved: \(thaiword) - \(englishword)  - group \(groupId)")
        do {
            try context.save()
            ok = true
        } catch {
            print("Failed saving")
        }
        return ok
    }
    
    func insertWordIntoCoreDataNoImage(id:UUID,thaiword :String,englishword: String, tag: String, groupId: Int16, wordType: Int16 = 0) -> Bool {
        let context = PersistenceController.shared.container.viewContext

        // SJEKK FOR DUPLIKAT - ALDRI tillat duplikater basert på thaiWord
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ThaiWords")
        fetchRequest.predicate = NSPredicate(format: "thaiWord == %@", thaiword)
        fetchRequest.fetchLimit = 1

        do {
            let existingWords = try context.fetch(fetchRequest)
            if !existingWords.isEmpty {
                print("❌ DUPLIKAT BLOKKERT: '\(thaiword)' finnes allerede i databasen")
                return false
            }
        } catch {
            print("❌ Feil ved duplikatsjekk: \(error)")
            return false
        }

        let entity = NSEntityDescription.entity(forEntityName: "ThaiWords", in: context)
        let newWord = NSManagedObject(entity: entity!, insertInto: context)
        var ok = false
        // let dataMyImage:NSData = image.jpegData(compressionQuality: 1.0)! as NSData
        newWord.setValue(id, forKey: "id")
        newWord.setValue(thaiword, forKey: "thaiWord")
        newWord.setValue(englishword, forKey: "englishWord")
        newWord.setValue(Date(), forKey: "modifiedDate")
        // Lagre tag i format ",tag," for korrekt CONTAINS-søk
        let formattedTag = tag.isEmpty ? nil : ",\(tag),"
        newWord.setValue(formattedTag, forKey: "tags")
        newWord.setValue(Date(), forKey: "insertDate")
        // newWord.setValue(true, forKey: "star")
        newWord.setValue(groupId, forKey: "groupId")
        newWord.setValue(wordType, forKey: "wordType")
       // newWord.setValue(dataMyImage, forKey: "image")
        print("word saved: \(thaiword) - \(englishword)  - group \(groupId)")
        do {
            try context.save()
            ok = true
        } catch {
            print("Failed saving")
        }
        return ok
    }
    
    func insertGroupIntoCoreData(groupId :Int16,groupName: String, groupType: Int16) {
        let context = PersistenceController.shared.container.viewContext
        let entity = NSEntityDescription.entity(forEntityName: "Group", in: context)
        let newWord = NSManagedObject(entity: entity!, insertInto: context)
        newWord.setValue(UUID(), forKey: "id")
        newWord.setValue(groupId, forKey: "groupId")
        newWord.setValue(groupName, forKey: "groupName")
        newWord.setValue(groupType, forKey: "groupType")
        print("group saved: \(groupName) ")
        do {
            try context.save()
        } catch {
            print("Failed saving")
        }
    }
    func insertCurrentGroupIntoCoreData(groupId :Int16,number: Int16) {
        let context = PersistenceController.shared.container.viewContext
        let entity = NSEntityDescription.entity(forEntityName: "CurrentGroup", in: context)
        let newWord = NSManagedObject(entity: entity!, insertInto: context)
        newWord.setValue(groupId, forKey: "groupId")
        newWord.setValue(number, forKey: "number")
        print("group saved: \(groupId) - \(number) ")
        do {
            try context.save()
        } catch {
            print("Failed saving")
        }
    }
    func updateCoreDataGroup(groupId :String, name : String ) -> Bool {
        var bReturn = false
        let search = groupId
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Group")
        request.predicate = NSPredicate(format: "groupId = %@", search)
        request.returnsObjectsAsFaults = false
        do {
            let result = try context.fetch(request)
            // let date = Date()
            for data in result as! [NSManagedObject] {
                data.setValue(name, forKey: "groupName")
                // data.setValue(language, forKey: "language")
                do {
                    try context.save()
                    bReturn = true
                    // print("data uodated with groupId \(groupId)")
                } catch {
                    // print("Error updating")
                }
            }
        } catch {
            return false
        }
        return bReturn
    }
   
    func deleteImage(for id: UUID) -> Bool {
        let context = PersistenceController.shared.container.viewContext
        
        var success = false
        context.performAndWait {
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            
            let req = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            req.fetchLimit = 1
            req.returnsObjectsAsFaults = false
            
            do {
                guard let obj = try context.fetch(req).first else { success = false; return }
                
                // hent siste versjon for sikkerhet
                context.refresh(obj, mergeChanges: true)
                
                // sett bildet til nil
                obj.setValue(nil, forKey: "image")
                
                // oppdatér "sist endret"-dato hvis du ønsker
                obj.setValue(Date(), forKey: "dateTwo")
                
                try context.save()
                success = true
            } catch {
                print("❌ CoreData delete image failed:", (error as NSError).userInfo)
                success = false
            }
        }
        return success
    }
    
        


    func updateWord(id: UUID,
                    englishWord: String,
                    groupId: Int16,
                    image: UIImage,
                    sentence: String) -> Bool {

        let context = PersistenceController.shared.container.viewContext

        var success = false
        context.performAndWait {                      // ← kjør på context-tråden
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

            let req = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            req.fetchLimit = 1
            req.returnsObjectsAsFaults = false

            do {
                guard let obj = try context.fetch(req).first else { success = false; return }

                // hent siste versjon (belt & suspenders mot 133020)
                context.refresh(obj, mergeChanges: true)

                if let data = image.jpegData(compressionQuality: 0.9) {
                    obj.setValue(data,       forKey: "image")
                }

                obj.setValue(englishWord,    forKey: "englishWord")
                obj.setValue(groupId,        forKey: "groupId")
                obj.setValue(sentence,       forKey: "sentence")
                obj.setValue(Date(),         forKey: "dateTwo")       // updatedDate
                obj.setValue(Date(),         forKey: "insertDate")
                // IKKE rør "insertDate" her

                try context.save()
                success = true
            } catch {
                print("❌ CoreData update failed:", (error as NSError).userInfo)
                success = false
            }
        }
        return success
    }
    
    
    func updateWordData(id :String, englishWord: String, groupId: Int16, image: UIImage, sentence: String) -> Bool {
        // fix everything is set to current time!! fix
        let search = id
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        request.predicate = NSPredicate(format: "id = %@", search)
        request.returnsObjectsAsFaults = false
        let dataMyImage:NSData = image.jpegData(compressionQuality: 1.0)! as NSData
        let date = Date.now
        let result = true
        do {
            let result = try context.fetch(request)
            // let date = Date()
            for data in result as! [NSManagedObject] {
                data.setValue(date, forKey: "dateTwo")
                data.setValue(englishWord, forKey: "englishWord")
                data.setValue(dataMyImage, forKey: "image")
                data.setValue(groupId, forKey: "groupId")
                data.setValue(sentence, forKey: "sentence")
                // data.setValue(date, forKey: "dateOne")
                data.setValue(Date(), forKey: "insertDate")
                do {
                    // result = true
                    try context.save()
                } catch {
                    // print("Error updating")
                    //result = false
                }
            }
        } catch {
            // print("Failed")
        }
        return result
    }
    func updateSentenceData(id :String, sentence: String) -> Bool {
        // fix everything is set to current time!! fix
        // let search = id
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        request.predicate = NSPredicate(format: "id = %@", id)
        request.returnsObjectsAsFaults = false
        // let dataMyImage:NSData = image.jpegData(compressionQuality: 1.0)! as NSData
        //  let date = Date.now
        let result = true
        do {
            let result = try context.fetch(request)
            // let date = Date()
            for data in result as! [NSManagedObject] {
                //data.setValue(date, forKey: "dateTwo")
                // data.setValue(englishWord, forKey: "englishWord")
                // data.setValue(dataMyImage, forKey: "image")
                // data.setValue(groupId, forKey: "groupId")
                data.setValue(sentence, forKey: "sentence")
                // data.setValue(date, forKey: "dateOne")
                data.setValue(Date(), forKey: "insertDate")
                do {
                    // result = true
                    try context.save()
                } catch {
                    // print("Error updating")
                    //result = false
                }
            }
        } catch {
            // print("Failed")
        }
        return result
    }
    func updateIdCoreData(word :String, id: UUID) {
        // fix everything is set to current time!! fix
        let search = word
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        request.predicate = NSPredicate(format: "thaiWord = %@", search)
        request.returnsObjectsAsFaults = false
        // var prev = "asdfqwertvs"
        do {
            let result = try context.fetch(request)
            // let date = Date()
            // var ant = 0
            for data in result as! [NSManagedObject] {
                //  let wordCheck = data.value(forKey: "thaiWord")
                let idx = UUID()
                data.setValue(idx, forKey: "id")
                do {
                    try context.save()
                } catch {
                    print("Error updating")
                }
            }
        } catch {
            // print("Failed")
        }
    }
    func updateGroupCoreData(thaiword :String, groupId: Int16) -> Bool {
        let search = thaiword
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        request.predicate = NSPredicate(format: "thaiWord = %@", search)
        request.returnsObjectsAsFaults = false
        var isOk = false
        do {
            let result = try? context.fetch(request)
            let date = Date()
            if result?.count ?? 0 > 0 {
                //  let data = result![0]
                for data in result as! [NSManagedObject] {
                    data.setValue(groupId, forKey: "groupId")
                    data.setValue(date, forKey: "insertDate")
                }
                do {
                    try context.save()
                    isOk = true
                    print("saved to: \(groupId) !!!")
                } catch {
                    print(error.localizedDescription)
                    return false
                }
            }
        }
        return isOk
    }
    
    
    /*
        func searchThaiWordOld(searchWord: String, context: NSManagedObjectContext) -> [String] {
            
            print("🔍 SØKER ETTER '\(searchWord)'")
            print("🔍 Context: \(context)")
            print("🔍 Context has changes: \(context.hasChanges)")
            print("🔍 Registered objects count: \(context.registeredObjects.count)")

            let allRequest = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
            do {
                let alle = try context.fetch(allRequest)
                print("📦 Totalt antall ThaiWords i context: \(alle.count)")
            } catch {
                print("🛑 Kunne ikke hente alle ThaiWords: \(error.localizedDescription)")
            }
            
            // ออกกำลังกาย
            let request = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "thaiWord = %@", searchWord)
             //   NSPredicate(format: "englishWord CONTAINS[cd] %@", searchWord),
              //  NSPredicate(format: "sentence CONTAINS[cd] %@", searchWord)
            ])
            
            do {
                let resultater = try context.fetch(request)
                let thaiOrdArray = resultater.compactMap { $0.thaiWord }
                return Array(Set(thaiOrdArray)) // fjerner duplikater hvis ønsket
            } catch {
                print("🔴 Feil under søk: \(error.localizedDescription)")
                return []
            }
        }
        */
    
    
    // hvorfor virker ikke sok på bordet: มยไม่มีที่จับเลแล้วที่มันไม่พออ่ะก็หา


    func searchThaiWordFree(searchWord: String, context: NSManagedObjectContext) -> [NSManagedObjectID] {
        // Normaliser inndata: trim + NFC for thailandske kombitegn
        let term = searchWord
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping  // NFC

        guard !term.isEmpty else { return [] }

        let request = NSFetchRequest<NSManagedObjectID>(entityName: "ThaiWords")

        // Thai terms: exact match only — [cd] strips diacritics making ปู่→ป which
        // matches any Thai word containing that consonant (false positives). I gNorsk
        // er det translation1 (ikke thaiWord) som inneholder ekte thai-skrift.
        // Latin terms: substring match with case/diacritic folding across thaiWord/English/notes.
        let isThaiQuery = term.unicodeScalars.contains { $0.value >= 0x0E00 && $0.value <= 0x0E7F }
        if isThaiQuery {
            let canonical = canonicalThaiString(term)
            let thaiMatch: NSPredicate
            if term == canonical {
                thaiMatch = NSPredicate(format: "translation1 == %@", canonical)
            } else {
                thaiMatch = NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "translation1 == %@", term),
                    NSPredicate(format: "translation1 == %@", canonical),
                ])
            }
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                thaiMatch,
                NSPredicate(format: "notes CONTAINS[c] %@", term),
            ])
        } else {
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "englishWord CONTAINS[c] %@", term),
                NSPredicate(format: "translation1 CONTAINS[c] %@", term),
                NSPredicate(format: "thaiWord CONTAINS[c] %@", term),
                NSPredicate(format: "notes CONTAINS[c] %@", term),
            ])
        }

        request.resultType = .managedObjectIDResultType
        request.returnsDistinctResults = true

        do {
            return try context.fetch(request)
        } catch {
            print("🛑 Feil under søk: \(error.localizedDescription)")
            return []
        }
    }
    
    /*
    func searchThaiWordFreeOld(searchWord: String, context: NSManagedObjectContext) -> [String] {
        
        print("🔍 SØKER ETTER '\(searchWord)'")
        print("🔍 Context: \(context)")
        print("🔍 Context has changes: \(context.hasChanges)")
        print("🔍 Registered objects count: \(context.registeredObjects.count)")

        let allRequest = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        do {
            let alle = try context.fetch(allRequest)
            print("📦 Totalt antall ThaiWords i context: \(alle.count)")
        } catch {
            print("🛑 Kunne ikke hente alle ThaiWords: \(error.localizedDescription)")
        }
        
        // ออกกำลังกาย
        let request = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "thaiWord = %@", searchWord),
            NSPredicate(format: "englishWord CONTAINS[cd] %@", searchWord),
            NSPredicate(format: "sentence CONTAINS[cd] %@", searchWord)
        ])
        
        do {
            let resultater = try context.fetch(request)
            let thaiOrdArray = resultater.compactMap { $0.thaiWord }
            return Array(Set(thaiOrdArray)) // fjerner duplikater hvis ønsket
        } catch {
            print("🔴 Feil under søk: \(error.localizedDescription)")
            return []
        }
    }
    */
    
    func searchThaiWordSentence(searchWord: String, context: NSManagedObjectContext) throws -> [NSManagedObjectID] {
        let req = NSFetchRequest<NSManagedObjectID>(entityName: "ThaiWords")
        req.predicate = NSPredicate(format: "sentence CONTAINS[cd] %@", searchWord)
        req.resultType = .managedObjectIDResultType
        req.returnsDistinctResults = true
        return try context.fetch(req)
    }
    
    func searchThaiWord(searchWord: String, context: NSManagedObjectContext) throws -> [NSManagedObjectID] {
        let nfc = searchWord.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        let canonical = canonicalThaiString(nfc)
        let req = NSFetchRequest<NSManagedObjectID>(entityName: "ThaiWords")
        // Search both the typed form and the canonical form — covers all diacritic orderings
        if nfc == canonical {
            req.predicate = NSPredicate(format: "thaiWord = %@", canonical)
        } else {
            req.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "thaiWord = %@", nfc),
                NSPredicate(format: "thaiWord = %@", canonical),
            ])
        }
        req.resultType = .managedObjectIDResultType
        req.returnsDistinctResults = true
        return try context.fetch(req)
    }

    /// Prefix-søk på thaiWord — trigges av avsluttende "%" i søketeksten (f.eks. "ทร%" → alt som starter på ทร)
    func searchThaiWordPrefix(searchWord: String, context: NSManagedObjectContext) throws -> [NSManagedObjectID] {
        let nfc = searchWord.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        let canonical = canonicalThaiString(nfc)
        let req = NSFetchRequest<NSManagedObjectID>(entityName: "ThaiWords")
        if nfc == canonical {
            req.predicate = NSPredicate(format: "thaiWord BEGINSWITH[cd] %@", canonical)
        } else {
            req.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "thaiWord BEGINSWITH[cd] %@", nfc),
                NSPredicate(format: "thaiWord BEGINSWITH[cd] %@", canonical),
            ])
        }
        req.resultType = .managedObjectIDResultType
        req.returnsDistinctResults = true
        return try context.fetch(req)
    }

    /// I gNorsk sin database inneholder "translation1" ekte thai-skrift (motsatt av gThai — se
    /// DetailWordView.swift:3976). Speiler searchThaiWord: eksakt treff + kanonisk normalisering,
    /// ikke CONTAINS, for å unngå at diakritikk-stripping gir falske treff på thai-tegn.
    func searchThaiTranslation(searchWord: String, context: NSManagedObjectContext) throws -> [NSManagedObjectID] {
        let nfc = searchWord.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        let canonical = canonicalThaiString(nfc)
        let req = NSFetchRequest<NSManagedObjectID>(entityName: "ThaiWords")
        if nfc == canonical {
            req.predicate = NSPredicate(format: "translation1 = %@", canonical)
        } else {
            req.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "translation1 = %@", nfc),
                NSPredicate(format: "translation1 = %@", canonical),
            ])
        }
        req.resultType = .managedObjectIDResultType
        req.returnsDistinctResults = true
        return try context.fetch(req)
    }

    /// Prefix-søk på translation1 (thai-skrift i gNorsk) — trigges av avsluttende "%" i søketeksten.
    func searchThaiTranslationPrefix(searchWord: String, context: NSManagedObjectContext) throws -> [NSManagedObjectID] {
        let nfc = searchWord.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        let canonical = canonicalThaiString(nfc)
        let req = NSFetchRequest<NSManagedObjectID>(entityName: "ThaiWords")
        if nfc == canonical {
            req.predicate = NSPredicate(format: "translation1 BEGINSWITH[cd] %@", canonical)
        } else {
            req.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "translation1 BEGINSWITH[cd] %@", nfc),
                NSPredicate(format: "translation1 BEGINSWITH[cd] %@", canonical),
            ])
        }
        req.resultType = .managedObjectIDResultType
        req.returnsDistinctResults = true
        return try context.fetch(req)
    }

    func searchEnglish(searchWord: String, exact: Bool, context: NSManagedObjectContext) -> [NSManagedObjectID] {
        let term = searchWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        let req = NSFetchRequest<NSManagedObjectID>(entityName: "ThaiWords")
        req.predicate = exact
            ? NSPredicate(format: "englishWord ==[c] %@", term)
            : NSPredicate(format: "englishWord CONTAINS[c] %@", term)
        req.resultType = .managedObjectIDResultType
        req.returnsDistinctResults = true
        return (try? context.fetch(req)) ?? []
    }

    /// I gNorsk sin database inneholder "thaiWord" det norske ordet (motsatt av gThai — se
    /// CreateWordView.swift: TextField("Norwegian word", text: $thaiWord)). Vanlig CONTAINS-søk,
    /// siden feltet her er norsk løpetekst uten thai-skriftens diakritikk-fallgruver.
    func searchNorsk(searchWord: String, exact: Bool, context: NSManagedObjectContext) -> [NSManagedObjectID] {
        let term = searchWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        let req = NSFetchRequest<NSManagedObjectID>(entityName: "ThaiWords")
        req.predicate = exact
            ? NSPredicate(format: "thaiWord ==[c] %@", term)
            : NSPredicate(format: "thaiWord CONTAINS[c] %@", term)
        req.resultType = .managedObjectIDResultType
        req.returnsDistinctResults = true
        return (try? context.fetch(req)) ?? []
    }

    func searchSentence(searchWord: String, exact: Bool, context: NSManagedObjectContext) -> [NSManagedObjectID] {
        let term = searchWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        let req = NSFetchRequest<NSManagedObjectID>(entityName: "ThaiWords")
        req.predicate = exact
            ? NSPredicate(format: "sentence ==[c] %@", term)
            : NSPredicate(format: "sentence CONTAINS[c] %@", term)
        req.resultType = .managedObjectIDResultType
        req.returnsDistinctResults = true
        return (try? context.fetch(req)) ?? []
    }




    /*
    func searchThaiWordSentenceOld(searchWord: String, context: NSManagedObjectContext) -> [String] {
        
        print("🔍 SØKER ETTER '\(searchWord)'")
        print("🔍 Context: \(context)")
        print("🔍 Context has changes: \(context.hasChanges)")
        print("🔍 Registered objects count: \(context.registeredObjects.count)")

        let allRequest = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        do {
            let alle = try context.fetch(allRequest)
            print("📦 Totalt antall ThaiWords i context: \(alle.count)")
        } catch {
            print("🛑 Kunne ikke hente alle ThaiWords: \(error.localizedDescription)")
        }
        
        // ออกกำลังกาย
        let request = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            
            NSPredicate(format: "sentence CONTAINS[cd] %@", searchWord)
        ])
        
        do {
            let resultater = try context.fetch(request)
            let thaiOrdArray = resultater.compactMap { $0.thaiWord }
            return Array(Set(thaiOrdArray)) // fjerner duplikater hvis ønsket
        } catch {
            print("🔴 Feil under søk: \(error.localizedDescription)")
            return []
        }
    }
    */

    func updateGroupIdCoreData(id :String, groupId: Int16) -> Bool {
        let search = id
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        request.predicate = NSPredicate(format: "id = %@", search)
        request.returnsObjectsAsFaults = false
        var isOk = false
        do {
            do {
                let result = try context.fetch(request)
                let datex = Date()
                // print("no: \(result.count)")
                for data in result as! [NSManagedObject] {
                    data.setValue(groupId, forKey: "groupId")
                    data.setValue(true, forKey: "star")
                    data.setValue(datex, forKey: "insertDate")
                    // data.setValue(date, forKey: "insertDate")
                }
                do {
                    try context.save()
                    isOk = true
                    print("saved to: \(groupId) !!!")
                } catch {
                    print(error.localizedDescription)
                    return false
                }
            }
        } catch {
            // print("Failed")
        }
        return isOk
    }
    func updateInsertDateCoreData(id :String) -> Bool {
        let search = id
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        request.predicate = NSPredicate(format: "id = %@", search)
        request.returnsObjectsAsFaults = false
        var isOk = false
        do {
            let result = try? context.fetch(request)
            let date = Date.now
            if result?.count ?? 0 > 0 {
                //  let data = result![0]
                for data in result as! [NSManagedObject] {
                    data.setValue(date, forKey: "insertDate")
                }
                do {
                    try context.save()
                    isOk = true
                } catch {
                    // print(error.localizedDescription)
                    return false
                }
            }
        }
        return isOk
    }
    func updateStarCoreData(id :String, star:Bool) {
        let search = id
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        request.predicate = NSPredicate(format: "id = %@", search)
        request.returnsObjectsAsFaults = false
        do {
            let result = try context.fetch(request)
            let date = Date()
            print("no: \(result.count)")
            for data in result as! [NSManagedObject] {
                data.setValue(star, forKey: "star")
                data.setValue(date, forKey: "insertDate")
                do {
                    print("saved: \(id) value : \(star) !!!")
                    try context.save()
                } catch {
                    print("Error updating")
                }
            }
        } catch {
            // print("Failed")
        }
    }
    func updateDateTwoCoreData(id :String, date: Date) {
        let search = id
        //let date = Date()
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        request.predicate = NSPredicate(format: "id = %@", search)
        request.returnsObjectsAsFaults = false
        do {
            let result = try context.fetch(request)
            for data in result as! [NSManagedObject] {
                //data.setValue(date1, forKey: "dateTwo")
                data.setValue(date, forKey: "dateTwo")
                do {
                    try context.save()
                } catch {
                    // print("Error updating")
                }
            }
        } catch {
            // print("Failed")
        }
    }
    func updateDateOneCoreData(id :String, date: Date) {
        let search = id
        let date = Date()
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        request.predicate = NSPredicate(format: "id = %@", search)
        request.returnsObjectsAsFaults = false
        do {
            let result = try context.fetch(request)
            for data in result as! [NSManagedObject] {
                //data.setValue(date1, forKey: "dateTwo")
                data.setValue(date, forKey: "dateOne")
                do {
                    try context.save()
                } catch {
                    // print("Error updating")
                }
            }
        } catch {
            // print("Failed")
        }
    }
    func safeDateValue(data: NSManagedObject, forKey: String, defaultValue: Date)-> Date {
        var returnValue = defaultValue
        let x = (data.value(forKey: forKey))
        if x != nil {
            returnValue = ((data.value(forKey: forKey)) as! Date)
        }
        return returnValue
    }
    func safeTextValue(data: NSManagedObject, forKey: String, defaultValue: String)-> String {
        var returnText = defaultValue
        let x = (data.value(forKey: forKey))
        if x != nil {
            returnText = ((data.value(forKey: forKey)) as! String)
        }
        return returnText
    }
    func safeBoolValue(data: NSManagedObject, forKey: String, defaultValue: Bool)-> Bool {
        var returnx = defaultValue
        let x = (data.value(forKey: forKey))
        if x != nil {
            returnx = ((data.value(forKey: forKey)) as! Bool)
        }
        return returnx
    }
    
    func safeInt16Value(data: NSManagedObject, forKey: String, defaultValue: Int16)-> Int16 {
        var returnValue = defaultValue
        let x = (data.value(forKey: forKey))
        if x != nil {
            returnValue = ((data.value(forKey: forKey)) as! Int16)
        }
        return returnValue
    }
    func deleteCurrentGroupCoreData()  {
        // let search = String(thaiWord)
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "CurrentGroup")
        // request.predicate = NSPredicate(format: "thaiWord = %@", search)
        request.returnsObjectsAsFaults = false
        do {
            let records = try context.fetch(request) as! [NSManagedObject]
            let max = records.count
            if max == 0 {
                // UIAlertController.alert(title: "Feil ved delete",msg: "", target: self)
            }
            else {
                for record in records {
                    context.delete(record)
                    try context.save()
                }
            }
        } catch {
            // print("Failed")
        }
    }
    func deleteGroupCoreData(groupId:Int16) -> Bool {
        let search = String(groupId)
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Group")
        request.predicate = NSPredicate(format: "groupId = %@", search)
        request.returnsObjectsAsFaults = false
        do {
            let records = try context.fetch(request) as! [NSManagedObject]
            let max = records.count
            if max == 0 {
                // UIAlertController.alert(title: "Feil ved delete",msg: "", target: self)
                return false
            }
            else {
                for record in records {
                    context.delete(record)
                    try context.save()
                }
            }
        } catch {
            // print("Failed")
        }
        return true
    }
    func deleteNorwegianWordCoreData(englishWord :String) -> Bool {
        let search = String(englishWord)
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        request.predicate = NSPredicate(format: "englishWord = %@", search)
        request.returnsObjectsAsFaults = false
        do {
            let records = try context.fetch(request) as! [NSManagedObject]
            let max = records.count
            if max == 0 {
                // UIAlertController.alert(title: "Feil ved delete",msg: "", target: self)
                return false
            }
            else {
                for record in records {
                    context.delete(record)
                    try context.save()
                }
            }
        } catch {
            // print("Failed")
        }
        return true
    }
    func deleteWordCoreData(thaiWordUUID :UUID) -> Bool {
        let search = thaiWordUUID.description
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ThaiWords")
        request.predicate = NSPredicate(format: "id = %@", search)
        request.returnsObjectsAsFaults = false
        do {
            let records = try context.fetch(request) as! [NSManagedObject]
            let max = records.count
            if max == 0 {
                // UIAlertController.alert(title: "Feil ved delete",msg: "", target: self)
                return false
            }
            else {
                for record in records {
                    context.delete(record)
                    try context.save()
                }
            }
        } catch {
            // print("Failed")
        }
        return true
    }
    

    func batchDeleteWords(in groupId: Int16) {
        let context = PersistenceController.shared.container.newBackgroundContext()

        context.perform {
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "ThaiWords")
            fetchRequest.predicate = NSPredicate(format: "groupId == %d", groupId)

            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            deleteRequest.resultType = .resultTypeCount

            do {
                let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
                print("🧹 Deleted \(result?.result as? Int ?? 0) words from group \(groupId)")
            } catch {
                print("❌ Batch delete failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Read-only Core Data helpers for safe background fetches
extension GlFunctions {
    /// A private read-only context for background fetches. Do not use for writes.
    var readContext: NSManagedObjectContext {
        let container = PersistenceController.shared.container
        let ctx = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        ctx.persistentStoreCoordinator = container.persistentStoreCoordinator
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        ctx.automaticallyMergesChangesFromParent = true
        return ctx
    }

    struct ThaiWordsDTO {
        let thaiWord: String
        let syllables: [String]
        let ipa: String?
    }
    /// Safe fetch that does not touch viewContext. Returns a DTO (plain values), never NSManagedObject.
    func fetchThaiWordDTO(thaiWord: String) -> ThaiWordsDTO? {
        let ctx = readContext
        var out: ThaiWordsDTO?
        ctx.performAndWait {
            let req = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
            req.predicate = NSPredicate(format: "thaiWord == %@", thaiWord)
            req.fetchLimit = 1
            req.includesPropertyValues = true
            req.returnsObjectsAsFaults = false
            do {
                if let w = try ctx.fetch(req).first {
                    out = ThaiWordsDTO(
                        thaiWord: w.thaiWord ?? "",
                        syllables: w.syllables ?? [],
                        ipa: w.ipa
                    )
                }
            } catch {
                print("⚠️ fetchThaiWordDTO error for '\(thaiWord)': \(error)")
            }
        }
        return out
    }
}

// MARK: - Thai canonical normalization

private func _thaiDiacriticPriority(_ v: UInt32) -> Int {
    switch v {
    case 0x0E38...0x0E39: return 1  // below-base vowels (sara u, sara uu)
    case 0x0E34...0x0E37, 0x0E47: return 2  // above-base vowels
    case 0x0E4C, 0x0E4D: return 3  // thanthakat, nikhahit
    case 0x0E48...0x0E4B: return 4  // tone marks
    default: return 5
    }
}

private func _isThaiDiacritic(_ v: UInt32) -> Bool {
    v >= 0x0E34 && v <= 0x0E4E
}

// Invisible/junk Unicode codepoints to strip from Thai text
private let _thaiStripSet: Set<UInt32> = [
    0x200B, // zero-width space
    0x200C, // zero-width non-joiner
    0x200D, // zero-width joiner
    0xFEFF, // BOM / zero-width no-break space
    0x00A0, // non-breaking space
    0x2060, // word joiner
    0x180E, // mongolian vowel separator
]

/// Strips invisible characters, reorders Thai combining chars to canonical order.
/// Fixes hidden duplicates where the same word differs only in invisible bytes.
func canonicalThaiString(_ input: String) -> String {
    let nfc = input.precomposedStringWithCanonicalMapping
    var result: [Unicode.Scalar] = []
    var cluster: [Unicode.Scalar] = []

    func flush() {
        guard !cluster.isEmpty else { return }
        let base = cluster[0]
        var dia = Array(cluster.dropFirst())
        dia.sort { _thaiDiacriticPriority($0.value) < _thaiDiacriticPriority($1.value) }
        result.append(base)
        result.append(contentsOf: dia)
        cluster.removeAll()
    }

    for s in nfc.unicodeScalars {
        if _thaiStripSet.contains(s.value) { continue }  // drop invisible chars
        if _isThaiDiacritic(s.value) {
            cluster.append(s)
        } else {
            flush()
            cluster.append(s)
        }
    }
    flush()
    return String(String.UnicodeScalarView(result)).trimmingCharacters(in: .whitespaces)
}

/// Returns hex dump of a string's unicode scalars — for debugging hidden char differences.
func thaiHexDump(_ s: String) -> String {
    s.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
}

