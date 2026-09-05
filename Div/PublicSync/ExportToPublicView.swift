// ExportToPublicView.swift
// Manuell eksport fra din private database til den delte Public CloudKit-databasen.
// Kun du (eier) bruker denne. Ingen automatikk — alt trigges av et knappetrykk.
import SwiftUI
import CoreData
import CloudKit

struct ExportToPublicView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var fraRankText: String = ""
    @State private var tilRankText: String = ""
    @State private var isRunning = false
    @State private var progressText = ""
    @State private var resultSummary: String?
    @State private var showConfirm = false
    @State private var pendingAction: (() -> Void)?

    var body: some View {
        NavigationStack {
            List {
                Section("Export new frequency range") {
                    TextField("From rank", text: $fraRankText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField("To rank", text: $tilRankText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Button {
                        confirmAndRun(exportRange: true)
                    } label: {
                        Label("Export to Public", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(isRunning || Int(fraRankText) == nil || Int(tilRankText) == nil)
                }

                Section("Update previously exported words") {
                    Button {
                        confirmAndRun(exportRange: false)
                    } label: {
                        Label("Update exported words in Public", systemImage: "arrow.triangle.2.circlepath.icloud")
                    }
                    .disabled(isRunning)
                }

                Section("Public database") {
                    NavigationLink {
                        PublicWordsListView()
                    } label: {
                        Label("View / manage Public database", systemImage: "list.bullet.rectangle")
                    }
                }

                if isRunning {
                    Section {
                        HStack {
                            ProgressView()
                            Text(progressText)
                                .font(.footnote)
                        }
                    }
                }

                if let summary = resultSummary {
                    Section("Result") {
                        Text(summary)
                    }
                }
            }
            .navigationTitle("Export to Public")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 800, minHeight: 1000)
        #endif
        .confirmationDialog(
            "This writes to the shared Public database, visible to all users of the app. Continue?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Export", role: .destructive) {
                let action = pendingAction
                pendingAction = nil
                action?()
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        }
    }

    private func confirmAndRun(exportRange: Bool) {
        if exportRange {
            let minRank = Int(fraRankText) ?? 0
            let maxRank = Int(tilRankText) ?? 0
            pendingAction = { runExport(minRank: minRank, maxRank: maxRank) }
        } else {
            pendingAction = { runUpdateExported() }
        }
        showConfirm = true
    }

    private func runExport(minRank: Int, maxRank: Int) {
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(format: "frequencyRank >= %d AND frequencyRank <= %d", minRank, maxRank)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ThaiWords.frequencyRank, ascending: true)]
        let words = (try? context.fetch(request)) ?? []
        startExport(words: words, emptyMessage: "No words found in this range.")
    }

    private func runUpdateExported() {
        let ids = PublicSyncRecord.exportedSourceIds(sourceType: .word, in: context)
        guard !ids.isEmpty else {
            resultSummary = "No previously exported words found."
            return
        }
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", ids)
        let words = (try? context.fetch(request)) ?? []
        startExport(words: words, emptyMessage: "None of the previously exported words were found locally.")
    }

    private func startExport(words: [ThaiWords], emptyMessage: String) {
        guard !words.isEmpty else {
            resultSummary = emptyMessage
            return
        }

        isRunning = true
        resultSummary = nil
        progressText = "Starting export of \(words.count) words..."

        Task {
            var exportedWordCount = 0
            var exportedSentenceCount = 0
            var failedCount = 0
            var errorDetails: [String] = []

            // Prosesser i bolker for jevn fremdriftsvisning og lavere minnebruk (bilder inkludert)
            for chunk in words.chunked(into: 15) {
                await MainActor.run {
                    progressText = "Exporting words \(exportedWordCount + failedCount + 1)–"
                        + "\(min(exportedWordCount + failedCount + chunk.count, words.count)) of \(words.count)..."
                }

                var recordsToSave: [(record: CKRecord, thaiWord: String)] = []
                var wordSyncUpdates: [(id: UUID, recordName: String)] = []
                var sentenceSyncUpdates: [(id: UUID, recordName: String)] = []

                for word in chunk {
                    guard let wordRecord = PublicRecordBuilder.makeWordRecord(from: word), let wordId = word.id else {
                        failedCount += 1
                        continue
                    }
                    let thaiWord = word.thaiWord ?? ""
                    recordsToSave.append((wordRecord, thaiWord))
                    wordSyncUpdates.append((wordId, wordRecord.recordID.recordName))

                    let sentenceRows = SentenceRowLookup.sentenceRows(forThaiWord: thaiWord, excluding: wordId, in: context)
                    for row in sentenceRows {
                        guard let sentenceRecord = PublicRecordBuilder.makeSentenceRecord(
                            from: row, parentThaiWord: thaiWord, wordRecordID: wordRecord.recordID
                        ), let sentenceId = row.id else { continue }
                        recordsToSave.append((sentenceRecord, row.thaiWord ?? thaiWord))
                        sentenceSyncUpdates.append((sentenceId, sentenceRecord.recordID.recordName))
                    }
                }

                do {
                    // Ikke-atomisk: én dårlig post (f.eks. et for stort bilde) feiler kun seg selv,
                    // ikke resten av bolken.
                    let failures = try await PublicRecordWriter.saveReportingFailures(recordsToSave)
                    let failedNames = Set(failures.map { $0.recordID.recordName })
                    for failure in failures {
                        errorDetails.append("'\(failure.thaiWord)': \(failure.error.localizedDescription)")
                    }

                    await MainActor.run {
                        for entry in wordSyncUpdates where !failedNames.contains(entry.recordName) {
                            PublicSyncRecord.upsert(
                                sourceId: entry.id, sourceType: .word, direction: .export,
                                publicRecordName: entry.recordName, in: context
                            )
                        }
                        for entry in sentenceSyncUpdates where !failedNames.contains(entry.recordName) {
                            PublicSyncRecord.upsert(
                                sourceId: entry.id, sourceType: .sentence, direction: .export,
                                publicRecordName: entry.recordName, in: context
                            )
                        }
                        try? context.save()
                    }
                    exportedWordCount += wordSyncUpdates.filter { !failedNames.contains($0.recordName) }.count
                    exportedSentenceCount += sentenceSyncUpdates.filter { !failedNames.contains($0.recordName) }.count
                    failedCount += failures.count
                } catch {
                    // Hele bolken feilet (f.eks. nettverksfeil før noe rakk å bli forsøkt lagret)
                    failedCount += recordsToSave.count
                    errorDetails.append(error.localizedDescription)
                }
            }

            await MainActor.run {
                isRunning = false
                var summary = "\(exportedWordCount) words and \(exportedSentenceCount) sentences exported."
                if failedCount > 0 {
                    summary += " \(failedCount) failed."
                    if let firstError = errorDetails.first {
                        summary += "\nFirst error: \(firstError)"
                        if errorDetails.count > 1 {
                            summary += " (+ \(errorDetails.count - 1) more errors)"
                        }
                    }
                }
                resultSummary = summary
                Notifier.shared.show(
                    failedCount > 0 ? .error : .success,
                    failedCount > 0 ? "Export completed with errors — see result" : "Export completed"
                )
            }
        }
    }
}

#Preview {
    ExportToPublicView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
