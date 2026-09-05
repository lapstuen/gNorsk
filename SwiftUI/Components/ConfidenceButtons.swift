//
//  ConfidenceButtons.swift
//  gThai
//
//  Confidence-based grading buttons for enhanced learning
//

import SwiftUI

struct ConfidenceButtons: View {
    let word: ThaiWords
    let onGrade: (ConfidenceLevel) -> Void

    @State private var showingButtons = false

    var body: some View {
        VStack(spacing: 4) {
            if showingButtons {
                // Show confidence level buttons
                HStack(spacing: 8) {
                    ForEach(ConfidenceLevel.allCases, id: \.self) { level in
                        ConfidenceButton(level: level) {
                            onGrade(level)
                            showingButtons = false
                        }
                    }
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                // Show "Grade" button
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showingButtons = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.head.profile")
                        Text("Grade")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(response: 0.3), value: showingButtons)
    }
}

struct ConfidenceButton: View {
    let level: ConfidenceLevel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(level.emoji)
                    .font(.system(size: 16))
                Text(level.displayName)
                    .font(.system(size: 8))
                    .lineLimit(1)
            }
            .frame(width: 50, height: 36)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch level {
        case .wrong: return .red
        case .correct: return .green
        }
    }
}

struct LearningStateIndicator: View {
    let word: ThaiWords

    private var learningState: LearningState {
        EnhancedExercise.learningState(for: word)
    }

    private var nextReview: String {
        EnhancedExercise.nextReviewInterval(for: word)
    }

    var body: some View {
        VStack(spacing: 2) {
            // Learning state dot
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)

            // Next review time
            Text(nextReview)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var stateColor: Color {
        switch learningState {
        case .new: return .blue
        case .learning: return .orange
        case .reviewing: return .green
        case .relearning: return .red
        }
    }
}

#Preview("ConfidenceButtons") {
    let context = PersistenceController.preview.container.viewContext
    let word = ThaiWords(context: context)
    word.thaiWord = "สวัสดี"

    return VStack(spacing: 20) {
        ConfidenceButtons(word: word) { level in
            print("Graded: \(level.displayName)")
        }

        LearningStateIndicator(word: word)
    }
    .padding()
}