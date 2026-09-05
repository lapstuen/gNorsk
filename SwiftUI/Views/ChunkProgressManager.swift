//
//  ChunkProgressManager.swift
//  gThai
//
//  Manages chunked learning progress and persistence
//

import Foundation
import CoreData

class ChunkProgressManager {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Chunk Progress Tracking

    /// Gets the current chunk for a group, considering date-based review cycles
    func getCurrentChunk(for groupId: Int16, chunkSize: Int = 10) -> Int {
        let progress = getOrCreateGroupProgress(for: groupId)
        let now = Date()

        // Check if we should reset chunks based on date
        if shouldResetChunks(progress: progress, now: now) {
            resetGroupProgress(progress)
            return 0
        }

        return Int(progress.currentChunk)
    }

    /// Marks a chunk as completed and advances to next chunk
    func completeChunk(for groupId: Int16, chunkIndex: Int) -> Bool {
        let progress = getOrCreateGroupProgress(for: groupId)

        // Add to completed chunks
        var completedChunks = getCompletedChunks(from: progress.completedChunks)
        completedChunks.insert(chunkIndex)
        progress.completedChunks = setToString(completedChunks)

        // Advance current chunk
        progress.currentChunk = Int16(chunkIndex + 1)
        progress.lastActivity = Date()

        // Check if all chunks are completed
        let totalWords = getTotalWordsForGroup(groupId)
        let totalChunks = (totalWords + 9) / 10 // Ceiling division for chunks of 10

        if completedChunks.count >= totalChunks {
            // All chunks completed - set up for review cycle
            progress.lastCompleteDate = Date()
            progress.reviewCycle += 1
            progress.currentChunk = 0
            progress.completedChunks = ""

            saveContext()
            return true // Entire group completed
        }

        saveContext()
        return false // More chunks remaining
    }

    /// Gets completed chunks for a group
    func getCompletedChunks(for groupId: Int16) -> Set<Int> {
        let progress = getOrCreateGroupProgress(for: groupId)
        return getCompletedChunks(from: progress.completedChunks)
    }

    /// Gets words for current chunk
    func getWordsForChunk(groupId: Int16, chunkIndex: Int, chunkSize: Int = 10) -> [ThaiWords] {
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()

        // Filter by group
        var predicates: [NSPredicate] = []
        predicates.append(NSPredicate(format: "groupId == %d", groupId))

        // Add learning state filters (new words, due reviews, etc.)
        let now = Date()
        let newPredicate = NSPredicate(format: "learningState == %d", LearningState.new.rawValue)
        let duePredicate = NSPredicate(format: "dueAt == nil OR dueAt <= %@", now as NSDate)
        predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [newPredicate, duePredicate]))

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(ThaiWords.learningState), ascending: true),
            NSSortDescriptor(key: #keyPath(ThaiWords.dueAt), ascending: true),
            NSSortDescriptor(key: #keyPath(ThaiWords.frequencyRank), ascending: true),
            NSSortDescriptor(key: #keyPath(ThaiWords.insertDate), ascending: true)
        ]

        do {
            let allWords = try context.fetch(request)
            let startIndex = chunkIndex * chunkSize
            let endIndex = min(startIndex + chunkSize, allWords.count)

            guard startIndex < allWords.count else { return [] }

            return Array(allWords[startIndex..<endIndex])
        } catch {
            print("Error fetching words for chunk: \(error)")
            return []
        }
    }

    /// Gets statistics for a group's learning progress
    func getGroupStats(for groupId: Int16) -> GroupLearningStats {
        let progress = getOrCreateGroupProgress(for: groupId)
        let totalWords = getTotalWordsForGroup(groupId)
        let completedChunks = getCompletedChunks(from: progress.completedChunks)

        return GroupLearningStats(
            groupId: groupId,
            totalWords: totalWords,
            currentChunk: Int(progress.currentChunk),
            completedChunks: completedChunks.count,
            reviewCycle: Int(progress.reviewCycle),
            lastCompleteDate: progress.lastCompleteDate,
            nextReviewDate: calculateNextReviewDate(for: progress)
        )
    }

    // MARK: - Private Helper Methods

    private func getOrCreateGroupProgress(for groupId: Int16) -> GroupProgress {
        let request: NSFetchRequest<GroupProgress> = GroupProgress.fetchRequest()
        request.predicate = NSPredicate(format: "groupId == %d", groupId)
        request.fetchLimit = 1

        do {
            if let existing = try context.fetch(request).first {
                return existing
            }
        } catch {
            print("Error fetching group progress: \(error)")
        }

        // Create new progress
        let progress = GroupProgress(context: context)
        progress.groupId = groupId
        progress.currentChunk = 0
        progress.completedChunks = ""
        progress.reviewCycle = 0
        progress.lastActivity = Date()

        saveContext()
        return progress
    }

    private func getTotalWordsForGroup(_ groupId: Int16) -> Int {
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(format: "groupId == %d", groupId)

        do {
            return try context.count(for: request)
        } catch {
            print("Error counting words for group: \(error)")
            return 0
        }
    }

    private func shouldResetChunks(progress: GroupProgress, now: Date) -> Bool {
        guard let lastComplete = progress.lastCompleteDate else { return false }

        // Calculate review interval based on review cycle
        let reviewInterval: TimeInterval = {
            switch progress.reviewCycle {
            case 0: return 0 // First time through
            case 1: return 24 * 60 * 60 // 1 day
            case 2: return 3 * 24 * 60 * 60 // 3 days
            case 3: return 7 * 24 * 60 * 60 // 1 week
            case 4: return 14 * 24 * 60 * 60 // 2 weeks
            default: return 30 * 24 * 60 * 60 // 1 month
            }
        }()

        return now.timeIntervalSince(lastComplete) >= reviewInterval
    }

    private func calculateNextReviewDate(for progress: GroupProgress) -> Date? {
        guard let lastComplete = progress.lastCompleteDate else { return nil }

        let reviewInterval: TimeInterval = {
            switch progress.reviewCycle {
            case 1: return 24 * 60 * 60 // 1 day
            case 2: return 3 * 24 * 60 * 60 // 3 days
            case 3: return 7 * 24 * 60 * 60 // 1 week
            case 4: return 14 * 24 * 60 * 60 // 2 weeks
            default: return 30 * 24 * 60 * 60 // 1 month
            }
        }()

        return lastComplete.addingTimeInterval(reviewInterval)
    }

    private func resetGroupProgress(_ progress: GroupProgress) {
        progress.currentChunk = 0
        progress.completedChunks = ""
        progress.lastActivity = Date()
    }

    private func getCompletedChunks(from string: String?) -> Set<Int> {
        guard let string = string, !string.isEmpty else { return Set<Int>() }

        let components = string.components(separatedBy: ",")
        var chunks = Set<Int>()

        for component in components {
            if let chunkIndex = Int(component.trimmingCharacters(in: .whitespaces)) {
                chunks.insert(chunkIndex)
            }
        }

        return chunks
    }

    private func setToString(_ set: Set<Int>) -> String {
        return set.map(String.init).joined(separator: ",")
    }

    private func saveContext() {
        guard context.hasChanges else { return }

        do {
            try context.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }
}

// MARK: - Supporting Types

struct GroupLearningStats {
    let groupId: Int16
    let totalWords: Int
    let currentChunk: Int
    let completedChunks: Int
    let reviewCycle: Int
    let lastCompleteDate: Date?
    let nextReviewDate: Date?

    var totalChunks: Int {
        (totalWords + 9) / 10 // Ceiling division
    }

    var progress: Double {
        guard totalChunks > 0 else { return 0 }
        return Double(completedChunks) / Double(totalChunks)
    }

    var isCompleted: Bool {
        completedChunks >= totalChunks
    }

    var needsReview: Bool {
        guard let nextReview = nextReviewDate else { return false }
        return Date() >= nextReview
    }
}

// MARK: - Core Data Entity (you'll need to add this to your .xcdatamodeld file)

/*
 Add this entity to your Core Data model:

 Entity Name: GroupProgress
 Attributes:
 - groupId: Int16
 - currentChunk: Int16 (default: 0)
 - completedChunks: String (default: "")
 - reviewCycle: Int16 (default: 0)
 - lastActivity: Date
 - lastCompleteDate: Date (optional)
 */