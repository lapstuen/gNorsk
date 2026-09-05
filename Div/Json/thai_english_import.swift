//
//  Untitled.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/8/25.
//
import SwiftUI
import CoreData

func importFullThaiWordList(context: NSManagedObjectContext) {
    guard let url = Bundle.main.url(forResource: "thai_english_64000_full", withExtension: "csv") else {
        print("❌ CSV ikke funnet i bundle")
        return
    }

    do {
        let content = try String(contentsOf: url, encoding: .utf8)
        let rows = content.components(separatedBy: .newlines).dropFirst() // hopp over header

        for line in rows {
            let columns = line.components(separatedBy: ",")
            guard columns.count >= 2 else { continue }

            let thai = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let english = columns[1].trimmingCharacters(in: .whitespacesAndNewlines)

            guard !thai.isEmpty else { continue }

            // Sjekk om ordet finnes fra før
            let request: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
            request.predicate = NSPredicate(format: "thaiWord == %@", thai)

            let exists = (try? context.count(for: request)) ?? 0 > 0
            if exists { continue }

            // Sett inn nytt ord
            let _ = GlFunctions.shared.insertWordIntoCoreData(
                id: UUID(),
                thaiword: thai,
                englishword: english,
                sentence: "",
                groupId: 97,
                image: UIImage(systemName: "questionmark.square.fill")!
            )
        }

        try context.save()
        print("✅ Fullført import")

    } catch {
        print("❌ Feil under import: \(error)")
    }
}
