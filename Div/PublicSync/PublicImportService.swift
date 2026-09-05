// PublicImportService.swift
// Delt import-logikk: henter ord (+ tilknyttede setninger) fra Public for et frekvensintervall
// og oppretter dem lokalt. Brukes både av ImportFromPublicView og "Fetch words" i EditGroupView.
import CoreData
import CloudKit

enum PublicImportService {

    struct ImportResult {
        var importedWords = 0
        var skippedWords = 0
        var importedSentences = 0
        var skippedSentences = 0
    }

    /// Henter ord + tilknyttede setninger fra Public for et frekvensintervall og importerer dem lokalt.
    /// - Parameter targetGroupId: hvis satt, plasseres alle importerte ord i denne gruppen (typisk når
    ///   kalt fra gruppe-redigering). Hvis nil, beregnes riktig frekvensgruppe automatisk per ord.
    static func importRange(
        minRank: Int, maxRank: Int, targetGroupId: Int16?, context: NSManagedObjectContext
    ) async throws -> ImportResult {
        let publicWords = try await PublicRecordFetcher.fetchWords(minRank: minRank, maxRank: maxRank)
        let thaiWordTexts = publicWords.compactMap { $0[PublicCK.WordField.thaiWord] as? String }
        let publicSentences = try await PublicRecordFetcher.fetchSentences(forTags: thaiWordTexts)

        return await MainActor.run {
            importAll(words: publicWords, sentences: publicSentences, targetGroupId: targetGroupId, context: context)
        }
    }

    @MainActor
    private static func importAll(
        words: [CKRecord], sentences: [CKRecord], targetGroupId: Int16?, context: NSManagedObjectContext
    ) -> ImportResult {
        var result = ImportResult()

        for record in words {
            guard let thaiWord = record[PublicCK.WordField.thaiWord] as? String, !thaiWord.isEmpty else { continue }
            if SentenceHelpers.thaiWordExists(thaiWord, in: context) {
                result.skippedWords += 1
                continue
            }
            createLocalWord(from: record, thaiWord: thaiWord, targetGroupId: targetGroupId, context: context)
            result.importedWords += 1
        }

        for record in sentences {
            guard let sentenceText = record[PublicCK.SentenceField.sentenceText] as? String, !sentenceText.isEmpty else { continue }
            if SentenceHelpers.thaiWordExists(sentenceText, in: context) {
                result.skippedSentences += 1
                continue
            }
            createLocalSentence(from: record, sentenceText: sentenceText, context: context)
            result.importedSentences += 1
        }

        do {
            try context.save()
        } catch {
            Notifier.shared.show(.error, "Could not save imported words: \(error.localizedDescription)")
        }
        return result
    }

    @MainActor
    private static func createLocalWord(
        from record: CKRecord, thaiWord: String, targetGroupId: Int16?, context: NSManagedObjectContext
    ) {
        let newWord = ThaiWords(context: context)
        let newId = UUID()
        newWord.id = newId
        newWord.thaiWord = thaiWord
        newWord.englishWord = record[PublicCK.WordField.englishWord] as? String
        newWord.ipa = record[PublicCK.WordField.ipa] as? String
        newWord.sentence = record[PublicCK.WordField.sentenceText] as? String
        newWord.notes = record[PublicCK.WordField.notes] as? String
        newWord.tags = record[PublicCK.WordField.tags] as? String
        let frequencyRank = Int32((record[PublicCK.WordField.frequencyRank] as? NSNumber)?.intValue ?? 0)
        newWord.frequencyRank = frequencyRank
        newWord.wordType = Int16((record[PublicCK.WordField.wordType] as? NSNumber)?.intValue ?? 0)
        newWord.groupId = targetGroupId ?? FrequencyGroupSeeder.groupId(forFrequencyRank: frequencyRank) ?? AppState.publicImportGroupId
        newWord.insertDate = Date()
        newWord.modifiedDate = Date()
        newWord.star = false
        newWord.easiness = 2.5
        newWord.learningState = LearningState.new.rawValue
        if let asset = record[PublicCK.WordField.image] as? CKAsset, let data = TempAsset.readData(from: asset) {
            newWord.image = data
        }
        PublicSyncRecord.upsert(
            sourceId: newId, sourceType: .word, direction: .importFromPublic,
            publicRecordName: record.recordID.recordName, in: context
        )
    }

    @MainActor
    private static func createLocalSentence(from record: CKRecord, sentenceText: String, context: NSManagedObjectContext) {
        let newSentence = ThaiWords(context: context)
        let newId = UUID()
        newSentence.id = newId
        newSentence.thaiWord = sentenceText
        newSentence.englishWord = record[PublicCK.SentenceField.englishWord] as? String
        let parentTag = (record[PublicCK.SentenceField.tag] as? String) ?? ""
        newSentence.tags = parentTag.isEmpty ? nil : ",\(parentTag),"
        newSentence.groupId = SentenceRowLookup.sentencesForWordsGroupID
        newSentence.wordType = 1
        newSentence.insertDate = Date()
        newSentence.modifiedDate = Date()
        newSentence.star = false
        if let asset = record[PublicCK.SentenceField.image] as? CKAsset, let data = TempAsset.readData(from: asset) {
            newSentence.image = data
        }
        PublicSyncRecord.upsert(
            sourceId: newId, sourceType: .sentence, direction: .importFromPublic,
            publicRecordName: record.recordID.recordName, in: context
        )
    }
}
