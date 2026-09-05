//
//  LearningStateMigration.swift
//  gThai
//
//  Migration helper for initializing learning states on existing words
//

import CoreData
import Foundation

enum LearningStateMigration {

    /// Initializes learning state for all words that don't have it set
    static func migrateExistingWords(context: NSManagedObjectContext) {
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()

        // Find words that need migration (either learningState = 0 or never set)
        request.predicate = NSPredicate(format: "learningState == 0 OR learningState == nil")

        do {
            let wordsToMigrate = try context.fetch(request)
            print("🔄 Migrerer \(wordsToMigrate.count) ord til nytt læringssystem...")

            var migratedCount = 0
            var newCount = 0
            var learningCount = 0
            var reviewingCount = 0

            for word in wordsToMigrate {
                let newState = determineLearningState(for: word)
                word.learningState = newState.rawValue
                word.learningStep = 0 // Reset learning step

                // Initialize other fields if needed
                if word.easiness == 0.0 {
                    word.easiness = 2.30 // Default SM-2 easiness factor
                }

                // Count migrations by type
                switch newState {
                case .new:
                    newCount += 1
                case .learning:
                    learningCount += 1
                case .reviewing:
                    reviewingCount += 1
                case .relearning:
                    // Shouldn't happen in migration, but just in case
                    break
                }

                migratedCount += 1
            }

            try context.save()

            print("✅ Migrering fullført:")
            print("   • Totalt migrert: \(migratedCount)")
            print("   • Nye ord: \(newCount)")
            print("   • Lærer: \(learningCount)")
            print("   • Repeterer: \(reviewingCount)")

        } catch {
            print("❌ Feil under migrering: \(error)")
        }
    }

    /// Determines appropriate learning state based on existing word data
    private static func determineLearningState(for word: ThaiWords) -> LearningState {
        // If word has never been reviewed, it's new
        if word.lastReviewedAt == nil && word.repetitions == 0 {
            return .new
        }

        // If word has few repetitions, it's still learning
        if word.repetitions < 3 {
            return .learning
        }

        // If word has been reviewed multiple times and has a due date in the future, it's reviewing
        if word.repetitions >= 3 {
            return .reviewing
        }

        // Default to new if we can't determine
        return .new
    }

    /// One-time migration check and execution
    static func performMigrationIfNeeded(context: NSManagedObjectContext) {
        let migrationKey = "LearningStateMigrationCompleted"

        if !UserDefaults.standard.bool(forKey: migrationKey) {
            print("🚀 Utfører engangs-migrering til nytt læringssystem...")
            migrateExistingWords(context: context)
            UserDefaults.standard.set(true, forKey: migrationKey)
            print("✅ Migrering merket som fullført")
        } else {
            print("ℹ️ Læringssystem-migrering allerede utført")
        }
    }

    /// Reset all learning progress (for testing or starting fresh)
    static func resetAllLearningProgress(context: NSManagedObjectContext) {
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()

        do {
            let allWords = try context.fetch(request)
            print("🔄 Nullstiller læringsprogresjon for \(allWords.count) ord...")

            for word in allWords {
                word.learningState = LearningState.new.rawValue
                word.learningStep = 0
                word.repetitions = 0
                word.lapses = 0
                word.easiness = 2.30
                word.dueAt = nil
                word.lastReviewedAt = nil
                word.lastResult = 0
            }

            try context.save()
            print("✅ Alle ord tilbakestilt til ny status")

            // Reset migration flag so it can be run again if needed
            UserDefaults.standard.set(false, forKey: "LearningStateMigrationCompleted")

        } catch {
            print("❌ Feil under tilbakestilling: \(error)")
        }
    }

    /// Get learning statistics for current state
    static func getLearningStatistics(context: NSManagedObjectContext) -> LearningStatistics {
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()

        do {
            let allWords = try context.fetch(request)
            var stats = LearningStatistics()

            for word in allWords {
                let state = LearningState(rawValue: word.learningState) ?? .new
                switch state {
                case .new:
                    stats.newWords += 1
                case .learning:
                    stats.learningWords += 1
                case .reviewing:
                    stats.reviewingWords += 1
                case .relearning:
                    stats.relearningWords += 1
                }

                // Count due words
                if EnhancedExercise.isDue(word) {
                    stats.dueWords += 1
                }
            }

            stats.totalWords = allWords.count
            return stats

        } catch {
            print("❌ Feil ved henting av statistikk: \(error)")
            return LearningStatistics()
        }
    }
}

struct LearningStatistics {
    var totalWords = 0
    var newWords = 0
    var learningWords = 0
    var reviewingWords = 0
    var relearningWords = 0
    var dueWords = 0

    var description: String {
        """
        📊 Læringsstatistikk:
        • Totalt: \(totalWords) ord
        • Nye: \(newWords)
        • Lærer: \(learningWords)
        • Repeterer: \(reviewingWords)
        • Gjeninnlærer: \(relearningWords)
        • Klare nå: \(dueWords)
        """
    }
}