import CoreData
import Foundation

extension SearchHistoryEntry {
    static let maxHistoryItems = 50

    static func normalizedSearchText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func upsert(searchText: String, in context: NSManagedObjectContext, usedAt: Date = Date()) {
        let trimmed = normalizedSearchText(searchText)
        guard !trimmed.isEmpty else { return }

        let request: NSFetchRequest<SearchHistoryEntry> = SearchHistoryEntry.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "searchText ==[cd] %@", trimmed)

        let entry = (try? context.fetch(request))?.first ?? SearchHistoryEntry(context: context)
        if entry.id == nil {
            entry.id = UUID()
        }
        entry.searchText = trimmed
        entry.usedAt = usedAt

        pruneIfNeeded(in: context)
        save(context: context)
    }

    static func deleteAll(in context: NSManagedObjectContext) {
        let request: NSFetchRequest<SearchHistoryEntry> = SearchHistoryEntry.fetchRequest()
        guard let entries = try? context.fetch(request), !entries.isEmpty else { return }

        for entry in entries {
            context.delete(entry)
        }

        save(context: context)
    }

    static func pruneIfNeeded(in context: NSManagedObjectContext) {
        let request: NSFetchRequest<SearchHistoryEntry> = SearchHistoryEntry.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "usedAt", ascending: false)]

        guard let entries = try? context.fetch(request), entries.count > maxHistoryItems else { return }

        for entry in entries.dropFirst(maxHistoryItems) {
            context.delete(entry)
        }
        save(context: context)
    }

    private static func save(context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("❌ Kunne ikke lagre søkehistorikk: \(error)")
        }
    }
}
