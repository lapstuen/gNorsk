//
//  EnhancedThaiGridItem.swift
//  gThai
//
//  Enhanced grid item with proper learning flow and confidence grading
//

import SwiftUI

struct EnhancedThaiGridItem: View {
    @Environment(AppState.self) private var appState
    @ObservedObject var word: ThaiWords
    @Binding var moveToPinnedGroup: Bool

    @State private var studyPhase: StudyPhase = .question
    @State private var hasRevealed = false

    enum StudyPhase {
        case question    // Show only image and English
        case revealed    // Show Thai word after user reveals
        case grading     // Show confidence buttons
    }

    private var learningState: LearningState {
        EnhancedExercise.learningState(for: word)
    }

    var body: some View {
        VStack(spacing: 4) {
            // Learning state indicator at top
            LearningStateIndicator(word: word)

            // Main content area
            VStack(spacing: 6) {
                // Image (always visible)
                Image(uiImage: word.uiImage)
                    .resizable()
                    .frame(width: 70, height: 70)
                    .scaledToFill()
                    .clipShape(Circle())
                    .overlay(Circle().stroke(stateColor, lineWidth: 3))
                    .onTapGesture {
                        playAudio()
                    }

                // Content based on study phase
                switch studyPhase {
                case .question:
                    questionPhaseContent

                case .revealed:
                    revealedPhaseContent

                case .grading:
                    gradingPhaseContent
                }
            }

            // Move to pinned group button (if applicable)
            if moveToPinnedGroup {
                moveButton
            }

            Spacer()
        }
        .frame(width: 130, height: moveToPinnedGroup ? 240 : 200)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
                .shadow(radius: 2)
        )
        .onAppear {
            studyPhase = .question
            hasRevealed = false
            moveToPinnedGroup = appState.pinnedGruppeId > 0
        }
    }

    // MARK: - Content Views
    @ViewBuilder
    private var questionPhaseContent: some View {
        // English word (the "question")
        Text(word.englishWord ?? "")
            .font(.caption)
            .lineLimit(2)
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)

        Text(word.sentence ?? "")
            .font(.caption2)
            .lineLimit(1)
            .foregroundStyle(.gray)

        Spacer()

        // Reveal button
        Button {
            withAnimation(.easeIn(duration: 0.2)) {
                studyPhase = .revealed
                hasRevealed = true
            }
            playAudio()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "eye")
                Text("Show")
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

    @ViewBuilder
    private var revealedPhaseContent: some View {
        // Thai word (the "answer")
        Text(word.thaiWord ?? "")
            .font(.title2)
            .fontWeight(.bold)
            .lineLimit(1)
            .foregroundStyle(.black)

        Text(word.englishWord ?? "")
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(.gray)

        Spacer()

        // Grade button
        Button {
            withAnimation(.easeIn(duration: 0.2)) {
                studyPhase = .grading
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
            .background(Color.green)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var gradingPhaseContent: some View {
        // Thai word (still visible)
        Text(word.thaiWord ?? "")
            .font(.title2)
            .fontWeight(.bold)
            .lineLimit(1)
            .foregroundStyle(.black)

        // Confidence buttons
        HStack(spacing: 4) {
            ForEach(ConfidenceLevel.allCases, id: \.self) { level in
                ConfidenceButton(level: level) {
                    gradeWord(level)
                }
            }
        }
    }

    @ViewBuilder
    private var moveButton: some View {
        let tekstGroup = g.getGroupname(groupId: appState.pinnedGruppeId)
        Button("→ \(tekstGroup)") {
            _ = g.updateGroupIdCoreData(id: word.id?.uuidString ?? "", groupId: appState.pinnedGruppeId)
            appState.refreshToken = UUID()
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(4)
    }

    // MARK: - Helper Properties
    private var stateColor: Color {
        switch learningState {
        case .new: return .blue
        case .learning: return .orange
        case .reviewing: return .green
        case .relearning: return .red
        }
    }

    private var backgroundColor: Color {
        word.id == nil ? Color(.white) : Color("CollectionBackground")
    }

    // MARK: - Actions
    private func playAudio() {
        Task {
            do {
                try await CloudTTSTest.testGoogleTTS(word.thaiWord ?? "")
            } catch {
                print("Audio error: \(error)")
                await MainActor.run {
                    Notifier.shared.show(.error, "Google-uttale feilet: \(error.localizedDescription)")
                }
            }
        }
    }

    private func gradeWord(_ confidence: ConfidenceLevel) {
        withAnimation(.easeOut(duration: 0.3)) {
            EnhancedExercise.grade(word: word, confidence: confidence)

            do {
                try word.managedObjectContext?.save()
            } catch {
                print("Save error: \(error)")
            }

            // Reset to question phase for next time
            studyPhase = .question
            hasRevealed = false
        }
    }
}

#Preview("EnhancedThaiGridItem") {
    let context = PersistenceController.preview.container.viewContext

    let word = ThaiWords(context: context)
    word.id = UUID()
    word.thaiWord = "สวัสดี"
    word.englishWord = "Hello"
    word.sentence = "สวัสดีครับ"
    word.learningState = LearningState.learning.rawValue
    word.image = UIImage(systemName: "star.fill")!.jpegData(compressionQuality: 0.8)

    let appState = AppState()
    @State var moveToPinnedGroup = false

    return EnhancedThaiGridItem(word: word, moveToPinnedGroup: $moveToPinnedGroup)
        .environment(appState)
        .environment(\.managedObjectContext, context)
        .padding()
        .background(Color(.systemBackground))
}