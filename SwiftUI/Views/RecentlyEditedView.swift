//
//  RecentlyEditedView.swift
//  gThai
//
//  View for å vise de sist redigerte ordene
//

import SwiftUI
import CoreData

struct RecentlyEditedView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var valgtOrd: ThaiWords?
    @State private var recentWords: [ThaiWords] = []
    @State private var isLoading: Bool = false

    private func loadRecentWords(limit: Int = 50) {
        guard !isLoading else { return }
        isLoading = true
        let t0 = CFAbsoluteTimeGetCurrent()
        let req = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
        req.predicate = NSPredicate(format: "modifiedDate != nil")
        req.sortDescriptors = [NSSortDescriptor(key: #keyPath(ThaiWords.modifiedDate), ascending: false)]
        req.fetchLimit = limit
        do {
            let results = try context.fetch(req)
            let t1 = CFAbsoluteTimeGetCurrent()
            print("⏱ RecentlyEditedView fetch took \(String(format: "%.3f", t1 - t0))s for \(results.count) items (limit=\(limit))")
            self.recentWords = results
        } catch {
            print("❌ RecentlyEditedView fetch error: \(error)")
            self.recentWords = []
        }
        isLoading = false
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.green.opacity(0.9), Color.teal.opacity(0.7), Color.blue.opacity(0.9)]),
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
                            Text("📝 Recently Edited Words")
                                .font(.headline)
                                .foregroundStyle(.white)

                            Text("\(recentWords.count) words")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.9))
                        }

                        Button(action: { loadRecentWords() }) {
                            Image(systemName: isLoading ? "arrow.clockwise" : "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)

                        Spacer()
                    }
                    .padding(.horizontal)

                    // Grid
                    ScrollView {
                        if recentWords.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 80))
                                    .foregroundColor(.white.opacity(0.5))

                                Text("No edited words yet")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)

                                Text("Words you edit in the detail view appear here.")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                        } else {
                            LazyVGrid(columns: columns, spacing: spacing) {
                                ForEach(recentWords, id: \.objectID) { word in
                                    Button {
                                        valgtOrd = word
                                    } label: {
                                        RecentlyEditedGridItem(word: word)
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
        }
        .wireNotifications()
        .onAppear {
            Notifier.shared.hide()
            loadRecentWords()
            // Debug logging
            print("📊 RecentlyEditedView shows \(recentWords.count) words (after fetchLimit)")
        }
    }
}

// MARK: - Recently Edited Grid Item
private struct RecentlyEditedGridItem: View {
    let word: ThaiWords
    @Environment(AppState.self) private var appState

    private var timeSinceModified: String {
        guard let modifiedDate = word.modifiedDate else { return "Unknown" }

        let now = Date()
        let interval = now.timeIntervalSince(modifiedDate)

        if interval < 60 {
            return "Now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) d ago"
        }
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

            // Modified time
            VStack(spacing: 2) {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.green)
                        .font(.caption2)

                    Text(timeSinceModified)
                        .font(.caption2)
                        .foregroundColor(.green)
                }

                // Debug: Vis faktisk modifiedDate
                if let modDate = word.modifiedDate {
                    Text(modDate, style: .time)
                        .font(.caption2)
                        .foregroundColor(.green.opacity(0.7))
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color.green.opacity(0.15))
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
        .shadow(color: .green.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

#Preview("RecentlyEditedView") {
    RecentlyEditedView()
        .environment(AppState())
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
