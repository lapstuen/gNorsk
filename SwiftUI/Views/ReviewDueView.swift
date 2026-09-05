//
//  ReviewDueView.swift
//  gThai
//
//  View for å vise alle ord som forfaller til repetisjon (uavhengig av gruppe)
//

import SwiftUI
import CoreData

struct ReviewDueView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var valgtOrd: ThaiWords?
    @State private var showExerciseMode = false

    @FetchRequest private var dueWords: FetchedResults<ThaiWords>

    init() {
        let now = Date()

        // Filtrer på:
        // 1. Ord som er startet å lære (learningState != 0)
        // 2. Ord som forfaller i dag eller tidligere (dueAt <= now)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "learningState != %d", LearningState.new.rawValue),
            NSPredicate(format: "dueAt != nil AND dueAt <= %@", now as NSDate)
        ])

        _dueWords = FetchRequest(
            entity: ThaiWords.entity(),
            sortDescriptors: [
                NSSortDescriptor(key: #keyPath(ThaiWords.dueAt), ascending: true),
                NSSortDescriptor(key: #keyPath(ThaiWords.thaiWord), ascending: true)
            ],
            predicate: predicate
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.orange.opacity(0.9), Color.red.opacity(0.7), Color.pink.opacity(0.9)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .edgesIgnoringSafeArea(.all)
            .ignoresSafeArea()

            GeometryReader { geo in
                let spacing: CGFloat = 8
                let cardWidth: CGFloat = 200
                let availableWidth = geo.size.width * 0.95
                let numberOfColumns = max(2, Int(availableWidth / (cardWidth + spacing)))
                let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: numberOfColumns)

                VStack(spacing: 10) {
                    // Header
                    HStack {
                        Button("← Back") { dismiss() }
                            .foregroundStyle(.white)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("🔁 Review Due")
                                .font(.headline)
                                .foregroundStyle(.white)

                            Text("\(dueWords.count) words")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.9))
                        }

                        Spacer()

                        // Exercise mode button
                        if !dueWords.isEmpty {
                            Button {
                                showExerciseMode = true
                            } label: {
                                HStack {
                                    Image(systemName: "brain.head.profile")
                                    Text("Practice")
                                }
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green)
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Grid
                    ScrollView {
                        if dueWords.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 80))
                                    .foregroundColor(.green)

                                Text("🎉 No words to review!")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)

                                Text("You're all caught up on reviews.")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                        } else {
                            LazyVGrid(columns: columns, spacing: spacing) {
                                ForEach(dueWords, id: \.objectID) { word in
                                    Button {
                                        valgtOrd = word
                                    } label: {
                                        ReviewDueGridItem(word: word)
                                            .environment(appState)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarBackButtonHidden(true)
            .sheet(item: $valgtOrd) { word in
                let input = WordInput(from: word)
                DetailWordView(initialWord: input, isNested: false)
                    .environment(appState)
                    .environment(\.managedObjectContext, context)
                    .presentationSizing(.page)
            }
            .fullScreenCover(isPresented: $showExerciseMode) {
                // Exercise mode for review
                ExerciseView(groupId: nil, exerciseType: .review)
                    .environment(appState)
                    .environment(\.managedObjectContext, context)
            }
        }
        .wireNotifications()
        .onAppear {
            Notifier.shared.hide()
        }
    }
}

// MARK: - Review Due Grid Item
private struct ReviewDueGridItem: View {
    let word: ThaiWords
    @Environment(AppState.self) private var appState

    private var daysOverdue: Int {
        guard let dueAt = word.dueAt else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: dueAt, to: Date()).day ?? 0
        return max(0, days)
    }

    private var overdueColor: Color {
        if daysOverdue == 0 { return .green }
        if daysOverdue <= 1 { return .yellow }
        if daysOverdue <= 3 { return .orange }
        return .red
    }

    private var learningStateInfo: (text: String, color: Color) {
        let state = EnhancedExercise.learningState(for: word)
        switch state {
        case .new:
            return ("New", .blue)
        case .learning:
            return ("Learning", .orange)
        case .reviewing:
            return ("Reviewing", .green)
        case .relearning:
            return ("Relearning", .red)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Learning state badge
            HStack {
                Circle()
                    .fill(learningStateInfo.color)
                    .frame(width: 8, height: 8)
                Text(learningStateInfo.text)
                    .font(.caption2)
                    .foregroundColor(learningStateInfo.color)
                Spacer()
            }

            // Image
            Image(uiImage: word.uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 180, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Thai word
            if appState.visAlleDetaljer {
                Text(word.thaiWord ?? "")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }

            // English translation
            if appState.visAlleDetaljer {
                Text(word.englishWord ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Due info
            HStack {
                Image(systemName: daysOverdue == 0 ? "clock.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(overdueColor)
                    .font(.caption2)

                if daysOverdue == 0 {
                    Text("Today")
                } else if daysOverdue == 1 {
                    Text("1 day overdue")
                } else {
                    Text("\(daysOverdue) days overdue")
                }
            }
            .font(.caption2)
            .foregroundColor(overdueColor)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(overdueColor.opacity(0.15))
            .cornerRadius(6)

            // Group info
            Text(g.getGroupname(groupId: word.groupId))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: overdueColor.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

#Preview("ReviewDueView") {
    ReviewDueView()
        .environment(AppState())
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
