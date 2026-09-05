//
//  InitializeLearningState.swift
//  gThai
//
//  Initialiserer learningState for alle eksisterende ord
//

import CoreData
import Foundation

enum InitializeLearningState {

    /// Setter learningState basert på eksisterende data
    static func migrateAllWords(context: NSManagedObjectContext) {
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()

        do {
            let allWords = try context.fetch(request)
            var migratedCount = 0

            for word in allWords {
                // Hvis ordet har dueAt eller lastReviewedAt, anser vi det som startet
                if word.dueAt != nil || word.lastReviewedAt != nil || word.repetitions > 0 {
                    // Allerede startet - sett til learning eller reviewing basert på repetitions
                    if word.repetitions >= 3 {
                        word.learningState = LearningState.reviewing.rawValue
                    } else if word.repetitions > 0 {
                        word.learningState = LearningState.learning.rawValue
                    } else {
                        word.learningState = LearningState.learning.rawValue
                    }
                    migratedCount += 1
                } else {
                    // Nytt ord - sett til new
                    word.learningState = LearningState.new.rawValue
                }
            }

            try context.save()
            print("✅ Migrert \(migratedCount) av \(allWords.count) ord til riktig learningState")

        } catch {
            print("❌ Feil under migrering av learningState: \(error)")
        }
    }

    /// Setter ALLE ord til new state (reset)
    static func resetAllToNew(context: NSManagedObjectContext) {
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()

        do {
            let allWords = try context.fetch(request)

            for word in allWords {
                word.learningState = LearningState.new.rawValue
                word.learningStep = 0
                word.dueAt = nil
                word.lastReviewedAt = nil
            }

            try context.save()
            print("✅ Resatt \(allWords.count) ord til new state")

        } catch {
            print("❌ Feil under reset: \(error)")
        }
    }

    /// Initialiserer modifiedDate for alle ord som mangler den
    static func initializeModifiedDate(context: NSManagedObjectContext) {
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()

        do {
            let allWords = try context.fetch(request)
            var updatedCount = 0

            for word in allWords {
                // Hvis modifiedDate er nil, sett den til insertDate (eller Date() hvis insertDate også er nil)
                if word.modifiedDate == nil {
                    word.modifiedDate = word.insertDate ?? Date()
                    updatedCount += 1
                }
            }

            try context.save()
            print("✅ Initialisert modifiedDate for \(updatedCount) av \(allWords.count) ord")

        } catch {
            print("❌ Feil under initialisering av modifiedDate: \(error)")
        }
    }
}
