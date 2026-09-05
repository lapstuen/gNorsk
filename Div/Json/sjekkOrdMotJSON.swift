//
//  sjekkOrdMotJSON.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/16/25.
//
import Foundation
import CoreData
import UIKit

extension GlFunctions {
    /// Sjekker alle Core Data-ord opp mot thai_top_4000.json i bundle.
    /// Logger hvilke ord som ikke finnes i JSON.
    func sjekkOrdMotJSON() {
        // 1) Les JSON fra bundle
        guard let jsonURL = Bundle.main.url(forResource: "thai_top_4000", withExtension: "json"),
              let jsonData = try? Data(contentsOf: jsonURL),
              let jsonList = try? JSONDecoder().decode([ThaiWordJSON].self, from: jsonData)
        else {
            print("❌ Kunne ikke lese/parse thai_top_4000.json")
            return
        }

        // Bruk Set for O(1) oppslag
        let jsonWords = Set(jsonList.map { $0.word })

        // 2) Les alle rader fra Core Data
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        let context = appDelegate.persistentContainer.viewContext

        let req = NSFetchRequest<NSManagedObject>(entityName: "ThaiWords")
        req.returnsObjectsAsFaults = false

        do {
            let rows = try context.fetch(req)
            var missing: [String] = []

            for obj in rows {
                let thaiWord = (obj.value(forKey: "thaiWord") as? String) ?? ""
                if !thaiWord.isEmpty, !jsonWords.contains(thaiWord) {
                    missing.append(thaiWord)
                }
            }

            print("✅ Sjekket \(rows.count) ord mot JSON, \(missing.count) mangler.")
            if !missing.isEmpty {
                // print litt pent, evt. del opp i mindre bunter
                print("❌ Mangler i JSON:\n" + missing.joined(separator: ", "))
            }
        } catch {
            print("❌ Feil ved Core Data-søk: \(error)")
        }
    }
}
