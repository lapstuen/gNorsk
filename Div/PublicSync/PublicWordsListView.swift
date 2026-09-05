// PublicWordsListView.swift
// Viser innholdet i den delte Public CloudKit-databasen, og lar deg tømme den under testing.
// Rører ALDRI den lokale/private databasen.
import SwiftUI
import CloudKit
import CoreData
import UIKit

struct PublicWordsListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var context

    @State private var words: [CKRecord] = []
    @State private var sentenceRecords: [CKRecord] = []
    @State private var isLoading = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false

    @State private var selectedLocalWord: ThaiWords?
    @State private var wordJustEdited: ThaiWords?

    @State private var selectedLocalSentence: ThaiWords?
    @State private var sentenceJustEdited: (row: ThaiWords, parentTag: String)?

    var body: some View {
        List {
            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete all content in Public", systemImage: "trash")
                }
                .disabled(isDeleting || isLoading)
            } footer: {
                Text("Permanently deletes ALL words and sentences in the shared Public database. Your local database is not affected. Cannot be undone.")
            }

            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading...")
                    }
                }
            } else {
                if words.isEmpty {
                    Section {
                        Text("No words found in Public.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Words (\(wordsOnly.count))") {
                        ForEach(wordsOnly, id: \.recordID) { record in
                            row(for: record)
                        }
                    }
                    Section("Words marked as sentence (\(sentencesOnly.count))") {
                        ForEach(sentencesOnly, id: \.recordID) { record in
                            row(for: record)
                        }
                    }
                }

                Section("Linked sentences (\(sentenceRecords.count))") {
                    if sentenceRecords.isEmpty {
                        Text("No linked sentences found in Public.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sentenceRecords, id: \.recordID) { record in
                            sentenceRow(for: record)
                        }
                    }
                }
            }
        }
        .navigationTitle("Public Database")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task { await load() }
        .confirmationDialog(
            "This permanently deletes ALL content in the shared Public database. Your local database is not affected. This cannot be undone.",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete everything in Public", role: .destructive) {
                Task { await deleteAll() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $selectedLocalWord, onDismiss: {
            if let word = wordJustEdited {
                wordJustEdited = nil
                Task { await syncSingleWordToPublic(word) }
            }
        }) { word in
            DetailWordView(initialWord: WordInput(from: word), isNested: true)
                .environment(appState)
                .environment(\.managedObjectContext, context)
                .onAppear { wordJustEdited = word }
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 900, minHeight: 1200)
                #endif
        }
        .sheet(item: $selectedLocalSentence, onDismiss: {
            if let pending = sentenceJustEdited {
                sentenceJustEdited = nil
                Task { await syncSingleSentenceToPublic(pending.row, parentThaiWord: pending.parentTag) }
            }
        }) { sentenceWord in
            DetailWordView(initialWord: WordInput(from: sentenceWord), isNested: true)
                .environment(appState)
                .environment(\.managedObjectContext, context)
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 900, minHeight: 1200)
                #endif
        }
    }

    /// Sender akkurat dette ene ordet — og setningene tagget med det — til Public på nytt
    /// (uavhengig av om noe faktisk ble endret). Slipper å kjøre en full "Oppdater eksporterte
    /// ord"-runde for hver rettelse under opprydding.
    private func syncSingleWordToPublic(_ word: ThaiWords) async {
        guard let wordId = word.id, let wordRecord = PublicRecordBuilder.makeWordRecord(from: word) else { return }

        let thaiWord = word.thaiWord ?? ""
        let sentenceRows = SentenceRowLookup.sentenceRows(forThaiWord: thaiWord, excluding: wordId, in: context)
        var recordsToSave: [CKRecord] = [wordRecord]
        var sentenceSyncUpdates: [(UUID, String)] = []
        for row in sentenceRows {
            guard let sentenceRecord = PublicRecordBuilder.makeSentenceRecord(
                from: row, parentThaiWord: thaiWord, wordRecordID: wordRecord.recordID
            ), let sentenceId = row.id else { continue }
            recordsToSave.append(sentenceRecord)
            sentenceSyncUpdates.append((sentenceId, sentenceRecord.recordID.recordName))
        }

        do {
            try await PublicRecordWriter.save(recordsToSave)
            await MainActor.run {
                PublicSyncRecord.upsert(
                    sourceId: wordId, sourceType: .word, direction: .export,
                    publicRecordName: wordRecord.recordID.recordName, in: context
                )
                for (id, name) in sentenceSyncUpdates {
                    PublicSyncRecord.upsert(sourceId: id, sourceType: .sentence, direction: .export, publicRecordName: name, in: context)
                }
                try? context.save()
                if let idx = words.firstIndex(where: { $0.recordID == wordRecord.recordID }) {
                    words[idx] = wordRecord
                }
                let suffix = sentenceSyncUpdates.isEmpty ? "" : " (+ \(sentenceSyncUpdates.count) sentences)"
                Notifier.shared.show(.success, "Updated in Public: \(thaiWord)\(suffix)")
            }
        } catch {
            await MainActor.run {
                Notifier.shared.show(.error, "Could not update '\(word.thaiWord ?? "")' in Public: \(error.localizedDescription)")
            }
        }
    }

    /// Sender akkurat denne ene tilknyttede setningen til Public på nytt.
    private func syncSingleSentenceToPublic(_ sentenceRow: ThaiWords, parentThaiWord: String) async {
        guard let sentenceId = sentenceRow.id else { return }

        let parentRequest: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        parentRequest.predicate = NSPredicate(format: "thaiWord == %@", parentThaiWord)
        parentRequest.fetchLimit = 1
        guard let parentWord = (try? context.fetch(parentRequest))?.first, let parentId = parentWord.id else {
            Notifier.shared.show(.error, "Could not find the parent word '\(parentThaiWord)' locally.")
            return
        }

        let wordRecordID = PublicCK.wordRecordID(for: parentId)
        guard let record = PublicRecordBuilder.makeSentenceRecord(
            from: sentenceRow, parentThaiWord: parentThaiWord, wordRecordID: wordRecordID
        ) else { return }

        do {
            try await PublicRecordWriter.save([record])
            await MainActor.run {
                PublicSyncRecord.upsert(
                    sourceId: sentenceId, sourceType: .sentence, direction: .export,
                    publicRecordName: record.recordID.recordName, in: context
                )
                try? context.save()
                if let idx = sentenceRecords.firstIndex(where: { $0.recordID == record.recordID }) {
                    sentenceRecords[idx] = record
                }
                Notifier.shared.show(.success, "Updated sentence in Public: \(sentenceRow.thaiWord ?? "")")
            }
        } catch {
            await MainActor.run {
                Notifier.shared.show(.error, "Could not update the sentence in Public: \(error.localizedDescription)")
            }
        }
    }

    /// Finner ordet i DIN lokale database (via sourceWordID lagret på Public-recorden) og åpner det til redigering.
    private func openLocalDetail(for record: CKRecord) {
        guard let sourceIdString = record[PublicCK.WordField.sourceWordID] as? String,
              let sourceId = UUID(uuidString: sourceIdString) else {
            Notifier.shared.show(.error, "No local link found for this word.")
            return
        }
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", sourceId as CVarArg)
        request.fetchLimit = 1
        guard let localWord = (try? context.fetch(request))?.first else {
            Notifier.shared.show(.error, "The word no longer exists in your local database.")
            return
        }
        selectedLocalWord = localWord
    }

    /// Finner setningsraden i DIN lokale database (via sourceSentenceID) og åpner den til redigering.
    private func openLocalSentenceDetail(for record: CKRecord) {
        guard let sourceIdString = record[PublicCK.SentenceField.sourceSentenceID] as? String,
              let sourceId = UUID(uuidString: sourceIdString) else {
            Notifier.shared.show(.error, "No local link found for this sentence.")
            return
        }
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", sourceId as CVarArg)
        request.fetchLimit = 1
        guard let localSentence = (try? context.fetch(request))?.first else {
            Notifier.shared.show(.error, "The sentence no longer exists locally.")
            return
        }
        let parentTag = (record[PublicCK.SentenceField.tag] as? String) ?? ""
        sentenceJustEdited = (localSentence, parentTag)
        selectedLocalSentence = localSentence
    }

    // Public-spørringen sorterer allerede på frequencyRank; her deler vi den ene strømmen
    // i to grupper (rekkefølgen internt i hver gruppe er dermed fortsatt frekvenssortert).
    private var wordsOnly: [CKRecord] { words.filter { !isSentence($0) } }
    private var sentencesOnly: [CKRecord] { words.filter { isSentence($0) } }

    private func isSentence(_ record: CKRecord) -> Bool {
        ((record[PublicCK.WordField.wordType] as? NSNumber)?.intValue ?? 0) == 1
    }

    @ViewBuilder
    private func row(for record: CKRecord) -> some View {
        HStack(spacing: 10) {
            thumbnail(for: record, imageKey: PublicCK.WordField.image)

            VStack(alignment: .leading) {
                Text(record[PublicCK.WordField.thaiWord] as? String ?? "?")
                    .font(.headline)
                Text(record[PublicCK.WordField.englishWord] as? String ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let rank = (record[PublicCK.WordField.frequencyRank] as? NSNumber)?.intValue {
                    Text("#\(rank)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(isSentence(record) ? "Sentence" : "Word")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSentence(record) ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                    .clipShape(Capsule())
            }

            Button {
                openLocalDetail(for: record)
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func sentenceRow(for record: CKRecord) -> some View {
        HStack(spacing: 10) {
            thumbnail(for: record, imageKey: PublicCK.SentenceField.image)

            VStack(alignment: .leading) {
                Text(record[PublicCK.SentenceField.sentenceText] as? String ?? "?")
                    .font(.headline)
                Text(record[PublicCK.SentenceField.englishWord] as? String ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let tag = record[PublicCK.SentenceField.tag] as? String, !tag.isEmpty {
                Text(tag)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.15))
                    .clipShape(Capsule())
            }

            Button {
                openLocalSentenceDetail(for: record)
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func thumbnail(for record: CKRecord, imageKey: String) -> some View {
        if let asset = record[imageKey] as? CKAsset,
           let data = TempAsset.readData(from: asset),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            words = try await PublicRecordFetcher.fetchAllWordsForListing()
            sentenceRecords = try await PublicRecordFetcher.fetchAllSentencesForListing()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAll() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            let result = try await PublicRecordAdmin.deleteEverything()
            Notifier.shared.show(.success, "Deleted \(result.words) words and \(result.sentences) sentences from Public.")
            words = []
            sentenceRecords = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        PublicWordsListView()
            .environment(AppState())
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
