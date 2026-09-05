//
//  ThaiNLPData.swift
//  gThai
//
//  Thai syllable and IPA data from Core Data
//  Uses PyThaiNLP-generated data stored in ThaiWords entity
//
//  BRUK:
//      let result = ThaiNLPData.lookup("กลางคืน", context: viewContext)
//      print(result.syllables)  // ["กลาง", "คืน"]
//      print(result.ipa)        // "klaːŋ.kʰɯːn"
//

import Foundation
import CoreData

/// Resultat fra Thai NLP oppslag
struct ThaiNLPResult {
    let text: String
    let syllables: [String]
    let ipa: String
    let isPreComputed: Bool

    /// For debugging - vis om data kom fra pre-computed database eller fallback
    var source: String {
        isPreComputed ? "Core Data (PyThaiNLP)" : "Fallback (ThaiSeg)"
    }
}

/// Manager for Thai linguistic data from Core Data
/// Dette er din ENESTE interface - alt annet er internt!
enum ThaiNLPData {

    // Debug bypass: when true, skip Core Data and ThaiSeg and return a dummy result
    static var debugBypassLookup: Bool = false

    // MARK: - Public API

    /// Hovedfunksjon: Slå opp Thai tekst og få stavelser + IPA fra Core Data (async)
    ///
    /// Eksempel:
    /// ```swift
    /// let result = await ThaiNLPData.lookup("กลางคืน", context: viewContext)
    /// print(result.syllables)  // ["กลาง", "คืน"]
    /// print(result.ipa)        // "klaːŋ.kʰɯːn"
    /// ```
    static func lookup(_ text: String, context: NSManagedObjectContext) async -> ThaiNLPResult {
        // DEBUG: bypass all lookups to test if hangs are related to Core Data / ThaiSeg
        if debugBypassLookup {
            print("🔧 DEBUG BYPASS ACTIVE — returning dummy NLP result for '\(text)'")
            // Simple deterministic dummy: treat whole text as one syllable, no IPA
            return ThaiNLPResult(
                text: text,
                syllables: text.isEmpty ? [] : [text],
                ipa: "—",
                isPreComputed: false
            )
        }

        // Slå opp i Core Data
        if let word = await fetchWord(text, context: context) {
            // Har vi syllables?
            if let syllables = word.syllables, !syllables.isEmpty {
                // Valider: stavelser satt sammen MÅ matche original tekst
                let joined = syllables.joined()
                if joined == text {
                    let ipa = word.ipa ?? "—"
                    return ThaiNLPResult(
                        text: text,
                        syllables: syllables,
                        ipa: ipa,
                        isPreComputed: true
                    )
                } else {
                    // Korrupt data - IKKE slett (DetailWordView auto-fyller med feil ThaiSeg)
                    // Bare ignorer og fall gjennom til ThaiSeg fallback
                    print("⚠️ Korrupt stavelse-data for '\(text)': joined='\(joined)' ≠ '\(text)' - ignorerer")
                }
            }
        }

        // Fallback: Bruk ThaiSeg + ThaiIPA og LAGRE resultatet
        print("⚠️ '\(text)' ikke funnet eller mangler syllables - genererer med ThaiSeg")

        let syllables = ThaiSeg.segmentWordIntoSyllables(text)
        let syllableStrings = syllables.map { $0.original }
        let ipaString = syllables.map { ipaForSyllable($0) }.joined(separator: ".")

        // Lagre til Core Data for fremtidig bruk
  //      saveGeneratedData(
  //          text: text,
  //          syllables: syllableStrings,
  //          ipa: ipaString,
  //          context: context
  //      )

        return ThaiNLPResult(
            text: text,
            syllables: syllableStrings,
            ipa: ipaString.isEmpty ? "—" : ipaString,
            isPreComputed: false
        )
    }

    /// Synchronous wrapper for legacy code
    static func lookup(_ text: String, context: NSManagedObjectContext) -> ThaiNLPResult {
        // Synchronous wrapper that bridges to async for legacy callers
        let semaphore = DispatchSemaphore(value: 0)
        var output: ThaiNLPResult? = nil
        Task {
            output = await lookup(text, context: context)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)
        return output ?? ThaiNLPResult(text: text, syllables: [], ipa: "—", isPreComputed: false)
    }

    /// Sjekk om et ord finnes i Core Data med syllables
    static func hasPreComputedData(for text: String, context: NSManagedObjectContext) -> Bool {
        // This function is sync, calling async fetchWord is not possible without async
        // So keep it as is with synchronous fetchWord or block with semaphore
        // But since fetchWord is now async, provide a synchronous fetchWord variant here for this?
        // For now, keep old fetchWord sync for this function only:

        var hasSyllables = false
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            if let word = await fetchWord(text, context: context) {
                hasSyllables = word.hasSyllables
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)
        return hasSyllables
    }

    /// Få statistikk om NLP data i databasen
    static func databaseStats(context: NSManagedObjectContext) -> (totalEntries: Int, withSyllables: Int, withIPA: Int) {
        let stats = ThaiWords.getNLPStatistics(context: context)
        return (stats.total, stats.withSyllables, stats.withIPA)
    }

    // MARK: - Private Implementation

    /// Hent word fra Core Data (async variant)
    private static func fetchWord(_ text: String, context: NSManagedObjectContext) async -> ThaiWords? {
        await context.perform {
            let request = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
            request.predicate = NSPredicate(format: "thaiWord == %@", text)
            request.fetchLimit = 1
            do {
                return try context.fetch(request).first
            } catch {
                print("⚠️ Error fetching word '\(text)': \(error)")
                return nil
            }
        }
    }

    /// Lagre genererte syllables og IPA til Core Data
    private static func saveGeneratedData(
        text: String,
        syllables: [String],
        ipa: String,
        context: NSManagedObjectContext
    ) {
        context.perform {
            // Check for existing word inside the same context/queue
            let fetch = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
            fetch.predicate = NSPredicate(format: "thaiWord == %@", text)
            fetch.fetchLimit = 1

            do {
                if let _ = try context.fetch(fetch).first {
                    // Never overwrite existing rows with ThaiSeg data
                    print("⚠️ Ord '\(text)' finnes allerede - lagrer ikke ThaiSeg-data over det")
                    return
                }
            } catch {
                print("⚠️ Fetch i saveGeneratedData feilet for '\(text)': \(error)")
                return
            }

            let word = ThaiWords(context: context)
            word.thaiWord = text
            word.id = UUID()
            word.insertDate = Date()
            word.groupId = 0
            word.star = false
            word.easiness = 2.5

            // Lagre NLP data
            word.updateNLPData(syllables: syllables, ipa: ipa, source: "ThaiSeg")

            do {
                try context.save()
                print("💾 Saved syllables for '\(text)' to Core Data")
            } catch {
                print("❌ Failed to save syllables: \(error)")
            }
        }
    }

    // MARK: - Async Helpers for migration and external helpers

    /// Async helper for å migrere fra din gamle ThaiSeg til Core Data
    static func segmentToSyllables(_ text: String, context: NSManagedObjectContext) async -> [String] {
        let result = await lookup(text, context: context)
        return result.syllables
    }

    /// Async helper for å få IPA direkte
    static func textToIPA(_ text: String, context: NSManagedObjectContext) async -> String {
        let result = await lookup(text, context: context)
        return result.ipa
    }
}

// MARK: - Convenience Extensions

extension ThaiNLPResult: CustomStringConvertible {
    var description: String {
        """
        ThaiNLPResult(
            text: "\(text)"
            syllables: \(syllables)
            ipa: "\(ipa)"
            source: \(source)
        )
        """
    }
}

// MARK: - Migration Helpers

extension ThaiNLPData {
    /// Helper for å migrere fra din gamle ThaiSeg til Core Data (sync, calls async version)
    static func segmentToSyllables(_ text: String, context: NSManagedObjectContext) -> [String] {
        let semaphore = DispatchSemaphore(value: 0)
        var resultSyllables: [String] = []
        Task {
            resultSyllables = await segmentToSyllables(text, context: context)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)
        return resultSyllables
    }

    /// Helper for å få IPA direkte (sync wrapper)
    static func textToIPA(_ text: String, context: NSManagedObjectContext) -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var ipaResult: String = "—"
        Task {
            ipaResult = await textToIPA(text, context: context)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)
        return ipaResult
    }
}

// MARK: - Batch Operations

extension ThaiNLPData {
    /// Batch-lookup for flere ord samtidig (sync wrapper)
    static func lookupBatch(_ texts: [String], context: NSManagedObjectContext) -> [ThaiNLPResult] {
        let semaphore = DispatchSemaphore(value: 0)
        var results: [ThaiNLPResult] = []
        Task {
            results = await lookupBatchAsync(texts, context: context)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5.0)
        return results
    }

    /// Async variant av batch lookup
    static func lookupBatchAsync(_ texts: [String], context: NSManagedObjectContext) async -> [ThaiNLPResult] {
        var results: [ThaiNLPResult] = []
        for text in texts {
            let result = await lookup(text, context: context)
            results.append(result)
        }
        return results
    }

    /// Sjekk hvor mange ord som er pre-computed vs fallback (sync wrapper)
    static func batchStats(_ texts: [String], context: NSManagedObjectContext) -> (preComputed: Int, fallback: Int) {
        let results = lookupBatch(texts, context: context)
        let preComputed = results.filter { $0.isPreComputed }.count
        let fallback = results.count - preComputed
        return (preComputed, fallback)
    }
}

