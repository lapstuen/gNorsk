import Foundation
import CoreData

class ThaiWordImporter {
    let context: NSManagedObjectContext
    let importGroupId: Int16 = 216

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func importWordsFromJSON() {
        guard let url = Bundle.main.url(forResource: "thai_top_4000", withExtension: "json") else {
            print("❌ Fant ikke thai_top_4000.json")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let importedWords = try decoder.decode([ThaiWordJSON].self, from: data)

            let fetchRequest: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
            let existing = try context.fetch(fetchRequest)
            var existingMap: [String: ThaiWords] = [:]
            for word in existing {
                if let key = word.thaiWord, existingMap[key] == nil {
                    existingMap[key] = word
                }
            }

            var nyCount = 0

            for word in importedWords {
                if existingMap[word.word] != nil {
                    continue // hopp over eksisterende
                }

                let newWord = ThaiWords(context: context)
                newWord.thaiWord = word.word
                newWord.englishWord = word.english
                newWord.groupId = importGroupId

                // Opprett sentence med frekvens, ipa, tag og eksempel
                let sentence = "\(word.rank) \(word.ipa) *frekvens [\(word.example)]"
                newWord.sentence = sentence

                nyCount += 1
            }

            if context.hasChanges {
                try context.save()
                print("✅ Importert \(nyCount) nye ord til gruppe \(importGroupId).")
            } else {
                print("ℹ️ Ingen nye ord ble lagt til.")
            }

        } catch {
            print("🚨 Feil under import: \(error.localizedDescription)")
        }
    }
}
