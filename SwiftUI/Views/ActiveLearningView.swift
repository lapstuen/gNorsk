//
//  ActiveLearningView.swift
//  gThai
//
//  View for å vise alle ord i aktiv læring (learningState != .new)
//  Uavhengig av gruppe - viser ALT som er startet å lære
//

import SwiftUI
import CoreData

typealias CDGroup = Group

struct ActiveLearningView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var valgtOrd: ThaiWords?
    @State private var showRemoveStarsAlert = false
    @State private var showExerciseFavorites = false
    @State private var refreshID = UUID()
    @State private var filterStars = false
    @State private var wordToMove: ThaiWords?
    @State private var showGroupSelector = false

    @FetchRequest private var activeWords: FetchedResults<ThaiWords>

    // Filtrert liste basert på stjerne-filter
    private var displayedWords: [ThaiWords] {
        if filterStars {
            return activeWords.filter { $0.star }
        } else {
            return Array(activeWords)
        }
    }

    init() {
        // Filtrer på:
        // - Alle ord som er startet å lære (learningState != 0)
        let predicate = NSPredicate(format: "learningState != %d", LearningState.new.rawValue)

        _activeWords = FetchRequest(
            entity: ThaiWords.entity(),
            sortDescriptors: [
                // Sorter først på learningState
                NSSortDescriptor(key: #keyPath(ThaiWords.learningState), ascending: true),
                // Deretter på dueAt (forfallsdato)
                NSSortDescriptor(key: #keyPath(ThaiWords.dueAt), ascending: true),
                // Til slutt alfabetisk
                NSSortDescriptor(key: #keyPath(ThaiWords.thaiWord), ascending: true)
            ],
            predicate: predicate
        )
    }

    var body: some View {
        ZStack {
            // Gradient: Grønn/blå for "læringsliste"
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.green.opacity(0.9),
                    Color.blue.opacity(0.7),
                    Color.cyan.opacity(0.9)
                ]),
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
                            Text("📚 Learning List")
                                .font(.headline)
                                .foregroundStyle(.white)

                            Text("\(displayedWords.count) words")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.9))
                        }

                        Spacer()

                        // Stjerne-filter knapp
                        Button {
                            filterStars.toggle()
                        } label: {
                            Image(systemName: filterStars ? "star.fill" : "star")
                                .font(.title2)
                                .foregroundColor(.yellow)
                                .padding(8)
                                .background(filterStars ? Color.yellow.opacity(0.3) : Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }

                        // Øv favoritter-knapp
                        if activeWords.contains(where: { $0.star }) {
                            Button {
                                showExerciseFavorites = true
                            } label: {
                                Image(systemName: "brain.head.profile")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.blue.opacity(0.6))
                                    .clipShape(Circle())
                            }
                        }

                        // Hamburger menu
                        Menu {
                            Button(role: .destructive) {
                                showRemoveStarsAlert = true
                            } label: {
                                Label("Remove all favorites", systemImage: "star.slash")
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .padding()
                        }
                    }
                    .padding(.horizontal)

                    // Grid
                    ScrollView {
                        if displayedWords.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: filterStars ? "star.slash" : "list.star")
                                    .font(.system(size: 80))
                                    .foregroundColor(.white.opacity(0.5))

                                Text(filterStars ? "No favorites" : "No active learning words")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)

                                Text(filterStars ? "Star words to add them to favorites." : "Start learning words from DetailWordView or GridView.")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                        } else {
                            LazyVGrid(columns: columns, spacing: spacing) {
                                ForEach(displayedWords, id: \.objectID) { word in
                                    Button {
                                        valgtOrd = word
                                    } label: {
                                        ActiveLearningGridItem(word: word)
                                            .environment(appState)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        // Flytt til gruppe
                                        Button {
                                            wordToMove = word
                                            showGroupSelector = true
                                        } label: {
                                            Label("Move to group", systemImage: "folder.fill")
                                        }

                                        Divider()

                                        // Context menu actions
                                        Button(role: .destructive) {
                                            moveToWaitGroup(word: word)
                                        } label: {
                                            Label("Not relevant", systemImage: "clock.badge.xmark")
                                        }

                                        Button {
                                            moveToMasteredGroup(word: word)
                                        } label: {
                                            Label("Already know", systemImage: "checkmark.circle.fill")
                                        }

                                        Divider()

                                        Button {
                                            toggleStar(word: word)
                                        } label: {
                                            Label(word.star ? "Remove favorite" : "Mark as favorite",
                                                  systemImage: word.star ? "star.slash" : "star.fill")
                                        }

                                        Divider()

                                        Button {
                                            valgtOrd = word
                                        } label: {
                                            Label("View details", systemImage: "info.circle")
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .id(refreshID)  // Force grid reload when refreshID changes
            .navigationBarBackButtonHidden(true)
            .sheet(item: $valgtOrd) { word in
                let input = WordInput(from: word)
                DetailWordView(initialWord: input, isNested: false)
                    .environment(appState)
                    .environment(\.managedObjectContext, context)
                    .presentationSizing(.page)
            }
            .alert("Remove all favorites?", isPresented: $showRemoveStarsAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Remove all", role: .destructive) {
                    removeAllStars()
                }
            } message: {
                Text("This will remove the favorite mark from all words in the learning list. The words remain in the list.")
            }
            .fullScreenCover(isPresented: $showExerciseFavorites) {
                ExerciseView(groupId: nil, exerciseType: .favorites)
                    .environment(appState)
                    .environment(\.managedObjectContext, context)
            }
            .sheet(isPresented: $showGroupSelector) {
                SelectGroup(appState: appState) { selectedGroup in
                    if let word = wordToMove {
                        moveToGroup(word: word, targetGroupId: selectedGroup.groupId)
                    }
                }
                .environment(\.managedObjectContext, context)
            }
        }
        .wireNotifications()
        .onAppear {
            Notifier.shared.hide()
            print("📊 ActiveLearningView shows \(activeWords.count) active learning words")
        }
    }

    // MARK: - Helper Functions

    /// Flytter ordet til en spesifikk gruppe
    private func moveToGroup(word: ThaiWords, targetGroupId: Int16) {
        let originalGroupId = word.groupId

        // Ikke gjør noe hvis det allerede er i denne gruppen
        guard originalGroupId != targetGroupId else {
            Notifier.shared.show(.info, "The word is already in this group", duration: 2.0)
            return
        }

        // Move to new group
        word.groupId = targetGroupId

        do {
            try context.save()
            let targetGroupName = g.getGroupname(groupId: targetGroupId)
            print("✅ Moved '\(word.thaiWord ?? "")' to group \(targetGroupId): \(targetGroupName)")
            Notifier.shared.show(.success, "Moved to '\(targetGroupName)'", duration: 2.0)

            // Force grid reload
            refreshID = UUID()
        } catch {
            print("❌ Could not move to group: \(error)")
            Notifier.shared.show(.error, "Error moving: \(error.localizedDescription)", duration: 3.0)
        }
    }

    /// Fjerner alle favoritter (star = false) fra alle ord i læringslisten
    private func removeAllStars() {
        let starredWords = activeWords.filter { $0.star }

        guard !starredWords.isEmpty else {
            Notifier.shared.show(.info, "No favorites to remove", duration: 2.0)
            return
        }

        let count = starredWords.count

        for word in starredWords {
            word.star = false
        }

        do {
            try context.save()
            print("✅ Removed \(count) favorites from the learning list")
            Notifier.shared.show(.success, "Removed \(count) favorites", duration: 2.0)

            // Force grid reload
            refreshID = UUID()
        } catch {
            print("❌ Could not remove favorites: \(error)")
            Notifier.shared.show(.error, "Error removing: \(error.localizedDescription)", duration: 3.0)
        }
    }

    /// Toggle star-verdien for ordet (favoritt/ikke favoritt)
    private func toggleStar(word: ThaiWords) {
        word.star.toggle()

        do {
            try context.save()
            let status = word.star ? "★ Favorite" : "☆ Not favorite"
            print("✅ Updated star for '\(word.thaiWord ?? "")': \(status)")

            Notifier.shared.show(.success, status, duration: 1.5)
        } catch {
            print("❌ Could not update star: \(error)")
            Notifier.shared.show(.error, "Error updating: \(error.localizedDescription)", duration: 3.0)
        }
    }

    /// Flytter ordet til ventegruppe (groupId + 1) og resetter learningState
    private func moveToWaitGroup(word: ThaiWords) {
        let originalGroupId = word.groupId
        let targetGroupId = originalGroupId + 1

        let groupReq: NSFetchRequest<Group> = Group.fetchRequest()
        groupReq.predicate = NSPredicate(format: "groupId == %d", targetGroupId)
        groupReq.fetchLimit = 1
        guard (try? context.fetch(groupReq).first) != nil else {
            print("❌ Waiting group groupId=\(targetGroupId) does not exist — aborting")
            return
        }

        // Reset learning state
        word.learningState = LearningState.new.rawValue
        word.learningStep = 0
        word.dueAt = nil
        word.lastReviewedAt = nil
        word.repetitions = 0
        word.lapses = 0

        // Move to wait group
        word.groupId = targetGroupId

        do {
            try context.save()
            print("✅ Moved '\(word.thaiWord ?? "")' to waiting group \(targetGroupId)")

            // Show feedback
            let targetGroupName = g.getGroupname(groupId: targetGroupId)
            Notifier.shared.show(.info, "Moved to '\(targetGroupName)'", duration: 2.0)
        } catch {
            print("❌ Could not move to waiting group: \(error)")
            Notifier.shared.show(.error, "Error moving: \(error.localizedDescription)", duration: 3.0)
        }
    }

    /// Flytter ordet til "kan allerede"-gruppe (groupId + 2) og resetter learningState
    private func moveToMasteredGroup(word: ThaiWords) {
        let originalGroupId = word.groupId
        let targetGroupId = originalGroupId + 2

        // Reset learning state
        word.learningState = LearningState.new.rawValue
        word.learningStep = 0
        word.dueAt = nil
        word.lastReviewedAt = nil
        word.repetitions = 0
        word.lapses = 0

        // Move to "kan allerede" group
        word.groupId = targetGroupId

        do {
            try context.save()
            print("✅ Moved '\(word.thaiWord ?? "")' to 'already know' group \(targetGroupId)")

            // Show feedback
            let targetGroupName = g.getGroupname(groupId: targetGroupId)
            Notifier.shared.show(.success, "Moved to '\(targetGroupName)' ✅", duration: 2.0)
        } catch {
            print("❌ Could not move to 'already know' group: \(error)")
            Notifier.shared.show(.error, "Error moving: \(error.localizedDescription)", duration: 3.0)
        }
    }
}

// MARK: - Active Learning Grid Item
private struct ActiveLearningGridItem: View {
    let word: ThaiWords
    @Environment(AppState.self) private var appState
    @State private var showThai = false

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

    private var nextReview: String {
        guard let dueAt = word.dueAt else { return "Not scheduled" }

        let now = Date()
        let interval = dueAt.timeIntervalSince(now)

        if interval <= 0 {
            return "Ready now ⏰"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "In \(minutes) min"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "In \(hours) hours"
        } else {
            let days = Int(interval / 86400)
            return "In \(days) days"
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
                // Star indicator
                if word.star {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
            }

            // Image
            Image(uiImage: word.uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 180, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture {
                    if showThai || appState.visAlleDetaljer {
                        // Speak Thai using Google Cloud TTS
                        Task {
                            do {
                                try await CloudTTSTest.testGoogleTTS(word.thaiWord ?? "")
                            } catch {
                                print("error cloud \(error)")
                            }
                        }
                    } else {
                        showThai = true
                        g.talkTh(talkText: word.thaiWord ?? "", rate: 0.5, language: "nb-NO")
                    }
                }

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

            // Next review info
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(learningStateInfo.color)
                    .font(.caption2)

                Text(nextReview)
                    .font(.caption2)
                    .foregroundColor(learningStateInfo.color)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(learningStateInfo.color.opacity(0.15))
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
        .shadow(color: learningStateInfo.color.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

#Preview("ActiveLearningView") {
    ActiveLearningView()
        .environment(AppState())
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
