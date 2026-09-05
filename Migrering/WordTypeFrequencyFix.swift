// WordTypeFrequencyFix.swift
// Engangsfiks: ord med en frekvensrank i kjerne-listen (1–4000) skal alltid være wordType 0 (Ord),
// aldri wordType 1 (Setning). Feilaktige verdier stammer trolig fra da ord/setning-skillet ble innført.
import CoreData

enum WordTypeFrequencyFix {

    static let minFrequencyRank: Int32 = 1
    static let maxFrequencyRank: Int32 = 4000

    private static func mismatchedRequest() -> NSFetchRequest<ThaiWords> {
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(
            format: "frequencyRank >= %d AND frequencyRank <= %d AND wordType == 1",
            minFrequencyRank, maxFrequencyRank
        )
        return request
    }

    /// Antall ord som er feilmerket (kun telling, ingen endring).
    static func countMismatched(context: NSManagedObjectContext) -> Int {
        (try? context.count(for: mismatchedRequest())) ?? 0
    }

    /// Retter opp: setter wordType = 0 for alle ord med frekvensrank 1–4000 som var merket som setning (1).
    @discardableResult
    static func fixWordsMismarkedAsSentence(context: NSManagedObjectContext) -> Int {
        guard let words = try? context.fetch(mismatchedRequest()), !words.isEmpty else { return 0 }

        for word in words {
            word.wordType = 0
        }

        do {
            try context.save()
            print("✅ Fikset \(words.count) ord fra wordType=Setning til wordType=Ord (frekvens 1–4000)")
        } catch {
            print("❌ Feil under lagring av wordType-fiks: \(error)")
            return 0
        }
        return words.count
    }
}
