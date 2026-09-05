//
//  NLPDataImporter.swift
//  gThai
//
//  Import NLP data from thai_complete.json into Core Data
//  ONE-TIME operation to populate syllables and IPA fields
//

import Foundation
import CoreData

enum NLPDataImporter {

    // MARK: - Import from thai_complete.json

    /// Import syllables and IPA from thai_complete.json into Core Data
    ///
    /// This is a ONE-TIME operation. After running this:
    /// 1. All words get syllables + IPA from PyThaiNLP
    /// 2. Delete thai_complete.json (no longer needed)
    /// 3. App uses Core Data for all lookups
    ///
    /// Usage:
    /// ```swift
    /// let result = NLPDataImporter.importFromThaiComplete(context: viewContext)
    /// print("✅ Updated \(result.updated) words")
    /// ```
    static func importFromThaiComplete(
        context: NSManagedObjectContext,
        dryRun: Bool = false
    ) -> (updated: Int, created: Int, skipped: Int, errors: Int) {

        print("🚀 Starting NLP data import from thai_complete.json...")
        if dryRun {
            print("   ⚠️ DRY RUN MODE - no changes will be saved")
        }

        // Load JSON file from bundle
        guard let url = Bundle.main.url(forResource: "thai_complete", withExtension: "json") else {
            print("❌ thai_complete.json not found in bundle!")
            print("   Make sure you have:")
            print("   1. Exported words: ThaiWordsExporter.exportAllWords()")
            print("   2. Generated data: python3 generate_thai_data.py")
            print("   3. Added thai_complete.json to Xcode project")
            return (0, 0, 0, 1)
        }

        // Parse JSON
        let entries: [NLPEntry]
        do {
            let data = try Data(contentsOf: url)
            entries = try JSONDecoder().decode([NLPEntry].self, from: data)
            print("✅ Loaded \(entries.count) entries from thai_complete.json")
        } catch {
            print("❌ Failed to parse thai_complete.json: \(error)")
            return (0, 0, 0, 1)
        }

        // Process each entry
        var stats = (updated: 0, created: 0, skipped: 0, errors: 0)

        for (index, entry) in entries.enumerated() {
            if index % 100 == 0 {
                print("📊 Processing \(index)/\(entries.count)...")
            }

            // Find or create word in Core Data
            let word = fetchOrCreateWord(entry.text, context: context)

            if word == nil {
                print("❌ Failed to create word: \(entry.text)")
                stats.errors += 1
                continue
            }

            guard let word = word else { continue }

            // Check if word already has NLP data
            let alreadyHasData = word.hasSyllables && word.ipa != nil && word.ipa != "—"

            if alreadyHasData {
                stats.skipped += 1
                continue
            }

            // Update NLP data
            let ipa = entry.ipa == "⚠️ Mangler IPA" ? nil : entry.ipa
            word.updateNLPData(
                syllables: entry.syllables,
                ipa: ipa,
                source: entry.engine ?? "PyThaiNLP"
            )

            if word.insertDate == nil {
                stats.created += 1
            } else {
                stats.updated += 1
            }
        }

        // Save to Core Data
        if !dryRun {
            do {
                try context.save()
                print("💾 Saved \(stats.updated + stats.created) words to Core Data")
            } catch {
                print("❌ Failed to save Core Data: \(error)")
                stats.errors += 1
            }
        }

        // Print summary
        print("\n" + String(repeating: "=", count: 60))
        print("📊 NLP DATA IMPORT COMPLETE")
        print(String(repeating: "=", count: 60))
        print("Total entries processed: \(entries.count)")
        print("  ✅ Updated existing words: \(stats.updated)")
        print("  ✨ Created new words: \(stats.created)")
        print("  ⏭️  Skipped (already have data): \(stats.skipped)")
        print("  ❌ Errors: \(stats.errors)")
        print(String(repeating: "=", count: 60))

        if !dryRun {
            print("\n✅ Done! You can now delete thai_complete.json")
            print("   App will use Core Data for all NLP lookups")
        }

        return stats
    }

    // MARK: - Helper Functions

    /// Find existing word or create new one
    private static func fetchOrCreateWord(
        _ text: String,
        context: NSManagedObjectContext
    ) -> ThaiWords? {

        // Try to find existing word
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(format: "thaiWord == %@", text)
        request.fetchLimit = 1

        do {
            if let existing = try context.fetch(request).first {
                return existing
            }
        } catch {
            print("⚠️ Error fetching word '\(text)': \(error)")
        }

        // Create new word
        let newWord = ThaiWords(context: context)
        newWord.thaiWord = text
        newWord.id = UUID()
        newWord.insertDate = Date()
        newWord.groupId = 0  // Default group
        newWord.star = false
        newWord.easiness = 2.5  // Default SM-2 easiness

        return newWord
    }

    // MARK: - Data Models

    private struct NLPEntry: Codable {
        let text: String
        let syllables: [String]
        let ipa: String
        let engine: String?
        let syllables_match: Bool?

        enum CodingKeys: String, CodingKey {
            case text
            case syllables
            case ipa
            case engine
            case syllables_match
        }
    }
}

// MARK: - Migration

extension NLPDataImporter {

    /// Migrate NLP metadata from tags to notes field
    /// Run this ONCE to move existing data
    static func migrateTagsToNotes(context: NSManagedObjectContext) -> Int {
        print("🔄 Migrating NLP metadata from tags → notes...")

        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(format: "tags CONTAINS[c] 'nlp_source:'")

        var migrated = 0

        do {
            let words = try context.fetch(request)
            print("   Found \(words.count) words with old NLP data in tags")

            for word in words {
                guard let tags = word.tags else { continue }

                // Extract nlp_source
                var source: String?
                var updatedAt: Date?

                let components = tags.components(separatedBy: "|")
                var remainingTags: [String] = []

                for component in components {
                    if component.hasPrefix("nlp_source:") {
                        source = component.replacingOccurrences(of: "nlp_source:", with: "")
                    } else if component.hasPrefix("updated:") {
                        let dateString = component.replacingOccurrences(of: "updated:", with: "")
                        let formatter = ISO8601DateFormatter()
                        updatedAt = formatter.date(from: dateString)
                    } else {
                        // Keep non-NLP tags
                        remainingTags.append(component)
                    }
                }

                // Move to notes field
                if let source = source {
                    word.nlpSource = source
                    word.nlpUpdatedAt = updatedAt
                    migrated += 1
                }

                // Clean tags field (remove NLP metadata)
                word.tags = remainingTags.isEmpty ? nil : remainingTags.joined(separator: "|")
            }

            try context.save()
            print("✅ Migrated \(migrated) words")

        } catch {
            print("❌ Migration error: \(error)")
        }

        return migrated
    }
}

// MARK: - Statistics and Diagnostics

extension NLPDataImporter {

    /// Get NLP data coverage statistics
    static func getStatistics(context: NSManagedObjectContext) -> String {
        let stats = ThaiWords.getNLPStatistics(context: context)

        let syllablePercent = stats.total > 0 ? (Double(stats.withSyllables) / Double(stats.total) * 100) : 0
        let ipaPercent = stats.total > 0 ? (Double(stats.withIPA) / Double(stats.total) * 100) : 0
        let completePercent = stats.total > 0 ? (Double(stats.complete) / Double(stats.total) * 100) : 0

        var result = """
        📊 NLP DATA STATISTICS
        ══════════════════════════════════════
        Total Thai words:       \(stats.total)

        With syllables:         \(stats.withSyllables) (\(String(format: "%.1f", syllablePercent))%)
        With IPA:               \(stats.withIPA) (\(String(format: "%.1f", ipaPercent))%)
        Complete (both):        \(stats.complete) (\(String(format: "%.1f", completePercent))%)

        Missing data:           \(stats.total - stats.complete)
        ══════════════════════════════════════
        """

        return result
    }

    /// Find words that need NLP data
    static func diagnose(context: NSManagedObjectContext, limit: Int = 10) {
        let wordsNeedingUpdate = ThaiWords.fetchWordsNeedingNLPUpdate(context: context)

        print("\n🔍 WORDS NEEDING NLP DATA UPDATE")
        print(String(repeating: "=", count: 60))
        print("Found \(wordsNeedingUpdate.count) words without complete NLP data")
        print("\nFirst \(min(limit, wordsNeedingUpdate.count)) examples:")

        for (index, word) in wordsNeedingUpdate.prefix(limit).enumerated() {
            let thai = word.thaiWord ?? "???"
            let hasSyl = word.hasSyllables ? "✅" : "❌"
            let hasIPA = (word.ipa != nil && word.ipa != "—") ? "✅" : "❌"

            print("  \(index + 1). \(thai)")
            print("      Syllables: \(hasSyl)  IPA: \(hasIPA)")
        }

        print(String(repeating: "=", count: 60))
    }
}
