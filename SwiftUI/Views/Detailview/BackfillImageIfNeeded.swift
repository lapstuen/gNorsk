// DetailWordLogic.swift
import SwiftUI
import CoreData
import UIKit

extension DetailWordView {
    func backfillImageIfNeeded() {
        guard selectedImage == nil else { return }

        if let oid = currentWordOID,
           let obj = try? context.existingObject(with: oid) as? ThaiWords,
           let data = obj.image,
           let ui = UIImage(data: data) {
            selectedImage = ui
            return
        }

        if let uuid = originalWordID {
            let req = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
            req.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            req.fetchLimit = 1
            req.returnsObjectsAsFaults = false
            if let obj = try? context.fetch(req).first,
               let data = obj.image,
               let ui = UIImage(data: data) {
                selectedImage = ui
                return
            }
        }

        if !thaiWord.isEmpty {
            let req = NSFetchRequest<ThaiWords>(entityName: "ThaiWords")
            req.predicate = NSPredicate(format: "thaiWord == %@", thaiWord)
            req.fetchLimit = 1
            req.returnsObjectsAsFaults = false
            if let obj = try? context.fetch(req).first,
               let data = obj.image,
               let ui = UIImage(data: data) {
                selectedImage = ui
            }
        }
    }

    public func lagreOrd() {
        let trimmed = thaiWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Notifier.shared.show(.warning, "Enter a Thai word before saving.")
            return
        }

        guard let oid = currentWordOID,
              let eksisterende = try? context.existingObject(with: oid) as? ThaiWords
        else {
            if !appState.suppressNextUpdateError {
                Notifier.shared.show(.error, "Could not find existing row for «\(trimmed)».")
                appState.suppressNextUpdateError = true
            }
            return
        }
        appState.suppressNextUpdateError = false

        let nySetning = sentence
        let nyEngelsk = englishWord
        let nyIpa = ipa
        let nyTags = tags
        let nyTranslation1 = translation1
        let nyTranslation2 = translation2
        let nyNotes = notes

        let newImageData = imageDirty ? selectedImage?.pngData() : eksisterende.image
        let bildeEndret  = imageDirty

        let tekstUendret =
            (eksisterende.englishWord ?? "") == nyEngelsk &&
            (eksisterende.ipa ?? "") == nyIpa &&
            (eksisterende.sentence    ?? "") == nySetning &&
            (eksisterende.tags ?? "") == nyTags &&
            (eksisterende.translation1 ?? "") == nyTranslation1 &&
            (eksisterende.translation2 ?? "") == nyTranslation2 &&
            (eksisterende.notes ?? "") == nyNotes &&
            eksisterende.wordType == wordType

        guard !(tekstUendret && !bildeEndret) else { return }

        // Check and translate thaiWord to Norwegian if needed
        let thaiWordNeedTranslation = (eksisterende.translation1?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        if (eksisterende.englishWord ?? "") != nyEngelsk {
            eksisterende.englishWord = nyEngelsk
        }
        if (eksisterende.ipa ?? "") != nyIpa {
            eksisterende.ipa = nyIpa
        }
        if (eksisterende.sentence ?? "") != nySetning {
            eksisterende.sentence = nySetning
        }
        if eksisterende.tags != nyTags {
            eksisterende.tags = nyTags
        }
        if (eksisterende.translation1 ?? "") != nyTranslation1 {
            eksisterende.translation1 = nyTranslation1
        }
        if (eksisterende.translation2 ?? "") != nyTranslation2 {
            eksisterende.translation2 = nyTranslation2
        }
        if (eksisterende.notes ?? "") != nyNotes {
            eksisterende.notes = nyNotes
        }
        if eksisterende.wordType != wordType {
            eksisterende.wordType = wordType
        }
        if bildeEndret {
            eksisterende.image = newImageData
        }

        // Update modified date
        eksisterende.modifiedDate = Date()
        print("📝 LAGRET: modifiedDate satt til \(eksisterende.modifiedDate!) for \(trimmed)")

        // Perform translations asynchronously after saving basic changes
        if thaiWordNeedTranslation {
            performNorwegianTranslations(
                for: eksisterende,
                sentenceToTranslate: nil,
                thaiWordToTranslate: thaiWordNeedTranslation ? trimmed : nil
            )
        }

        do {
            try context.save()
            if isDirty || imageDirty {
                print("✅ Updated word in database")
                Notifier.shared.show(.success, "Updated: \(eksisterende.thaiWord ?? trimmed)")
            }
            imageDirty = false
        } catch {
            print("❌ Save failed: \(error)")
            Notifier.shared.show(.error, "Could not save «\(trimmed)»: \(error.localizedDescription)")
        }
    }

    private func performNorwegianTranslations(
        for word: ThaiWords,
        sentenceToTranslate: String?,
        thaiWordToTranslate: String?
    ) {
        // Translate thaiWord to Norwegian for translation1
        if let thaiWord = thaiWordToTranslate {
            translateText2(soureLanguage: "th", toLanguage: "no", text: thaiWord) { [weak word] result, error in
                guard let word = word else { return }
                DispatchQueue.main.async {
                    if let translation = result.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !translation.isEmpty {
                        word.translation1 = translation
                        try? word.managedObjectContext?.save()
                        print("✅ Oversatte thai-ord til norsk: \(translation)")
                    } else if let error = error {
                        print("❌ Feil ved oversettelse av thai-ord: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    @MainActor
    func handleThaiChange(_ nyVerdi: String) {
        let trimmed = nyVerdi.trimmingCharacters(in: .whitespacesAndNewlines)
        resultater = GlFunctions.shared.getWordCoreData(thaiWord: trimmed)
        wordExists = !resultater.isEmpty
        if let w = resultater.first {
            kildeIkon     = UIImage(named: "apple_logo")
            englishWord   = w.englishWord ?? "xxx"
            sentence      = w.sentence ?? ""
            if let ui = (w.image as? UIImage) {
                selectedImage = ui
            } else if let data = (w.image as? Data), let ui = UIImage(data: data) {
                selectedImage = ui
            }
            return
        }
        if trimmed.isEmpty {
            englishWord   = ""
            sentence      = ""
        } else {
            englishWord = ""
        }
        if trimmed.count > 1 {
            isTranslating = true
            oversettelseFeil = nil
            // Oversettelse skjer nå on-device via Apple Translation (se TranslateText2.swift),
            // ikke Google — derfor settes ikke lenger noe kilde-ikon her ved suksess.
            translateText2(soureLanguage: "th", toLanguage: "en", text: trimmed) { result, error in
                isTranslating = false
                if let first = result.first, !first.trimmingCharacters(in: .whitespaces).isEmpty {
                    englishWord = first
                } else {
                    kildeIkon   = UIImage(named: "none_logo")
                    if let error = error { oversettelseFeil = error.localizedDescription }
                }
            }
        } else {
            kildeIkon = UIImage(named: "none_logo")
        }
    }
}


// เมื่อคืนคุณนอนหลับสบายไหม
