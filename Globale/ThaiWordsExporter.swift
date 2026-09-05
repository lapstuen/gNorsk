//
//  ThaiWordsExporter.swift
//  gThai
//
//  Eksporterer alle Thai-ord fra Core Data til JSON for PyThaiNLP-prosessering
//

import Foundation
import CoreData
import SwiftUI
#if os(iOS)
import UIKit
#endif

enum ThaiWordsExporter {

    /// Eksporter alle unike Thai-ord fra Core Data til JSON
    ///
    /// Bruk denne funksjonen EN GANG for å generere komplett ordliste.
    /// Deretter kjør Python-scriptet for å generere IPA + stavelser.
    ///
    /// Eksempel:
    /// ```swift
    /// ThaiWordsExporter.exportAllWords(context: viewContext)
    /// ```
    static func exportAllWords(context: NSManagedObjectContext) {
        print("🚀 Starter eksport av alle Thai-ord...")

        let fetchRequest: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ThaiWords.thaiWord, ascending: true)]

        do {
            let allWords = try context.fetch(fetchRequest)
            print("✅ Hentet \(allWords.count) ord fra Core Data")

            // Ekstraher unike Thai-ord
            var uniqueWords = Set<String>()

            for word in allWords {
                if let thaiText = word.thaiWord?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !thaiText.isEmpty {
                    uniqueWords.insert(thaiText)
                }
            }

            print("📊 Unike ord: \(uniqueWords.count)")

            // Konverter til JSON-format for PyThaiNLP
            let jsonArray: [[String: Any]] = uniqueWords.sorted().map { word in
                return [
                    "text": word,
                    "ipa": "",           // Genereres av PyThaiNLP
                    "syllables": []      // Genereres av PyThaiNLP
                ]
            }

            // Skriv til fil (i Documents-mappen for enkel tilgang)
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let outputURL = documentsPath.appendingPathComponent("all_thai_words.json")

            let jsonData = try JSONSerialization.data(withJSONObject: jsonArray, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: outputURL)

            print("\n✅ Eksportert til:")
            print("   \(outputURL.path)")
            print("\n📋 Kopier filen til Resources:")
            print("   cp '\(outputURL.path)' /Users/geirlapstuen/Swift/gNorsk/Resources/all_thai_words.json")
            print("\n🔧 Kjør deretter Python-scriptet:")
            print("   cd /Users/geirlapstuen/Swift/gNorsk/Scripts")
            print("   python3 generate_thai_data.py")

            // Vis melding til bruker
            #if os(iOS)
            UIPasteboard.general.string = outputURL.path
            #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(outputURL.path, forType: .string)
            #endif

            Notifier.shared.show(.success, "Eksportert \(uniqueWords.count) ord til \(outputURL.lastPathComponent)")

        } catch {
            print("❌ Feil ved eksport: \(error)")
            Notifier.shared.show(.error, "Eksport feilet: \(error.localizedDescription)")
        }
    }

    /// Eksporter til en spesifikk fil
    static func exportAllWords(context: NSManagedObjectContext, to outputURL: URL) {
        print("🚀 Eksporterer til: \(outputURL.path)")

        let fetchRequest: NSFetchRequest<ThaiWords> = ThaiWords.fetchRequest()

        do {
            let allWords = try context.fetch(fetchRequest)

            var uniqueWords = Set<String>()
            for word in allWords {
                if let thaiText = word.thaiWord?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !thaiText.isEmpty {
                    uniqueWords.insert(thaiText)
                }
            }

            let jsonArray: [[String: Any]] = uniqueWords.sorted().map { word in
                return [
                    "text": word,
                    "ipa": "",
                    "syllables": []
                ]
            }

            let jsonData = try JSONSerialization.data(withJSONObject: jsonArray, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: outputURL)

            print("✅ Eksportert \(uniqueWords.count) ord")

        } catch {
            print("❌ Feil: \(error)")
        }
    }
}

// MARK: - Convenience View Modifier

extension View {
    /// Legg til en debug-knapp for å eksportere alle ord
    func withExportButton(context: NSManagedObjectContext) -> some View {
        self.toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    ThaiWordsExporter.exportAllWords(context: context)
                }) {
                    Label("Eksporter ord", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}
