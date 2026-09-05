import Foundation
import CoreData

struct ThaiWordsCleanup {
    struct Entry {
        let objectID: NSManagedObjectID
        let thaiWord: String
    }

    static func isValidEnglish(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "—" else { return false }
        let firstGloss = trimmed
            .components(separatedBy: ";")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !firstGloss.isEmpty && firstGloss != "—"
    }

    static func findEntriesWithoutValidEnglish(context: NSManagedObjectContext) -> [Entry] {
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.returnsObjectsAsFaults = false

        do {
            let all = try context.fetch(request)
            let bad = all.filter { word in
                !isValidEnglish(word.englishWord)
            }
            print("🧹 Found \(bad.count) entries without valid English")
            return bad.compactMap { w in
                let thai = w.thaiWord ?? ""
                return Entry(objectID: w.objectID, thaiWord: thai)
            }
        } catch {
            print("❌ Cleanup scan failed: \(error)")
            return []
        }
    }

    static func deleteEntries(_ entries: [Entry], context: NSManagedObjectContext) {
        guard !entries.isEmpty else { return }
        do {
            for entry in entries {
                if let obj = try? context.existingObject(with: entry.objectID) {
                    context.delete(obj)
                }
            }
            try context.save()
            print("🧹 Deleted \(entries.count) entries without valid English")
        } catch {
            print("❌ Cleanup delete failed: \(error)")
        }
    }
}
