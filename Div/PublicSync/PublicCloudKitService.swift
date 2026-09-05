// PublicCloudKitService.swift
// Tilgang til den delte Public CloudKit-databasen (samme container som privat CloudKit-sync).
// Kun eier skriver hit (via en fremtidig eksport-visning); alle brukere kan lese/importere.
import CloudKit
import CoreData

enum PublicCK {
    static let containerIdentifier = "iCloud.com.lapstuen.gNorsk"
    static let container = CKContainer(identifier: containerIdentifier)
    static var database: CKDatabase { container.publicCloudDatabase }

    enum RecordType {
        static let word = "PublicWord"
        static let sentence = "PublicSentence"
    }

    enum WordField {
        static let thaiWord = "thaiWord"
        static let englishWord = "englishWord"
        static let ipa = "ipa"
        static let sentenceText = "sentenceText"
        static let notes = "notes"
        static let tags = "tags"
        static let frequencyRank = "frequencyRank"
        static let wordType = "wordType"
        static let image = "image"
        static let sourceWordID = "sourceWordID"
    }

    enum SentenceField {
        static let sentenceText = "sentenceText"
        static let englishWord = "englishWord"
        static let tag = "tag"
        static let image = "image"
        static let sourceSentenceID = "sourceSentenceID"
        static let wordReference = "wordReference"
    }

    /// Deterministisk recordID basert på lokal UUID — gjør re-eksport til en oppdatering, ikke en duplikat.
    static func wordRecordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "PW-\(id.uuidString)")
    }

    static func sentenceRecordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "PS-\(id.uuidString)")
    }
}

// MARK: - Mapping: lokalt → CKRecord (eksport)

enum PublicRecordBuilder {

    static func makeWordRecord(from word: ThaiWords) -> CKRecord? {
        guard let id = word.id else { return nil }
        let record = CKRecord(recordType: PublicCK.RecordType.word, recordID: PublicCK.wordRecordID(for: id))
        record[PublicCK.WordField.thaiWord] = word.thaiWord as CKRecordValue?
        record[PublicCK.WordField.englishWord] = word.englishWord as CKRecordValue?
        record[PublicCK.WordField.ipa] = word.ipa as CKRecordValue?
        record[PublicCK.WordField.sentenceText] = word.sentence as CKRecordValue?
        record[PublicCK.WordField.notes] = word.notes as CKRecordValue?
        record[PublicCK.WordField.tags] = word.tags as CKRecordValue?
        record[PublicCK.WordField.frequencyRank] = Int64(word.frequencyRank) as CKRecordValue
        record[PublicCK.WordField.wordType] = Int64(word.wordType) as CKRecordValue
        record[PublicCK.WordField.sourceWordID] = id.uuidString as CKRecordValue
        if let data = word.image, let assetURL = try? TempAsset.write(data: data, name: "word-\(id.uuidString).jpg") {
            record[PublicCK.WordField.image] = CKAsset(fileURL: assetURL)
        }
        return record
    }

    /// Setninger i denne appen er ikke den (ubrukte) `Sentence`-entiteten, men vanlige `ThaiWords`-rader
    /// (groupId 129, wordType 1) hvis `tags`-felt inneholder grunnordets `thaiWord` — se `AddSentenceView`/`GLFunctions.insertWordIntoCoreDataNoImage`.
    static func makeSentenceRecord(from sentenceRow: ThaiWords, parentThaiWord: String, wordRecordID: CKRecord.ID) -> CKRecord? {
        guard let id = sentenceRow.id else { return nil }
        let record = CKRecord(recordType: PublicCK.RecordType.sentence, recordID: PublicCK.sentenceRecordID(for: id))
        record[PublicCK.SentenceField.sentenceText] = sentenceRow.thaiWord as CKRecordValue?
        record[PublicCK.SentenceField.englishWord] = sentenceRow.englishWord as CKRecordValue?
        record[PublicCK.SentenceField.tag] = parentThaiWord as CKRecordValue
        record[PublicCK.SentenceField.sourceSentenceID] = id.uuidString as CKRecordValue
        record[PublicCK.SentenceField.wordReference] = CKRecord.Reference(recordID: wordRecordID, action: .none)
        if let data = sentenceRow.image, let assetURL = try? TempAsset.write(data: data, name: "sentence-\(id.uuidString).jpg") {
            record[PublicCK.SentenceField.image] = CKAsset(fileURL: assetURL)
        }
        return record
    }
}

// MARK: - Finn setningsrader for et ord (ThaiWords tagget med grunnordets thaiWord)

enum SentenceRowLookup {
    /// Samme gruppe som `kSentencesForWordsGroupID` i AddSentenceView.swift (#xSentencesForWords).
    static let sentencesForWordsGroupID: Int16 = 129

    /// Kun rader som faktisk ER eksempelsetninger (gruppe 129 og/eller wordType==1) regnes med her.
    /// Uten dette ville f.eks. synonym-ord tagget med et annet ord blitt feilaktig eksportert
    /// som "tilknyttet setning" i stedet for sitt eget selvstendige ord.
    static func sentenceRows(forThaiWord thaiWord: String, excluding excludedId: UUID?, in context: NSManagedObjectContext) -> [ThaiWords] {
        guard !thaiWord.isEmpty else { return [] }
        let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        request.predicate = NSPredicate(
            format: "tags CONTAINS %@ AND (groupId == %d OR wordType == 1)",
            thaiWord, sentencesForWordsGroupID
        )
        let rows = (try? context.fetch(request)) ?? []
        return rows.filter { $0.id != excludedId }
    }
}

// MARK: - CKAsset ↔ Data via midlertidig fil

enum TempAsset {
    static func write(data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func readData(from asset: CKAsset?) -> Data? {
        guard let url = asset?.fileURL else { return nil }
        return try? Data(contentsOf: url)
    }

    static func cleanup(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Lagring (batchet, med CloudKits ~400-poster-per-operasjon-grense)

enum PublicRecordWriter {

    static func save(_ records: [CKRecord], batchSize: Int = 200) async throws {
        guard !records.isEmpty else { return }
        for chunk in records.chunked(into: batchSize) {
            _ = try await PublicCK.database.modifyRecords(saving: chunk, deleting: [], savePolicy: .changedKeys)
        }
    }

    /// Som `save`, men lagrer ikke-atomisk: én dårlig post (f.eks. for stort bilde) feiler kun
    /// seg selv i stedet for å velte hele bolken. Returnerer (recordID, thaiWord, feil) for hver som feilet.
    @discardableResult
    static func saveReportingFailures(
        _ records: [(record: CKRecord, thaiWord: String)], batchSize: Int = 20
    ) async throws -> [(recordID: CKRecord.ID, thaiWord: String, error: Error)] {
        guard !records.isEmpty else { return [] }
        var failures: [(CKRecord.ID, String, Error)] = []
        for chunk in records.chunked(into: batchSize) {
            let result = try await PublicCK.database.modifyRecords(
                saving: chunk.map(\.record), deleting: [], savePolicy: .changedKeys, atomically: false
            )
            let thaiWordByID = Dictionary(uniqueKeysWithValues: chunk.map { ($0.record.recordID, $0.thaiWord) })
            for (id, outcome) in result.saveResults {
                if case .failure(let error) = outcome {
                    failures.append((id, thaiWordByID[id] ?? "?", error))
                }
            }
        }
        return failures
    }
}

// MARK: - Spørringer (import)

enum PublicRecordFetcher {

    /// Henter alle PublicWord-poster innenfor et frekvensintervall, sortert stigende. Sidenavigerer selv (CloudKit-cursor).
    static func fetchWords(minRank: Int, maxRank: Int) async throws -> [CKRecord] {
        let predicate = NSPredicate(format: "frequencyRank >= %d AND frequencyRank <= %d", minRank, maxRank)
        let query = CKQuery(recordType: PublicCK.RecordType.word, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: PublicCK.WordField.frequencyRank, ascending: true)]
        return try await fetchAll(query: query)
    }

    /// Henter alle PublicSentence-poster som matcher en av de gitte tags (f.eks. "*ไป", "*มา").
    static func fetchSentences(forTags tags: [String]) async throws -> [CKRecord] {
        guard !tags.isEmpty else { return [] }
        let predicate = NSPredicate(format: "tag IN %@", tags)
        let query = CKQuery(recordType: PublicCK.RecordType.sentence, predicate: predicate)
        return try await fetchAll(query: query)
    }

    /// Henter alle ord i Public for visning i en liste (inkl. lite thumbnail-bilde og ord/setning-type).
    static func fetchAllWordsForListing() async throws -> [CKRecord] {
        let query = CKQuery(recordType: PublicCK.RecordType.word, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: PublicCK.WordField.frequencyRank, ascending: true)]
        return try await fetchAll(query: query, desiredKeys: [
            PublicCK.WordField.thaiWord, PublicCK.WordField.englishWord, PublicCK.WordField.frequencyRank,
            PublicCK.WordField.wordType, PublicCK.WordField.image, PublicCK.WordField.sourceWordID,
        ])
    }

    /// Henter alle tilknyttede setninger (PublicSentence) i Public for visning i en liste.
    static func fetchAllSentencesForListing() async throws -> [CKRecord] {
        let query = CKQuery(recordType: PublicCK.RecordType.sentence, predicate: NSPredicate(value: true))
        return try await fetchAll(query: query, desiredKeys: [
            PublicCK.SentenceField.sentenceText, PublicCK.SentenceField.englishWord,
            PublicCK.SentenceField.tag, PublicCK.SentenceField.image, PublicCK.SentenceField.sourceSentenceID,
        ])
    }

    static func fetchAll(query: CKQuery, desiredKeys: [String]? = nil) async throws -> [CKRecord] {
        var results: [CKRecord] = []
        var (matchResults, cursor) = try await PublicCK.database.records(matching: query, desiredKeys: desiredKeys)
        results.append(contentsOf: matchResults.compactMap { try? $0.1.get() })

        while let currentCursor = cursor {
            let page = try await PublicCK.database.records(continuingMatchFrom: currentCursor, desiredKeys: desiredKeys)
            results.append(contentsOf: page.matchResults.compactMap { try? $0.1.get() })
            cursor = page.queryCursor
        }
        return results
    }
}

// MARK: - Administrasjon (slett alt innhold i Public — rører aldri lokal database)

enum PublicRecordAdmin {

    private static func fetchAllRecordIDs(recordType: String) async throws -> [CKRecord.ID] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let records = try await PublicRecordFetcher.fetchAll(query: query, desiredKeys: [])
        return records.map(\.recordID)
    }

    @discardableResult
    private static func deleteAllRecords(recordType: String, batchSize: Int = 200) async throws -> Int {
        let ids = try await fetchAllRecordIDs(recordType: recordType)
        for chunk in ids.chunked(into: batchSize) {
            _ = try await PublicCK.database.modifyRecords(saving: [], deleting: chunk)
        }
        return ids.count
    }

    /// Sletter ALT innhold (ord + setninger) i den delte Public-databasen. Kan ikke angres.
    /// Rører aldri den lokale/private databasen.
    static func deleteEverything() async throws -> (words: Int, sentences: Int) {
        let sentenceCount = try await deleteAllRecords(recordType: PublicCK.RecordType.sentence)
        let wordCount = try await deleteAllRecords(recordType: PublicCK.RecordType.word)
        return (wordCount, sentenceCount)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
