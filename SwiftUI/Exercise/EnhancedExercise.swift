//
//  EnhancedExercise.swift
//  gThai
//
//  Enhanced spaced repetition with learning states and confidence levels
//

import CoreData
import Foundation

enum EnhancedExercise {

    // MARK: - Constants
    private static let InitialEF: Double = 2.30
    private static let MinEF: Double = 1.30
    private static let MaxEF: Double = 2.80

    // Learning intervals (minutes)
    private static let LearningSteps: [Int] = [1, 10, 60, 360] // 1min, 10min, 1h, 6h
    private static let FailureRetryMinutes = 10
    private static let RelearningSteps: [Int] = [10, 60] // Shorter relearning

    // MARK: - Main grading function
    static func grade(word: ThaiWords, confidence: ConfidenceLevel, now: Date = .now) {
        let q = confidence.smQuality
        let wasCorrect = confidence != .blackout

        // Initialize learning state if needed
        if word.learningState == LearningState.new.rawValue {
            word.learningState = LearningState.learning.rawValue
            word.learningStep = 0
        }

        let currentState = LearningState(rawValue: word.learningState) ?? .new

        // Update easiness factor (only for reviews, not learning)
        if currentState == .reviewing {
            updateEasinessFactor(word: word, quality: q)
        }

        // Update statistics
        updateStatistics(word: word, confidence: confidence, now: now)

        // Handle state transitions and scheduling
        handleStateTransition(word: word, confidence: confidence, currentState: currentState, now: now)
    }

    // MARK: - Helper functions
    private static func updateEasinessFactor(word: ThaiWords, quality: Double) {
        var ef = word.easiness == 0 ? InitialEF : word.easiness
        let d = 5.0 - quality
        ef = ef + 0.1 - d * (0.08 + d * 0.02)
        ef = max(MinEF, min(MaxEF, ef))
        word.easiness = ef
    }

    private static func updateStatistics(word: ThaiWords, confidence: ConfidenceLevel, now: Date) {
        // Update review dates
        word.dateOne = word.dateTwo
        word.dateTwo = now
        word.lastReviewedAt = now
        word.modifiedDate = now  // Track last practice time for rotation
        word.lastResult = confidence.rawValue

        if confidence != .blackout {
            word.repetitions += 1
        } else {
            word.lapses += 1
        }
    }

    private static func handleStateTransition(word: ThaiWords, confidence: ConfidenceLevel, currentState: LearningState, now: Date) {
        switch currentState {
        case .new:
            // This shouldn't happen as we set it to learning above
            word.learningState = LearningState.learning.rawValue
            scheduleNextLearning(word: word, confidence: confidence, now: now)

        case .learning:
            if confidence == .blackout {
                // Reset learning
                word.learningStep = 0
                scheduleFailure(word: word, now: now)
            } else {
                // Advance learning
                word.learningStep += 1
                if word.learningStep >= LearningSteps.count {
                    // Graduate to reviewing
                    word.learningState = LearningState.reviewing.rawValue
                    word.repetitions = 1 // Reset for review counting
                    scheduleFirstReview(word: word, now: now)
                } else {
                    scheduleNextLearning(word: word, confidence: confidence, now: now)
                }
            }

        case .reviewing:
            if confidence == .blackout {
                // Back to relearning
                word.learningState = LearningState.relearning.rawValue
                word.learningStep = 0
                word.repetitions = 0
                scheduleFailure(word: word, now: now)
            } else {
                // Continue reviewing with interval
                scheduleNextReview(word: word, confidence: confidence, now: now)
            }

        case .relearning:
            if confidence == .blackout {
                // Reset relearning
                word.learningStep = 0
                scheduleFailure(word: word, now: now)
            } else{
                // Advance relearning
                word.learningStep += 1
                if word.learningStep >= RelearningSteps.count {
                    // Graduate back to reviewing
                    word.learningState = LearningState.reviewing.rawValue
                    scheduleFirstReview(word: word, now: now)
                } else {
                    scheduleNextRelearning(word: word, now: now)
                }
            }
        }
    }

    // MARK: - Scheduling functions
    private static func scheduleFailure(word: ThaiWords, now: Date) {
        word.dueAt = Calendar.current.date(byAdding: .minute, value: FailureRetryMinutes, to: now)
    }

    private static func scheduleCurrentLearningStep(word: ThaiWords, now: Date) {
        let stepIndex = min(Int(word.learningStep), LearningSteps.count - 1)
        let minutes = LearningSteps[stepIndex]
        word.dueAt = Calendar.current.date(byAdding: .minute, value: minutes, to: now)
    }

    private static func scheduleNextLearning(word: ThaiWords, confidence: ConfidenceLevel, now: Date) {
        let stepIndex = min(Int(word.learningStep), LearningSteps.count - 1)
        let minutes = LearningSteps[stepIndex]

        word.dueAt = Calendar.current.date(byAdding: .minute, value: minutes, to: now)
    }

    private static func scheduleCurrentRelearningStep(word: ThaiWords, now: Date) {
        let stepIndex = min(Int(word.learningStep), RelearningSteps.count - 1)
        let minutes = RelearningSteps[stepIndex]
        word.dueAt = Calendar.current.date(byAdding: .minute, value: minutes, to: now)
    }

    private static func scheduleNextRelearning(word: ThaiWords, now: Date) {
        let stepIndex = min(Int(word.learningStep), RelearningSteps.count - 1)
        let minutes = RelearningSteps[stepIndex]
        word.dueAt = Calendar.current.date(byAdding: .minute, value: minutes, to: now)
    }

    private static func scheduleFirstReview(word: ThaiWords, now: Date) {
        // First review after 1 day
        word.dueAt = Calendar.current.date(byAdding: .day, value: 1, to: now)
    }

    private static func scheduleNextReview(word: ThaiWords, confidence: ConfidenceLevel, now: Date) {
        let ef = word.easiness == 0 ? InitialEF : word.easiness

        let baseInterval: Double = {
            switch word.repetitions {
            case 1: return 1.0 // 1 day
            case 2: return 6.0 // 6 days
            default:
                // Calculate from previous interval if possible
                if let dateOne = word.dateOne, let dateTwo = word.dateTwo {
                    let previousInterval = max(1.0, dateTwo.timeIntervalSince(dateOne) / 86_400.0)
                    return previousInterval * ef
                } else {
                    return 6.0 * ef
                }
            }
        }()

        // Adjust interval based on confidence
        let adjustedInterval = baseInterval * confidenceMultiplier(confidence)

        word.dueAt = Calendar.current.date(byAdding: .second,
                                          value: Int(adjustedInterval * 86_400.0),
                                          to: now)
    }

    private static func confidenceMultiplier(_ confidence: ConfidenceLevel) -> Double {
        switch confidence {
        case .blackout: return 0.6    // Reduce interval by 40%
        case .hard: return 0.8        // Reduce interval by 20%
        case .good: return 1.0        // Keep normal interval
        case .easy: return 1.3        // Increase interval by 30%
        }
    }

    // MARK: - Utility functions
    static func isDue(_ word: ThaiWords, at date: Date = .now) -> Bool {
        (word.dueAt ?? .distantPast) <= date
    }

    static func isNew(_ word: ThaiWords) -> Bool {
        word.learningState == LearningState.new.rawValue
    }

    static func learningState(for word: ThaiWords) -> LearningState {
        LearningState(rawValue: word.learningState) ?? .new
    }

    static func nextReviewInterval(for word: ThaiWords) -> String {
        guard let dueAt = word.dueAt else { return "Not scheduled" }

        let now = Date.now
        let interval = dueAt.timeIntervalSince(now)

        if interval <= 0 {
            return "Ready now"
        } else if interval < 3600 { // Less than 1 hour
            let minutes = Int(interval / 60)
            return "\(minutes) min"
        } else if interval < 86400 { // Less than 1 day
            let hours = Int(interval / 3600)
            return "\(hours) hours"
        } else { // Days
            let days = Int(interval / 86400)
            return "\(days) days"
        }
    }
}