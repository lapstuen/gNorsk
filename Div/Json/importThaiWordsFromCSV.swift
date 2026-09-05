//
//  importThaiWordsFromCSV.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/8/25.
//

import CoreData
import SwiftUI

func importThaiWordsFromCSV(context: NSManagedObjectContext) {
    guard let url = Bundle.main.url(forResource: "thai_words_for_coredata", withExtension: "csv") else {
        print("❌ Fant ikke filen")
        return
    }

    do {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        for line in lines.dropFirst() { // Drop header
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let fetchRequest: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "thaiWord == %@", trimmed)

            let count = try context.count(for: fetchRequest)
            if count == 0 {
                let newWord = ThaiWords(context: context)
                newWord.thaiWord = trimmed
            }
        }

        try context.save()
        print("✅ Import fullført")
    } catch {
        print("❌ Feil ved import: \(error.localizedDescription)")
    }
}
