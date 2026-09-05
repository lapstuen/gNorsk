//
//  Grade.swift
//  gThai
//
//  Created by Geir Lapstuen on 9/7/25.
//



import CoreData
import Foundation
import SwiftData

private let InitialEF: Double = 2.30   // start-easiness
private let MinEF: Double      = 1.30   // nedre grense
private let MaxEF: Double      = 2.80   // øvre grense (valgfritt "tak")
private let WrongRetryMinutes  = 30     // feil → repeter snart

// NOTE: LearningState and ConfidenceLevel are defined in LearningState.swift

enum Exercise {
    // EF' = EF + 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)   // klippes til [MinEF, MaxEF]
    // Kall denne når bruker har trykket på øyne (visning) + deretter 👍/👎
   static func grade(word: ThaiWords, correct: Bool, now: Date = .now) {
        let q = correct ? 4.0 : 2.0
        
        // Start EF om den er 0
        var ef = (word.easiness == 0) ? InitialEF : word.easiness
        
        // SM-2 EF-oppdatering (klippes til [MinEF, MaxEF])
        let d = 5.0 - q
        ef = ef + 0.1 - d * (0.08 + d * 0.02)
        ef = max(MinEF, min(MaxEF, ef))
        word.easiness = ef
        
        // Oppdater repetisjoner / lapses
        if correct {
            word.repetitions += 1
        } else {
            word.repetitions = 0
            word.lapses += 1
        }
        
        // Flytt siste to tidsstempler (nyttig til diagnose & intervall)
        word.dateOne = word.dateTwo
        word.dateTwo = now
        
        // Intervallberegning
        let intervalDays: Double = {
            if !correct { return (Double(WrongRetryMinutes) / 144.0) }  // 30 min
            switch word.repetitions {
            case 1: return 1                                     // 1. gang riktig
            case 2: return 6                                     // 2. gang riktig
            default:
                // Bruk sist kjente faktiske intervall hvis vi har to stempler
                if let a = word.dateOne, let b = word.dateTwo {
                    let days = max(1.0, b.timeIntervalSince(a) / 86_400.0)
                    return days * ef
                } else {
                    return 6 * ef                                // fallback
                }
            }
        }()
        
        word.lastReviewedAt = now
        word.lastResult = correct ? 1 : 0
        
        // Sett neste forfall
        if correct {
            word.dueAt = Calendar.current.date(byAdding: .second,
                                               value: Int(intervalDays * 86_400.0),
                                               to: now)
        } else {
            word.dueAt = Calendar.current.date(byAdding: .minute,
                                               value: WrongRetryMinutes,
                                               to: now)
        }
    }
    
    // Hjelper for "er dette kortet klart til repetisjon nå?"
    static func isDue(_ word: ThaiWords, at date: Date = .now) -> Bool {
        (word.dueAt ?? .distantPast) <= date
    }

    // MARK: - Enhanced Learning System

    // Learning intervals (minutes)
    private static let LearningSteps: [Int] = [1, 10, 60, 360] // 1min, 10min, 1h, 6h
    private static let FailureRetryMinutes = 10
    private static let RelearningSteps: [Int] = [10, 60] // Shorter relearning

    // Enhanced grading with confidence levels
    static func gradeEnhanced(word: ThaiWords, confidence: ConfidenceLevel, now: Date = .now) {
        let q = confidence.smQuality
        let wasCorrect = confidence != .blackout

        // Check if Core Data model has been updated with new properties
        if !word.hasEnhancedLearningProperties {
            // Fallback to original grading for now
            grade(word: word, correct: wasCorrect, now: now)
            return
        }

        // Initialize learning state if needed
        if word.safeLearningState == LearningState.new.rawValue {
            word.safeLearningState = LearningState.learning.rawValue
            word.safeLearningStep = 0
        }

        let currentState = LearningState(rawValue: word.safeLearningState) ?? .new

        // Update easiness factor (only for reviews, not learning)
        if currentState == .reviewing {
            updateEasinessFactor(word: word, quality: q)
        }

        // Update statistics
        updateStatistics(word: word, confidence: confidence, now: now)

        // Handle state transitions and scheduling
        handleStateTransition(word: word, confidence: confidence, currentState: currentState, now: now)
    }

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
            word.safeLearningState = LearningState.learning.rawValue
            scheduleNextLearning(word: word, confidence: confidence, now: now)

        case .learning:
            if confidence == .blackout {
                word.safeLearningStep = 0
                scheduleFailure(word: word, now: now)
            } else {
                word.safeLearningStep += 1
                if word.safeLearningStep >= LearningSteps.count {
                    word.safeLearningState = LearningState.reviewing.rawValue
                    word.repetitions = 1
                    scheduleFirstReview(word: word, now: now)
                } else {
                    scheduleNextLearning(word: word, confidence: confidence, now: now)
                }
            }

        case .reviewing:
            if confidence == .blackout {
                word.safeLearningState = LearningState.relearning.rawValue
                word.safeLearningStep = 0
                word.repetitions = 0
                scheduleFailure(word: word, now: now)
            } else {
                scheduleNextReview(word: word, confidence: confidence, now: now)
            }

        case .relearning:
            if confidence == .blackout {
                word.safeLearningStep = 0
                scheduleFailure(word: word, now: now)
            } else {
                word.safeLearningStep += 1
                if word.safeLearningStep >= RelearningSteps.count {
                    word.safeLearningState = LearningState.reviewing.rawValue
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
        let stepIndex = min(Int(word.safeLearningStep), LearningSteps.count - 1)
        let minutes = LearningSteps[stepIndex]
        word.dueAt = Calendar.current.date(byAdding: .minute, value: minutes, to: now)
    }

    private static func scheduleNextLearning(word: ThaiWords, confidence: ConfidenceLevel, now: Date) {
        let stepIndex = min(Int(word.safeLearningStep), LearningSteps.count - 1)
        let minutes = LearningSteps[stepIndex]

        word.dueAt = Calendar.current.date(byAdding: .minute, value: minutes, to: now)
    }

    private static func scheduleCurrentRelearningStep(word: ThaiWords, now: Date) {
        let stepIndex = min(Int(word.safeLearningStep), RelearningSteps.count - 1)
        let minutes = RelearningSteps[stepIndex]
        word.dueAt = Calendar.current.date(byAdding: .minute, value: minutes, to: now)
    }

    private static func scheduleNextRelearning(word: ThaiWords, now: Date) {
        let stepIndex = min(Int(word.safeLearningStep), RelearningSteps.count - 1)
        let minutes = RelearningSteps[stepIndex]
        word.dueAt = Calendar.current.date(byAdding: .minute, value: minutes, to: now)
    }

    private static func scheduleFirstReview(word: ThaiWords, now: Date) {
        word.dueAt = Calendar.current.date(byAdding: .day, value: 1, to: now)
    }

    private static func scheduleNextReview(word: ThaiWords, confidence: ConfidenceLevel, now: Date) {
        let ef = word.easiness == 0 ? InitialEF : word.easiness

        let baseInterval: Double = {
            switch word.repetitions {
            case 1: return 1.0
            case 2: return 6.0
            default:
                if let dateOne = word.dateOne, let dateTwo = word.dateTwo {
                    let previousInterval = max(1.0, dateTwo.timeIntervalSince(dateOne) / 86_400.0)
                    return previousInterval * ef
                } else {
                    return 6.0 * ef
                }
            }
        }()

        let adjustedInterval = baseInterval * confidenceMultiplier(confidence)

        word.dueAt = Calendar.current.date(byAdding: .second,
                                          value: Int(adjustedInterval * 86_400.0),
                                          to: now)
    }

    private static func confidenceMultiplier(_ confidence: ConfidenceLevel) -> Double {
        switch confidence {
        case .blackout: return 0.6
        case .hard: return 0.8
        case .good: return 1.0
        case .easy: return 1.3
        }
    }

    // MARK: - Utility functions
    static func isNew(_ word: ThaiWords) -> Bool {
        // Safe access with fallback
        if word.hasEnhancedLearningProperties {
            return word.safeLearningState == LearningState.new.rawValue
        } else {
            return word.lastReviewedAt == nil && word.repetitions == 0
        }
    }

    static func learningState(for word: ThaiWords) -> LearningState {
        // Safe access with fallback for when Core Data model isn't updated yet
        if word.hasEnhancedLearningProperties {
            return LearningState(rawValue: word.safeLearningState) ?? .new
        } else {
            // Fallback logic based on existing data
            if word.lastReviewedAt == nil && word.repetitions == 0 {
                return .new
            } else if word.repetitions < 3 {
                return .learning
            } else {
                return .reviewing
            }
        }
    }

    static func nextReviewInterval(for word: ThaiWords) -> String {
        guard let dueAt = word.dueAt else { return "Not scheduled" }

        let now = Date.now
        let interval = dueAt.timeIntervalSince(now)

        if interval <= 0 {
            return "Ready now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hours"
        } else {
            let days = Int(interval / 86400)
            return "\(days) days"
        }
    }
}
