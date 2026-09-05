//
//  WiktionaryFrequencyReportView.swift
//  gThai
//

import SwiftUI
import CoreData
import UIKit

private struct WiktionaryReportRow: Identifiable {
    let id = UUID()
    let thaiWord: String
    let frequencyRank: Int32?
    let thaiWordObject: ThaiWords?
}

struct WiktionaryFrequencyReportView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var threshold: Double = 600
    @State private var allWords: [String] = []
    @State private var objectByWord: [String: ThaiWords] = [:]
    @State private var selectedWord: ThaiWords?

    // Diagnostikk: bytter farge hver gang refreshFromDatabase() faktisk kjører,
    // slik at man visuelt kan se om/når den kalles.
    @State private var refreshColorIndex: Int = 0
    private let refreshColors: [Color] = [.red, .black, .green]

    private let contextDidSave = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)

    private var visibleRows: [WiktionaryReportRow] {
        allWords.compactMap { word in
            let object = objectByWord[word]
            let freq = object.map(\.frequencyRank).flatMap { $0 > 0 ? $0 : nil }
            if let freq, Double(freq) < threshold {
                return nil // glemt: finnes med frekvens under terskel
            }
            return WiktionaryReportRow(thaiWord: word, frequencyRank: freq, thaiWordObject: object)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Frequency threshold: \(Int(threshold))")
                        .font(.headline)
                    Circle()
                        .fill(refreshColors[refreshColorIndex])
                        .frame(width: 16, height: 16)
                }
                Slider(value: $threshold, in: 0...4000, step: 50)
                Text("\(allWords.count - visibleRows.count) skipped (frequency < \(Int(threshold))) · \(visibleRows.count) shown")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            List(visibleRows) { row in
                HStack {
                    Text(row.thaiWord)
                        .font(.system(size: 18))
                    Spacer()
                    if let freq = row.frequencyRank {
                        Text("\(freq)")
                            .foregroundColor(.secondary)
                    } else if row.thaiWordObject != nil {
                        Text("missing frequency")
                            .foregroundColor(.red)
                    } else {
                        Text("not found in database")
                            .foregroundColor(.red)
                    }
                    Button {
                        UIPasteboard.general.string = row.thaiWord
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    Button {
                        selectedWord = row.thaiWordObject
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(.plain)
                    .disabled(row.thaiWordObject == nil)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        refreshFromDatabase()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            loadWordsIfNeeded()
            refreshFromDatabase()
        }
        .onReceive(contextDidSave) { _ in
            refreshFromDatabase()
        }
        .sheet(item: $selectedWord, onDismiss: refreshFromDatabase) { word in
            DetailWordView(initialWord: WordInput(from: word), isNested: true)
                .environment(appState)
                .environment(\.managedObjectContext, context)
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 900, minHeight: 1200)
                #endif
        }
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 800, minHeight: 1000)
        #endif
    }

    private func loadWordsIfNeeded() {
        guard allWords.isEmpty else { return }
        guard let url = Bundle.main.url(forResource: "thai_wiktionary_200_basic", withExtension: "csv"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        allWords = Array(lines.dropFirst()) // dropp header "thaiWord"
    }

    private func refreshFromDatabase() {
        refreshColorIndex = (refreshColorIndex + 1) % refreshColors.count
        guard !allWords.isEmpty else { return }
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(format: "thaiWord IN %@", allWords)
        let results = (try? context.fetch(request)) ?? []

        var bestByWord: [String: ThaiWords] = [:]
        for word in results {
            guard let text = word.thaiWord else { continue }
            if let existing = bestByWord[text] {
                if existing.frequencyRank == 0 || (word.frequencyRank > 0 && word.frequencyRank < existing.frequencyRank) {
                    bestByWord[text] = word
                }
            } else {
                bestByWord[text] = word
            }
        }
        objectByWord = bestByWord
    }
}
