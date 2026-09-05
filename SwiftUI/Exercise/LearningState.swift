//
//  LearningState.swift
//  gThai
//
//  Enhanced learning state management for spaced repetition
//

import Foundation

enum LearningState: Int16, CaseIterable {
    case new = 0          // Never studied
    case learning = 1     // Initial learning phase (short intervals)
    case reviewing = 2    // Long-term review phase
    case relearning = 3   // Failed review, back to learning

    var displayName: String {
        switch self {
        case .new: return "New"
        case .learning: return "Learning"
        case .reviewing: return "Reviewing"
        case .relearning: return "Relearning"
        }
    }

    var color: String {
        switch self {
        case .new: return "blue"
        case .learning: return "orange"
        case .reviewing: return "green"
        case .relearning: return "red"
        }
    }

    var meaning: String {
        switch self {
        case .new: return "Never studied"
        case .learning: return "In initial learning phase (short intervals)"
        case .reviewing: return "Long-term review phase"
        case .relearning: return "Failed last review, back to learning"
        }
    }
}

enum ConfidenceLevel: Int16, CaseIterable {
    case blackout = 0     // Helt feil/husket ikke
    case hard = 1         // Vanskelig, nesten feil
    case good = 2         // Riktig med litt anstrengelse
    case easy = 3         // Lett, husket umiddelbart

    var displayName: String {
        switch self {
        case .blackout: return "Wrong"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }

    var smQuality: Double {
        switch self {
        case .blackout: return 1.0
        case .hard: return 2.0
        case .good: return 4.0
        case .easy: return 5.0
        }
    }

    var emoji: String {
        switch self {
        case .blackout: return "❌"
        case .hard: return "😰"
        case .good: return "✅"
        case .easy: return "🚀"
        }
    }
}