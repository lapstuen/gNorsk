//
//  WordList+CoreDataProperties.swift
//  gThai
//

import Foundation
import CoreData

extension WordList {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<WordList> {
        NSFetchRequest<WordList>(entityName: "WordList")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var wordsText: String?
    @NSManaged public var createdDate: Date?
}

// MARK: - Word management (samme prinsipp som ThaiWords.tags)
extension WordList {

    /// Henter alle ord i listen som array, i den rekkefølgen de ble lagt inn.
    var wordsArray: [String] {
        guard let wordsText, !wordsText.isEmpty else { return [] }
        return wordsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Setter ordene fra et array (lagres linje for linje).
    func setWords(_ newWords: [String]) {
        wordsText = newWords.isEmpty ? nil : newWords.joined(separator: "\n")
    }

    /// Legger til et ord (unngår duplikater).
    func addWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var current = wordsArray
        guard !current.contains(trimmed) else { return }
        current.append(trimmed)
        setWords(current)
    }

    /// Fjerner et ord fra listen.
    func removeWord(_ word: String) {
        var current = wordsArray
        current.removeAll { $0 == word }
        setWords(current)
    }
}
